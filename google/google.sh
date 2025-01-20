sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates gnupg curl
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
sudo curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
sudo apt-get update && sudo apt-get install google-cloud-sdk google-cloud-cli
gcloud auth application-default login
gcloud init
gcloud auth application-default login
terraform init
terraform fmt
terraform validate

terraform apply
ssh -i ~/.ssh/id_rsa hpcn@$(terraform output -raw head_public_ip) tail -f /home/hpcn/log.out
ssh -i ~/.ssh/id_rsa hpcn@$(terraform output -raw head_public_ip) << EOF
source /etc/profile.d/slurm.sh
/home/hpcn/exec.sh
EOF
scp -i ~/.ssh/id_rsa hpcn@$(terraform output -raw head_public_ip):/nfs/mpi/reports/$datetime/report.txt ./report.txt
cat report.txt
