# State key can be overridden per environment:
#   terraform init -backend-config="key=prod/terraform.tfstate"
terraform {
  backend "s3" {
    bucket       = "cliff-terraform-state-storage-bucket"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
