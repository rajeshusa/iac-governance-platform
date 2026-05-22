# terraform/environments/dev/terraform.tfvars
# Non-sensitive values only — secrets come from AWS Secrets Manager or env vars

aws_region         = "us-east-1"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
team               = "platform-engineering"
owner              = "platform-team@mycompany.com"
cost_center        = "CC-1234"
# pipeline test
