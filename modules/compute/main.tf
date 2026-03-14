# ── SECURITY GROUPS ───────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "ALB: HTTP/HTTPS from internet only"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP - redirected to HTTPS by ALB listener rule"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-alb-sg" })
}

resource "aws_security_group" "app" {
  name        = "${var.project}-${var.environment}-app-sg"
  description = "App servers: traffic from ALB and bastion only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "App traffic from ALB only — not internet"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
    description     = "SSH from bastion host only — not internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-app-sg" })
}

resource "aws_security_group" "bastion" {
  name        = "${var.project}-${var.environment}-bastion-sg"
  description = "Bastion: SSH from admin IPs only"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    description = "SSH from approved admin IPs only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-bastion-sg" })
}

# ── IAM ROLE FOR EC2 ─────────────────────────────────────────────
resource "aws_iam_role" "app" {
  name = "${var.project}-${var.environment}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.common_tags
}

# SSM access — no SSH keys needed for session manager
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 read access — scoped to project bucket only
resource "aws_iam_policy" "s3_app" {
  name = "${var.project}-${var.environment}-app-s3-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.project}-${var.environment}-assets",
        "arn:aws:s3:::${var.project}-${var.environment}-assets/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.s3_app.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-${var.environment}-app-profile"
  role = aws_iam_role.app.name
}

# ── LAUNCH TEMPLATE ───────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile { name = aws_iam_instance_profile.app.name }

  # IMDSv2 only — security best practice
  # Prevents SSRF attacks from accessing instance metadata
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"    # Forces IMDSv2
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }    # Detailed CloudWatch metrics

  user_data = base64encode(var.user_data)

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.project}-${var.environment}-app"
    })
  }
}

# ── AUTO SCALING GROUP ────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = "${var.project}-${var.environment}-asg"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  # Mixed instances for cost optimization in non-prod
  dynamic "mixed_instances_policy" {
    for_each = var.use_spot_instances ? [1] : []
    content {
      instances_distribution {
        on_demand_base_capacity                  = 1
        on_demand_percentage_above_base_capacity = 0
        spot_allocation_strategy                 = "price-capacity-optimized"
      }
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.app.id
          version            = "$Latest"
        }
      }
    }
  }

  dynamic "launch_template" {
    for_each = var.use_spot_instances ? [] : [1]
    content {
      id      = aws_launch_template.app.id
      version = "$Latest"
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-app"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project}-${var.environment}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

# ── APPLICATION LOAD BALANCER ─────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Access logs to S3 for audit trail
  access_logs {
    bucket  = "${var.project}-${var.environment}-alb-logs"
    enabled = true
  }

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-alb" })
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project}-${var.environment}-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = var.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Redirect all HTTP to HTTPS
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
