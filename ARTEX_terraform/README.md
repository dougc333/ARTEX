# ARTEX AWS Terraform deployment

This Terraform configuration provisions an isolated Ubuntu EC2 sandbox for the
ARTEX Docker Compose stack. The instance clones the maintained fork:

```text
https://github.com/dougc333/ARTEX.git
```

## Deploy

```bash
cd ARTEX_terraform/terraform
cp terraform.tfvars.example terraform.tfvars
# Set admin_cidr and key_name in terraform.tfvars.
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Do not commit `terraform.tfvars`, state files, `.env`, or API credentials.
