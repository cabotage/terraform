# --- Tailscale Operator IRSA ---
#
# An IRSA role for the in-cluster Tailscale operator so it can call
# sts:GetWebIdentityToken to authenticate to Tailscale via OIDC.

module "tailscale_operator_irsa" {
  count   = var.enable_cabotage_tailscale_ingress ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-tailscale-operator"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.tailscale_operator_namespace}:${var.tailscale_operator_service_account}"]
    }
  }

  tags = local.tags
}

resource "aws_iam_role_policy" "tailscale_operator_sts" {
  count = var.enable_cabotage_tailscale_ingress ? 1 : 0

  name = "sts-web-identity-token-for-tailscale"
  role = module.tailscale_operator_irsa[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowGetWebIdentityTokenForTailscale"
        Effect   = "Allow"
        Action   = "sts:GetWebIdentityToken"
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "sts:IdentityTokenAudience" = var.cabotage_tailscale_workload_identity_audience
          }
          "NumericLessThanEquals" = {
            "sts:DurationSeconds" = "300"
          }
        }
      }
    ]
  })
}

# --- Tailscale Subnet Router (EC2) ---

data "aws_ami" "amazon_linux_2023_arm" {
  count       = var.enable_tailscale_subnet_router && var.tailscale_subnet_router_ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "tailscale_subnet_router" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  name_prefix = "${var.cluster_name}-tailscale-sr-"
  description = "Tailscale subnet router for ${var.cluster_name}"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-tailscale-subnet-router"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "tailscale_subnet_router_all_outbound" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  security_group_id = aws_security_group.tailscale_subnet_router[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound (Tailscale coordination + forwarded traffic)"
}

resource "aws_security_group_rule" "tailscale_to_eks_api" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  description              = "Tailscale subnet router to EKS API server"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = aws_security_group.tailscale_subnet_router[0].id
}

resource "aws_iam_role" "tailscale_subnet_router" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  name_prefix = "${var.cluster_name}-ts-sr-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "tailscale_subnet_router_sts" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  name = "sts-web-identity-token-for-tailscale"
  role = aws_iam_role.tailscale_subnet_router[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowGetWebIdentityTokenForTailscale"
        Effect   = "Allow"
        Action   = "sts:GetWebIdentityToken"
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "sts:IdentityTokenAudience" = var.tailscale_workload_identity_audience
          }
          "NumericLessThanEquals" = {
            "sts:DurationSeconds" = "300"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "tailscale_subnet_router_asg_health" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  name = "asg-set-instance-health"
  role = aws_iam_role.tailscale_subnet_router[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "autoscaling:SetInstanceHealth"
        Resource = "*"
        Condition = {
          "StringEquals" = {
            "autoscaling:ResourceTag/Name" = "${var.cluster_name}-tailscale-subnet-router"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "tailscale_subnet_router" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  name_prefix = "${var.cluster_name}-ts-sr-"
  role        = aws_iam_role.tailscale_subnet_router[0].name
}

resource "aws_launch_template" "tailscale_subnet_router" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  name_prefix   = "${var.cluster_name}-ts-sr-"
  image_id      = var.tailscale_subnet_router_ami_id != "" ? var.tailscale_subnet_router_ami_id : data.aws_ami.amazon_linux_2023_arm[0].id
  instance_type = var.tailscale_subnet_router_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.tailscale_subnet_router[0].arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.tailscale_subnet_router[0].id]
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail

    # Enable IP forwarding
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
    sysctl --system

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh

    # Start Tailscale as a subnet router using workload identity federation
    tailscale up \
      --client-id="${var.tailscale_workload_identity_client_id}" \
      --audience="${var.tailscale_workload_identity_audience}" \
      --advertise-routes="${var.vpc_cidr}" \
      --advertise-tags="${join(",", var.tailscale_subnet_router_tags)}" \
      --accept-dns=false \
      --hostname="${var.tailscale_subnet_router_hostname != "" ? var.tailscale_subnet_router_hostname : "${var.cluster_name}-subnet-router"}-$(ec2-metadata -i | cut -d' ' -f2)"

    # Watchdog: mark instance unhealthy if Tailscale stops running
    cat > /usr/local/bin/tailscale-watchdog.sh << 'WATCHDOG'
    #!/bin/bash
    if ! tailscale status --json | jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
      INSTANCE_ID=$(ec2-metadata -i | cut -d' ' -f2)
      aws autoscaling set-instance-health \
        --instance-id "$INSTANCE_ID" \
        --health-status Unhealthy \
        --region "${data.aws_region.current.id}"
    fi
    WATCHDOG
    chmod +x /usr/local/bin/tailscale-watchdog.sh

    cat > /etc/systemd/system/tailscale-watchdog.service << 'UNIT'
    [Unit]
    Description=Tailscale health watchdog
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/tailscale-watchdog.sh
    UNIT

    cat > /etc/systemd/system/tailscale-watchdog.timer << 'TIMER'
    [Unit]
    Description=Run Tailscale watchdog every minute

    [Timer]
    OnBootSec=60
    OnUnitActiveSec=15

    [Install]
    WantedBy=timers.target
    TIMER

    # Add ExecStop to tailscaled so it logs out before the daemon stops
    mkdir -p /etc/systemd/system/tailscaled.service.d
    cat > /etc/systemd/system/tailscaled.service.d/logout.conf << 'DROP'
    [Service]
    ExecStop=
    ExecStop=/usr/bin/tailscale logout
    ExecStop=/usr/sbin/tailscaled --cleanup
    DROP

    systemctl daemon-reload
    systemctl enable tailscale-watchdog.timer
    systemctl start tailscale-watchdog.timer
  EOT
  )

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "tailscale_subnet_router" {
  count = var.enable_tailscale_subnet_router ? 1 : 0

  name_prefix      = "${var.cluster_name}-ts-sr-"
  min_size         = 2
  max_size         = 3
  desired_capacity = 2

  vpc_zone_identifier = module.vpc.public_subnets

  launch_template {
    id      = aws_launch_template.tailscale_subnet_router[0].id
    version = aws_launch_template.tailscale_subnet_router[0].latest_version
  }

  instance_maintenance_policy {
    min_healthy_percentage = 100
    max_healthy_percentage = 150
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 150
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-tailscale-subnet-router"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
