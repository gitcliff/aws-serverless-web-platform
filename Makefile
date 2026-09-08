.PHONY: init validate plan apply destroy test fmt lint security-scan

TF_DIR := terraform

init:
	cd $(TF_DIR) && terraform init

validate:
	cd $(TF_DIR) && terraform validate

plan:
	cd $(TF_DIR) && terraform plan

apply:
	cd $(TF_DIR) && terraform apply

destroy:
	cd $(TF_DIR) && terraform destroy

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

fmt-check:
	cd $(TF_DIR) && terraform fmt -check -recursive

lint:
	cd $(TF_DIR) && tflint --recursive

security-scan:
	cd $(TF_DIR) && tfsec .

test:
	pytest tests/ -v
