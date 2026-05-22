# policies/opa/main.rego
# OPA policies for Terraform IaC governance
# Evaluated against: terraform show -json plan output

package terraform.policies

import future.keywords.in
import future.keywords.every

# ─────────────────────────────────────────────
# Entry point — aggregates all deny rules
# All violations are collected here
# ─────────────────────────────────────────────
deny[msg] {
    msg := required_tags_violations[_]
}

deny[msg] {
    msg := allowed_regions_violations[_]
}

deny[msg] {
    msg := no_public_s3_violations[_]
}

deny[msg] {
    msg := encrypted_storage_violations[_]
}

deny[msg] {
    msg := allowed_instance_types_violations[_]
}

deny[msg] {
    msg := no_unrestricted_ingress_violations[_]
}

deny[msg] {
    msg := no_admin_iam_violations[_]
}


# ─────────────────────────────────────────────
# Helper: get all resources being created or updated
# ─────────────────────────────────────────────
changing_resources[resource] {
    resource := input.resource_changes[_]
    actions := resource.change.actions
    "create" in actions
}

changing_resources[resource] {
    resource := input.resource_changes[_]
    actions := resource.change.actions
    "update" in actions
}


# ─────────────────────────────────────────────
# Policy 1: Required Tags
# Every resource must have: Team, Owner, Environment, CostCenter
# ─────────────────────────────────────────────
required_tags := {"Team", "Owner", "Environment", "CostCenter"}

required_tags_violations[msg] {
    resource := changing_resources[_]

    # Only enforce on taggable resource types
    taggable_resource_types[resource.type]

    tags := resource.change.after.tags
    missing := required_tags - {tag | tags[tag]}
    count(missing) > 0

    msg := sprintf(
        "[POLICY-001] Resource '%s' (%s) is missing required tags: %v",
        [resource.address, resource.type, missing]
    )
}

taggable_resource_types := {
    "aws_instance",
    "aws_s3_bucket",
    "aws_rds_instance",
    "aws_db_instance",
    "aws_elasticache_cluster",
    "aws_eks_cluster",
    "aws_lambda_function",
    "aws_lb",
    "aws_alb",
    "aws_sqs_queue",
    "aws_sns_topic",
    "aws_dynamodb_table",
    "aws_vpc",
    "aws_subnet",
    "aws_security_group"
}


# ─────────────────────────────────────────────
# Policy 2: Allowed AWS Regions
# Only approved regions may be used
# ─────────────────────────────────────────────
allowed_regions := {"us-east-1", "us-west-2", "eu-west-1"}

allowed_regions_violations[msg] {
    resource := changing_resources[_]
    region := resource.change.after.region
    not region in allowed_regions

    msg := sprintf(
        "[POLICY-002] Resource '%s' is in disallowed region '%s'. Allowed: %v",
        [resource.address, region, allowed_regions]
    )
}


# ─────────────────────────────────────────────
# Policy 3: No Public S3 Buckets
# S3 buckets must not be publicly accessible
# ─────────────────────────────────────────────
no_public_s3_violations[msg] {
    resource := changing_resources[_]
    resource.type == "aws_s3_bucket_acl"
    resource.change.after.acl == "public-read"

    msg := sprintf(
        "[POLICY-003] S3 bucket '%s' is set to public-read ACL. S3 buckets must be private.",
        [resource.address]
    )
}

no_public_s3_violations[msg] {
    resource := changing_resources[_]
    resource.type == "aws_s3_bucket_public_access_block"
    resource.change.after.block_public_acls == false

    msg := sprintf(
        "[POLICY-003] S3 bucket '%s' has block_public_acls disabled.",
        [resource.address]
    )
}


# ─────────────────────────────────────────────
# Policy 4: Encrypted Storage at Rest
# EBS, RDS, and S3 must be encrypted
# ─────────────────────────────────────────────
encrypted_storage_violations[msg] {
    resource := changing_resources[_]
    resource.type == "aws_instance"
    block_device := resource.change.after.root_block_device[_]
    block_device.encrypted != true

    msg := sprintf(
        "[POLICY-004] EC2 instance '%s' has an unencrypted root block device.",
        [resource.address]
    )
}

encrypted_storage_violations[msg] {
    resource := changing_resources[_]
    resource.type in {"aws_db_instance", "aws_rds_instance"}
    resource.change.after.storage_encrypted != true

    msg := sprintf(
        "[POLICY-004] RDS instance '%s' does not have storage_encrypted = true.",
        [resource.address]
    )
}

encrypted_storage_violations[msg] {
    resource := changing_resources[_]
    resource.type == "aws_ebs_volume"
    resource.change.after.encrypted != true

    msg := sprintf(
        "[POLICY-004] EBS volume '%s' is not encrypted.",
        [resource.address]
    )
}


# ─────────────────────────────────────────────
# Policy 5: Allowed EC2 Instance Types
# Prevent accidentally provisioning massive/expensive instances
# ─────────────────────────────────────────────
allowed_instance_types := {
    "t3.micro", "t3.small", "t3.medium", "t3.large",
    "t3.xlarge", "t3.2xlarge",
    "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge",
    "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge",
    "r5.large", "r5.xlarge", "r5.2xlarge"
}

allowed_instance_types_violations[msg] {
    resource := changing_resources[_]
    resource.type == "aws_instance"
    instance_type := resource.change.after.instance_type
    not instance_type in allowed_instance_types

    msg := sprintf(
        "[POLICY-005] EC2 instance '%s' uses disallowed instance type '%s'. Submit an exception request for larger sizes.",
        [resource.address, instance_type]
    )
}


# ─────────────────────────────────────────────
# Policy 6: No Unrestricted Security Group Ingress
# 0.0.0.0/0 ingress is not allowed on sensitive ports
# ─────────────────────────────────────────────
sensitive_ports := {22, 3389, 3306, 5432, 6379, 27017, 9200}

no_unrestricted_ingress_violations[msg] {
    resource := changing_resources[_]
    resource.type == "aws_security_group"
    rule := resource.change.after.ingress[_]
    rule.cidr_blocks[_] == "0.0.0.0/0"
    port := rule.from_port
    port in sensitive_ports

    msg := sprintf(
        "[POLICY-006] Security group '%s' allows unrestricted ingress (0.0.0.0/0) on sensitive port %d.",
        [resource.address, port]
    )
}

no_unrestricted_ingress_violations[msg] {
    resource := changing_resources[_]
    resource.type == "aws_security_group_rule"
    resource.change.after.type == "ingress"
    resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
    port := resource.change.after.from_port
    port in sensitive_ports

    msg := sprintf(
        "[POLICY-006] Security group rule '%s' allows unrestricted ingress on sensitive port %d.",
        [resource.address, port]
    )
}


# ─────────────────────────────────────────────
# Policy 7: No Wildcard IAM Admin Policies
# Prevents accidental privilege escalation
# ─────────────────────────────────────────────
no_admin_iam_violations[msg] {
    resource := changing_resources[_]
    resource.type in {"aws_iam_policy", "aws_iam_role_policy"}

    policy_doc := json.unmarshal(resource.change.after.policy)
    statement := policy_doc.Statement[_]
    statement.Effect == "Allow"
    statement.Action == "*"
    statement.Resource == "*"

    msg := sprintf(
        "[POLICY-007] IAM policy '%s' grants wildcard admin (*:*) permissions. Use least-privilege policies.",
        [resource.address]
    )
}
