provider "google" {
  project = "hpcn-448319"
  region  = "us-central1"
  zone    = "us-central1-c"
}

variable "head_vm_hostname" {
  type    = string
  default = "head"
}

variable "worker_vm_hostname" {
  type    = string
  default = "worker"
}

variable "worker_count" {
  type    = number
  default = 4
}

variable "head_instance" {
  type    = string
  default = "e2-medium"
}

variable "worker_instance" {
  type    = string
  default = "e2-medium"
}

resource "google_compute_network" "main" {
  name                    = "hpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "hpc-subnet"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.main.id
  region        = "us-central1"
}

resource "google_compute_router" "nat_router" {
  name    = "hpc-router"
  network = google_compute_network.main.id
  region  = "us-central1"
}

resource "google_compute_router_nat" "nat_config" {
  name                               = "hpc-nat"
  router                             = google_compute_router.nat_router.name
  region                             = "us-central1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.1.0/24"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "head" {
  name         = "head"
  machine_type = var.head_instance
  zone         = "us-central1-c"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.main.id
    subnetwork = google_compute_subnetwork.main.id
    access_config {}
  }

  metadata = {
    ssh-keys = "hpcn:${file("~/.ssh/id_rsa.pub")}"
  }

  metadata_startup_script = <<EOT
#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/home/hpcn/log.out 2>&1
apt-get update
apt-get install -y nfs-kernel-server libmunge-dev munge openmpi-bin openmpi-common libopenmpi-dev libdbus-1-dev
apt-get install -y openssl libssl-dev libpam-dev numactl hwloc lua5.4 libreadline-dev rrdtool libncurses-dev man2html libibmad-dev libibumad-dev bzip2 build-essential dnsutils bc
mkdir -p /nfs/mpi
chown -R nobody:nogroup /nfs/
chmod -R 777 /nfs/

# Dynamically export the NFS share based on private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "/nfs $PRIVATE_IP/24(rw,sync,no_subtree_check)" >> /etc/exports
exportfs -a
systemctl restart nfs-kernel-server

# Configure Munge
echo "welcometoslurmgcpuserwelcometoslurmgcpuserwelcometoslurmgcpuser" | tee /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 600 /etc/munge/munge.key
chown -R munge /etc/munge/ /var/log/munge/
chmod 0700 /etc/munge/ /var/log/munge/
systemctl enable munge
systemctl start munge
sleep 15

cd /home/hpcn
wget -q https://download.schedmd.com/slurm/slurm-22.05-latest.tar.bz2
tar -xvf /home/hpcn/slurm-*.tar.bz2 -C /home/hpcn
cd /home/hpcn/slurm-*
/home/hpcn/slurm-*/configure --prefix=/nfs/slurm
make -j 4
make install
sleep 5
export SLURM_HOME=/nfs/slurm
mkdir -p $SLURM_HOME/etc/slurm
'cp' /home/hpcn/slurm-*/etc/* $SLURM_HOME/etc/slurm
'cp' $SLURM_HOME/etc/slurm/cgroup.conf.example $SLURM_HOME/etc/cgroup.conf
cat > $SLURM_HOME/etc/slurm.conf <<'EOF'
ClusterName=changeme
ControlMachine=${var.head_vm_hostname}
ControlAddr=PRIVATE_IP
SlurmdUser=root
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
StateSaveLocation=/var/spool/slurm/ctld
SlurmdSpoolDir=/var/spool/slurm
SwitchType=switch/none
MpiDefault=none
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmdPidFile=/var/run/slurmd.pid
ProctrackType=proctrack/pgid
ReturnToService=2
# TIMERS
SlurmctldTimeout=300
SlurmdTimeout=60
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0
# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core
# LOGGING
SlurmctldDebug=3
SlurmctldLogFile=/var/log/slurmctld.log
SlurmdDebug=3
SlurmdLogFile=/var/log/slurmd.log
DebugFlags=NO_CONF_HASH
JobCompType=jobcomp/none
# DYNAMIC COMPUTE NODES
MaxNodeCount=8
TreeWidth=65533
PartitionName=aws Nodes=ALL Default=YES MaxTime=INFINITE State=UP
EOF

cat > $SLURM_HOME/etc/slurm/slurmd.service <<EOF
[Unit]
Description=Slurm node daemon
After=munge.service network.target remote-fs.target
[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmd
ExecStart=/nfs/slurm/sbin/slurmd -N @SLURM_NODENAME@ -Z -vv
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
[Install]
WantedBy=multi-user.target
EOF

cat > $SLURM_HOME/etc/slurm/slurmctld.service <<EOF
[Unit]
Description=Slurm controller daemon
After=network.target munge.service
ConditionPathExists=/nfs/slurm/etc/slurm.conf
[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmctld
ExecStart=/nfs/slurm/sbin/slurmctld -vv
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/slurmctld.pid
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

sed -i "s|PRIVATE_IP|$PRIVATE_IP|" $SLURM_HOME/etc/slurm.conf
echo 'export SLURM_HOME=/nfs/slurm' | tee /etc/profile.d/slurm.sh
echo 'export SLURM_CONF=$SLURM_HOME/etc/slurm.conf' | tee -a /etc/profile.d/slurm.sh
echo 'export PATH=/nfs/slurm/bin:$PATH' | tee -a /etc/profile.d/slurm.sh

# Launch Slurmctld
mkdir -p /var/spool/slurm
'cp' /nfs/slurm/etc/slurm/slurmd.service /lib/systemd/system
'cp' /nfs/slurm/etc/slurm/slurmctld.service /lib/systemd/system
systemctl restart munge.service
systemctl enable slurmctld
systemctl start slurmctld
touch /nfs/headnode_started
wget https://raw.githubusercontent.com/TretornESP/HPCN-VIRTUAL-CLUSTERS/refs/heads/main/execute.sh -O /home/hpcn/exec.sh
chmod +x /home/hpcn/exec.sh
echo "Slurmctld started"
EOT
}

resource "google_compute_instance" "worker" {
  count        = var.worker_count
  name         = "${var.worker_vm_hostname}-${count.index}"
  machine_type = var.worker_instance
  zone         = "us-central1-c"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.main.id
    subnetwork = google_compute_subnetwork.main.id
  }

  metadata = {
    ssh-keys = "hpcn:${file("~/.ssh/id_rsa.pub")}"
  }

  metadata_startup_script = <<EOT
#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/home/hpcn/log.out 2>&1
apt-get update
apt-get install -y nfs-kernel-server libmunge-dev munge openmpi-bin openmpi-common libopenmpi-dev libdbus-1-dev
apt-get install -y openssl libssl-dev libpam-dev numactl hwloc lua5.4 libreadline-dev rrdtool libncurses-dev man2html libibmad-dev libibumad-dev bzip2 build-essential dnsutils bc
# Configure Munge
mkdir -p /etc/munge
echo "welcometoslurmgcpuserwelcometoslurmgcpuserwelcometoslurmgcpuser" | tee /etc/munge/munge.key
chown -R munge:munge /etc/munge/munge.key
chmod 600 /etc/munge/munge.key
chown -R munge /etc/munge/ /var/log/munge/
chmod 0700 /etc/munge/ /var/log/munge/
systemctl enable munge
systemctl start munge
sleep 180

mkdir -p /nfs/reports
# Mount the NFS share dynamically based on the head node's private IP
mount -t nfs ${google_compute_instance.head.network_interface.0.network_ip}:/nfs /nfs
chown nobody:nogroup /nfs
chmod 777 /nfs
echo "${google_compute_instance.head.network_interface.0.network_ip}:/nfs /nfs nfs defaults 0 0" >> /etc/fstab
export SLURM_HOME=/nfs/slurm

#wait for headnode to start
echo "Waiting for headnode to start..."
until [ -f /nfs/headnode_started ]; do
  sleep 1
done
echo "Headnode started"

# Set environment variables
echo 'export SLURM_HOME=/nfs/slurm' | tee /etc/profile.d/slurm.sh
echo 'export SLURM_CONF=$SLURM_HOME/etc/slurm.conf' | tee -a /etc/profile.d/slurm.sh
echo 'export SLURM_NODENAME=${var.worker_vm_hostname}-${count.index}' | tee -a /etc/profile.d/slurm.sh
echo 'export PATH=/nfs/slurm/bin:$PATH' | tee -a /etc/profile.d/slurm.sh

mkdir -p /var/spool/slurm
chmod 777 /var/spool/slurm
sed "s|@SLURM_NODENAME@|${var.worker_vm_hostname}-${count.index}|" $SLURM_HOME/etc/slurm/slurmd.service > /lib/systemd/system/slurmd.service
systemctl restart munge.service
systemctl enable slurmd.service
systemctl start slurmd.service

echo "Slurmd started"
EOT
}

output "head_public_ip_address" {
  value = google_compute_instance.head.network_interface.0.access_config.0.nat_ip
}