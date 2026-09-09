terraform {
  backend "s3" {
    bucket       = "cliff-terraform-state-storage-bucket"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
