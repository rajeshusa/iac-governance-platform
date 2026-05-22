# terraform/environments/staging/terraform.tfvars

aws_region         = "us-east-1"
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
app_ami_id         = "ami-0abcdef1234567890"  # Replace with your AMI
team               = "platform-engineering"
owner              = "platform-team@mycompany.com"
cost_center        = "CC-1234"
# db_password: injected via TF_VAR_db_password env var in CI — never stored here
