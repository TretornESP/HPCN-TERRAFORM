terraform version
export ARM_CLIENT_ID="changeme"
export ARM_CLIENT_SECRET="changeme"
export ARM_SUBSCRIPTION_ID="changeme"
export ARM_TENANT_ID="changeme"

password=$(openssl rand -base64 32)
echo "Save this password: $password, we will ask it again"
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N $password

terraform init
terraform fmt
terraform validate
terraform apply -auto-approve

ssh -i ~/.ssh/id_rsa azureuser@$(terraform output -raw head_public_ip_address) tail -f /home/azureuser/log.out
ssh -i ~/.ssh/id_rsa azureuser@$(terraform output -raw head_public_ip_address) << EOF
source /etc/profile.d/slurm.sh
/home/azureuser/exec.sh
EOF
scp -i ~/.ssh/id_rsa azureuser@$(terraform output -raw head_public_ip_address):/nfs/mpi/reports/$datetime/report.txt ./report.txt
cat report.txt