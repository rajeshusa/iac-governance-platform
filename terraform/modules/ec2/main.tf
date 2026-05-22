# terraform/modules/ec2/main.tf
# Governance-compliant EC2 module
# Enforces: IMDSv2, encrypted EBS, no public IP by default, SSM access

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ─────────────────────────────────────────────
# Security Group
# ─────────────────────────────────────────────
resource "aws_security_group" "instance" {
  name        = "${var.name}-sg"
  description = "Security group for ${var.name} EC2 instances"
  vpc_id      = var.vpc_id

  # No ingress from internet — access via SSM or VPN only
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = ingress.value.cidr_blocks
      security_groups = lookup(ingress.value, "security_groups", [])
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-sg"
  })
}

# ─────────────────────────────────────────────
# IAM Role for SSM access (no SSH keys needed)
# ─────────────────────────────────────────────
resource "aws_iam_role" "instance" {
  name = "${var.name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach any additional policies passed in
resource "aws_iam_role_policy_attachment" "additional" {
  count      = length(var.additional_policy_arns)
  role       = aws_iam_role.instance.name
  policy_arn = var.additional_policy_arns[count.index]
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.instance.name
  tags = var.tags
}

# ─────────────────────────────────────────────
# Launch Template
# Enforces: IMDSv2, encrypted root volume, no public IP
# ─────────────────────────────────────────────
resource "aws_launch_template" "main" {
  name_prefix   = "${var.name}-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  # IMDSv2 required — prevents SSRF-based metadata attacks
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # Forces IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Encrypted root volume (satisfies OPA Policy-004 + Checkov CKV_AWS_8)
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_id
      delete_on_termination = true
    }
  }

  # No public IP — instances only reachable via private network
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.instance.id]
    subnet_id                   = var.subnet_ids[0]
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  user_data = var.user_data_base64

  monitoring {
    enabled = true  # Detailed CloudWatch monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = var.name
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.name}-root"
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# ─────────────────────────────────────────────
# Auto Scaling Group
# ─────────────────────────────────────────────
resource "aws_autoscaling_group" "main" {
  name                = "${var.name}-asg"
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  health_check_type         = var.target_group_arns != null ? "ELB" : "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# Attach to load balancer if provided
resource "aws_autoscaling_attachment" "main" {
  count                  = var.target_group_arns != null ? length(var.target_group_arns) : 0
  autoscaling_group_name = aws_autoscaling_group.main.id
  lb_target_group_arn    = var.target_group_arns[count.index]
}

# ─────────────────────────────────────────────
# Auto Scaling Policies
# ─────────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_up" {
  count                  = var.enable_autoscaling ? 1 : 0
  name                   = "${var.name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  count                  = var.enable_autoscaling ? 1 : 0
  name                   = "${var.name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.enable_autoscaling ? 1 : 0
  alarm_name          = "${var.name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.scale_up_cpu_threshold
  alarm_description   = "Scale up when CPU > ${var.scale_up_cpu_threshold}%"
  alarm_actions       = [aws_autoscaling_policy.scale_up[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  count               = var.enable_autoscaling ? 1 : 0
  alarm_name          = "${var.name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.scale_down_cpu_threshold
  alarm_description   = "Scale down when CPU < ${var.scale_down_cpu_threshold}%"
  alarm_actions       = [aws_autoscaling_policy.scale_down[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = var.tags
}
