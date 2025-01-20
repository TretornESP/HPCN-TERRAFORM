echo digitalocean_token = "changeme" >> terraform.tfvars

terraform init
terraform fmt
terraform validate

ssh -i ~/.ssh/id_rsa root@$(terraform output -raw head_public_ip) tail -f /root/log.out
ssh -i ~/.ssh/id_rsa root@$(terraform output -raw head_public_ip) << EOF
source /etc/profile.d/slurm.sh
/root/exec.sh
EOF
scp -i ~/.ssh/id_rsa root@$(terraform output -raw head_public_ip):/nfs/mpi/reports/$datetime/report.txt ./report.txt
cat report.txt