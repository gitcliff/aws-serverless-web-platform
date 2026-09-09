.PHONY: init validate plan apply destroy test fmt fmt-check lint security-scan checkov install-dev install-hooks

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

checkov:
	cd $(TF_DIR) && checkov -d .

test:
	.venv/bin/pytest tests/ -v

install-dev:
	python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt

install-hooks:
	pre-commit install
