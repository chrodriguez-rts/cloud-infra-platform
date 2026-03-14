# ── VPC ──────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

# ── THREE SUBNET TIERS ───────────────────────────────────────────
# Public: Load balancers, bastion hosts
# Private: Application servers
# Database: RDS, ElastiCache — no internet route at all

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 4)
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

resource "aws_subnet" "database" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 8)
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-db-${var.azs[count.index]}"
    Tier = "database"
  })
}

# ── INTERNET GATEWAY ─────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

# ── NAT GATEWAY ──────────────────────────────────────────────────
# Cost optimization: single NAT GW for non-prod, one per AZ for prod
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.azs)
  domain = "vpc"
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-nat-eip-${count.index}"
  })
}

resource "aws_nat_gateway" "main" {
  count         = var.single_nat_gateway ? 1 : length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-nat-${count.index}"
  })
}

# ── ROUTE TABLES ─────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-public-rt"
  })
}

resource "aws_route_table" "private" {
  count  = var.single_nat_gateway ? 1 : length(var.azs)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-private-rt-${count.index}"
  })
}

# Route table associations
resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[
    var.single_nat_gateway ? 0 : count.index
  ].id
}

# ── VPC ENDPOINTS ────────────────────────────────────────────────
# S3 Gateway Endpoint — free, keeps S3 traffic off internet
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-s3-endpoint"
  })
}

# ── VPC FLOW LOGS ─────────────────────────────────────────────────
# Security: capture all network traffic metadata for audit
resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flowlogs/${var.project}-${var.environment}"
  retention_in_days = 30
  tags              = var.common_tags
}

resource "aws_iam_role" "flow_log" {
  name = "${var.project}-${var.environment}-flow-log-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  role = aws_iam_role.flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}
