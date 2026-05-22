# terraform/environments/prod/terraform.tfvars

aws_region         = "us-east-1"
vpc_cidr           = "10.2.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
app_ami_id         = "ami-0abcdef1234567890"  # Replace with your hardened AMI
team               = "platform-engineering"
owner              = "platform-team@mycompany.com"
cost_center        = "CC-1234"
db_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/mrk-abc123"  # Replace
s3_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/mrk-def456"  # Replace
# db_password: injected via TF_VAR_db_password from GitHub Secret — never stored here
