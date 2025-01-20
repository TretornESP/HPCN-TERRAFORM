terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.digitalocean_token
}

variable "digitalocean_token" {
  type        = string
  description = "DigitalOcean API Token"
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

variable "head_instance_size" {
  type    = string
  default = "s-2vcpu-4gb"
}

variable "worker_instance_size" {
  type    = string
  default = "s-2vcpu-4gb"
}

variable "slurm_if" {
  type    = string
  default = "eth1"
}

variable "region" {
  type    = string
  default = "nyc3"
}

resource "digitalocean_vpc" "main" {
  name   = "hpc-vpc"
  region = var.region
}

resource "digitalocean_ssh_key" "default" {
  name       = "default-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "digitalocean_droplet" "head" {
  name     = var.head_vm_hostname
  region   = var.region
  size     = var.head_instance_size
  image    = "debian-12-x64"
  vpc_uuid = digitalocean_vpc.main.id
  ssh_keys = [digitalocean_ssh_key.default.id]

  user_data = <<EOT
#!/bin/bash

#Create user hpcn and add to sudo group
useradd -m -s /bin/bash hpcn
echo "hpcn:hpcn" | chpasswd
usermod -aG sudo hpcn

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/home/hpcn/log.out 2>&1
apt-get update
apt-get install -y nfs-kernel-server libmunge-dev munge openmpi-bin openmpi-common libopenmpi-dev libdbus-1-dev
apt-get install -y openssl libssl-dev libpam-dev numactl hwloc lua5.4 libreadline-dev rrdtool libncurses-dev man2html libibmad-dev libibumad-dev bzip2 build-essential dnsutils bc

mkdir -p /nfs/mpi
chown -R nobody:nogroup /nfs/
chmod -R 777 /nfs

# Dynamically export the NFS share based on private IP
PRIVATE_IP=$(curl -w "\n" http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
CURRENT_HOST=$(hostname)
echo "/nfs $PRIVATE_IP/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -a
systemctl restart nfs-kernel-server

# Configure Munge
echo "welcometoslurmdouserwelcometoslurmdouserwelcometoslurmdouser" | tee /etc/munge/munge.key
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
echo 'export OMPI_MCA_btl_tcp_if_include=${var.slurm_if}' | tee -a /etc/profile.d/slurm.sh

#Add this ip hostname pair to a hosts file in /nfs/hosts
echo "$PRIVATE_IP $CURRENT_HOST" >> /nfs/hosts

rm /etc/hosts
ln -s /nfs/hosts /etc/hosts

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
chmod -R 777 /nfs
echo "Slurmctld started"
EOT
}

resource "digitalocean_droplet" "worker" {
  count    = var.worker_count
  name     = "${var.worker_vm_hostname}-${count.index}"
  region   = var.region
  size     = var.worker_instance_size
  image    = "debian-12-x64"
  vpc_uuid = digitalocean_vpc.main.id
  ssh_keys = [digitalocean_ssh_key.default.id]

  user_data = <<EOT
#!/bin/bash

#Create user hpcn and add to sudo group
useradd -m -s /bin/bash hpcn
echo "hpcn:hpcn" | chpasswd
usermod -aG sudo hpcn

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/home/hpcn/log.out 2>&1
apt-get update

echo "Updating /etc/hosts for LAN hostname resolution"

PRIVATE_IP=$(curl -w "\n" http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
CURRENT_HOST=$(hostname)

apt-get install -y nfs-kernel-server libmunge-dev munge openmpi-bin openmpi-common libopenmpi-dev libdbus-1-dev
apt-get install -y openssl libssl-dev libpam-dev numactl hwloc lua5.4 libreadline-dev rrdtool libncurses-dev man2html libibmad-dev libibumad-dev bzip2 build-essential dnsutils bc
# Configure Munge
mkdir -p /etc/munge
echo "welcometoslurmdouserwelcometoslurmdouserwelcometoslurmdouser" | tee /etc/munge/munge.key
chown -R munge:munge /etc/munge/munge.key
chmod 600 /etc/munge/munge.key
chown -R munge /etc/munge/ /var/log/munge/
chmod 0700 /etc/munge/ /var/log/munge/
systemctl enable munge
systemctl start munge
sleep 180

mkdir -p /nfs/reports
# Mount the NFS share dynamically based on the head node's private IP
mount -t nfs ${digitalocean_droplet.head.ipv4_address_private}:/nfs /nfs
chown nobody:nogroup /nfs
chmod -R 777 /nfs
echo "${digitalocean_droplet.head.ipv4_address_private}:/nfs /nfs nfs defaults 0 0" >> /etc/fstab
export SLURM_HOME=/nfs/slurm

#Add this ip hostname pair to a hosts file in /nfs/hosts
echo "$PRIVATE_IP $CURRENT_HOST" >> /nfs/hosts

rm /etc/hosts
ln -s /nfs/hosts /etc/hosts

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
echo 'export OMPI_MCA_btl_tcp_if_include=${var.slurm_if}' | tee -a /etc/profile.d/slurm.sh

mkdir -p /var/spool/slurm
chmod 777 /var/spool/slurm
sed "s|@SLURM_NODENAME@|${var.worker_vm_hostname}-${count.index}|" $SLURM_HOME/etc/slurm/slurmd.service > /lib/systemd/system/slurmd.service
systemctl restart munge.service
systemctl enable slurmd.service
systemctl start slurmd.service
chmod -R 777 /nfs
echo "Slurmd started"
EOT
}

output "head_public_ip_address" {
  value = digitalocean_droplet.head.ipv4_address
}

output "worker_private_ips" {
  value = [for worker in digitalocean_droplet.worker : worker.ipv4_address_private]
}
