#!/bin/bash

#In case of azure, fill this variables
export ARM_CLIENT_ID="changeme"
export ARM_CLIENT_SECRET="changeme"
export ARM_SUBSCRIPTION_ID="changeme"
export ARM_TENANT_ID="changeme"

#In case of digitalocean, uncomment this line
#echo digitalocean_token = "changeme" >> terraform.tfvars

#Google installation
#sudo apt-get update
#sudo apt-get install apt-transport-https ca-certificates gnupg curl
#echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
#sudo curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
#sudo apt-get update && sudo apt-get install google-cloud-sdk google-cloud-cli

#Azure installation
#sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
#wget -O- https://apt.releases.hashicorp.com/gpg | \
#gpg --dearmor | \
#sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
#echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
#https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
#sudo tee /etc/apt/sources.list.d/hashicorp.list
#sudo apt update && sudo apt install terraform
#terraform version

#SSH Key generation
#password=$(openssl rand -base64 32)
#echo "Save this password: $password, we will ask it again"
#echo "$password" > password.txt
#ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N $password

#Generic installation
#terraform init

#Configuration
username="hpcn" #hpcn for google and digitalocean, azureuser for azure

terraform fmt
terraform validate
terraform apply

ssh -i ~/.ssh/id_rsa $username@$(terraform output -raw head_public_ip_address) tail -f /home/$username/log.out
ssh -i ~/.ssh/id_rsa $username@$(terraform output -raw head_public_ip_address) << EOF
source /etc/profile.d/slurm.sh
/home/$username/exec.sh
tar -czvf /home/$username/reports.tar.gz /nfs/mpi/reports
EOF
scp -i ~/.ssh/id_rsa $username@$(terraform output -raw head_public_ip_address):/home/$username/reports.tar.gz ./reports.tar.gz
echo "Reports saved in reports.tar.gz"
