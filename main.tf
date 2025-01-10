provider "azurerm" {
  features {}
}

variable "head_vm_hostname" {
  type = string
  default = "head"
}

variable "worker_vm_hostname" {
  type = string
  default = "worker"
}

resource "azurerm_resource_group" "main" {
  name     = "HPC-Cluster"
  location = "East US"
}

resource "azurerm_virtual_network" "main" {
  name                = "HPC-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "HPC-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "head_nsg" {
  name                = "head-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "head" {
  name                = "head-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.head.id
  }
}

resource "azurerm_public_ip" "head" {
  name                = "head-public-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "worker" {
  name                = "worker-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "head" {
  name                = "head"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.head.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-12"
    sku       = "12"
    version   = "latest"
  }

  custom_data = base64encode(<<EOT
#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/home/azureuser/log.out 2>&1
apt-get update
apt-get install -y nfs-kernel-server libmunge-dev munge openmpi-bin openmpi-common libopenmpi-dev libdbus-1-dev
apt-get install -y openssl libssl-dev libpam-dev numactl hwloc lua5.4 libreadline-dev rrdtool libncurses-dev man2html libibmad-dev libibumad-dev bzip2 build-essential dnsutils
mkdir -p /nfs/mpi
chown -R nobody:nogroup /nfs/
chmod -R 777 /nfs/

# Dynamically export the NFS share based on private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "/nfs $PRIVATE_IP/24(rw,sync,no_subtree_check)" >> /etc/exports
exportfs -a
systemctl restart nfs-kernel-server

# Configure Munge
echo "welcometoslurmamazonuserwelcometoslurmamazonuserwelcometoslurmamazonuser" | tee /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 600 /etc/munge/munge.key
chown -R munge /etc/munge/ /var/log/munge/
chmod 0700 /etc/munge/ /var/log/munge/
systemctl enable munge
systemctl start munge
sleep 15

cd /home/azureuser
wget -q https://download.schedmd.com/slurm/slurm-22.05-latest.tar.bz2
tar -xvf /home/azureuser/slurm-*.tar.bz2 -C /home/azureuser
cd /home/azureuser/slurm-*
/home/azureuser/slurm-*/configure --prefix=/nfs/slurm
make -j 4
make install
sleep 5
export SLURM_HOME=/nfs/slurm
mkdir -p $SLURM_HOME/etc/slurm
'cp' /home/azureuser/slurm-*/etc/* $SLURM_HOME/etc/slurm
'cp' $SLURM_HOME/etc/slurm/cgroup.conf.example $SLURM_HOME/etc/cgroup.conf
cat > $SLURM_HOME/etc/slurm.conf <<'EOF'
ClusterName=changeme
ControlMachine=${var.head_vm_hostname}
ControlAddr=${azurerm_network_interface.head.private_ip_address}
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
wget https://raw.githubusercontent.com/TretornESP/HPCN-VIRTUAL-CLUSTERS/refs/heads/main/execute.sh -O /home/azureuser/exec.sh
chmod +x /home/azureuser/exec.sh
echo "Slurmctld started"
EOT
  )
}

resource "azurerm_linux_virtual_machine" "worker" {
  name                = "worker"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.worker.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-12"
    sku       = "12"
    version   = "latest"
  }

  custom_data = base64encode(<<EOT
#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/home/azureuser/log.out 2>&1
apt-get update
apt-get install -y nfs-kernel-server libmunge-dev munge openmpi-bin openmpi-common libopenmpi-dev libdbus-1-dev
apt-get install -y openssl libssl-dev libpam-dev numactl hwloc lua5.4 libreadline-dev rrdtool libncurses-dev man2html libibmad-dev libibumad-dev bzip2 build-essential dnsutils
# Configure Munge
mkdir -p /etc/munge
echo "welcometoslurmamazonuserwelcometoslurmamazonuserwelcometoslurmamazonuser" | tee /etc/munge/munge.key
chown -R munge:munge /etc/munge/munge.key
chmod 600 /etc/munge/munge.key
chown -R munge /etc/munge/ /var/log/munge/
chmod 0700 /etc/munge/ /var/log/munge/
systemctl enable munge
systemctl start munge
sleep 180

mkdir -p /nfs/reports
# Mount the NFS share dynamically based on the head node's private IP
mount -t nfs ${azurerm_network_interface.head.private_ip_address}:/nfs /nfs
chown nobody:nogroup /nfs
chmod 777 /nfs
echo "${azurerm_network_interface.head.private_ip_address}:/nfs /nfs nfs defaults 0 0" >> /etc/fstab
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
echo 'export SLURM_NODENAME=${var.worker_vm_hostname}' | tee -a /etc/profile.d/slurm.sh
echo 'export PATH=/nfs/slurm/bin:$PATH' | tee -a /etc/profile.d/slurm.sh

mkdir -p /var/spool/slurm
chmod 777 /var/spool/slurm
sed "s|@SLURM_NODENAME@|${var.worker_vm_hostname}|" $SLURM_HOME/etc/slurm/slurmd.service > /lib/systemd/system/slurmd.service
systemctl restart munge.service
systemctl enable slurmd.service
systemctl start slurmd.service

echo "Slurmd started"
EOT
  )
}

output "head_public_ip_address" {
  value = azurerm_linux_virtual_machine.head.public_ip_address
}

output "head_private_ip_address" {
  value = azurerm_network_interface.head.private_ip_address
}

output "worker_private_ip_address" {
  value = azurerm_network_interface.worker.private_ip_address
}