# policies/opa/main_test.rego
# Unit tests for OPA governance policies
# Run with: opa test policies/opa/ -v

package terraform.policies

# ─────────────────────────────────────────────
# Test: Required Tags — PASS (all tags present)
# ─────────────────────────────────────────────
test_required_tags_pass if {
    count(required_tags_violations) == 0 with input as {
        "resource_changes": [{
            "address": "module.vpc.aws_vpc.main",
            "type": "aws_vpc",
            "change": {
                "actions": ["create"],
                "after": {
                    "tags": {
                        "Team": "platform",
                        "Owner": "team@company.com",
                        "Environment": "dev",
                        "CostCenter": "CC-1234"
                    }
                }
            }
        }]
    }
}

# ─────────────────────────────────────────────
# Test: Required Tags — FAIL (missing tags)
# ─────────────────────────────────────────────
test_required_tags_fail if {
    count(required_tags_violations) > 0 with input as {
        "resource_changes": [{
            "address": "aws_instance.web",
            "type": "aws_instance",
            "change": {
                "actions": ["create"],
                "after": {
                    "tags": {
                        "Name": "web-server"
                        # Missing: Team, Owner, Environment, CostCenter
                    }
                }
            }
        }]
    }
}

# ─────────────────────────────────────────────
# Test: Allowed Regions — PASS
# ─────────────────────────────────────────────
test_allowed_region_pass if {
    count(allowed_regions_violations) == 0 with input as {
        "resource_changes": [{
            "address": "aws_instance.web",
            "type": "aws_instance",
            "change": {
                "actions": ["create"],
                "after": {"region": "us-east-1"}
            }
        }]
    }
}

# ─────────────────────────────────────────────
# Test: Allowed Regions — FAIL (ap-southeast-1 not allowed)
# ─────────────────────────────────────────────
test_allowed_region_fail if {
    count(allowed_regions_violations) > 0 with input as {
        "resource_changes": [{
            "address": "aws_instance.web",
            "type": "aws_instance",
            "change": {
                "actions": ["create"],
                "after": {"region": "ap-southeast-1"}
            }
        }]
    }
}

# ─────────────────────────────────────────────
# Test: No Unrestricted Ingress — FAIL (SSH open to world)
# ─────────────────────────────────────────────
test_no_unrestricted_ssh_fail if {
    count(no_unrestricted_ingress_violations) > 0 with input as {
        "resource_changes": [{
            "address": "aws_security_group.allow_ssh",
            "type": "aws_security_group",
            "change": {
                "actions": ["create"],
                "after": {
                    "ingress": [{
                        "from_port": 22,
                        "to_port": 22,
                        "protocol": "tcp",
                        "cidr_blocks": ["0.0.0.0/0"]
                    }]
                }
            }
        }]
    }
}

# ─────────────────────────────────────────────
# Test: No Unrestricted Ingress — PASS (restricted CIDR)
# ─────────────────────────────────────────────
test_no_unrestricted_ssh_pass if {
    count(no_unrestricted_ingress_violations) == 0 with input as {
        "resource_changes": [{
            "address": "aws_security_group.allow_ssh",
            "type": "aws_security_group",
            "change": {
                "actions": ["create"],
                "after": {
                    "ingress": [{
                        "from_port": 22,
                        "to_port": 22,
                        "protocol": "tcp",
                        "cidr_blocks": ["10.0.0.0/8"]  # Internal only
                    }]
                }
            }
        }]
    }
}

# ─────────────────────────────────────────────
# Test: Encryption — FAIL (unencrypted RDS)
# ─────────────────────────────────────────────
test_unencrypted_rds_fail if {
    count(encrypted_storage_violations) > 0 with input as {
        "resource_changes": [{
            "address": "aws_db_instance.main",
            "type": "aws_db_instance",
            "change": {
                "actions": ["create"],
                "after": {
                    "storage_encrypted": false
                }
            }
        }]
    }
}
