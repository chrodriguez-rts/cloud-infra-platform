locals {
  project     = "myapp"
  environment = "dev"
  region      = "us-east-1"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = "chris"
    CostCenter  = "engineering"
  }
}

module "networking" {
  source = "../../modules/networking"

  project            = local.project
  environment        = local.environment
  region             = local.region
  vpc_cidr           = "10.0.0.0/16"
  azs                = ["us-east-1a", "us-east-1b"]
  common_tags        = local.common_tags
  single_nat_gateway = true    # Dev: single NAT saves ~$30/month
}

module "compute" {
  source = "../../modules/compute"

  project             = local.project
  environment         = local.environment
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  common_tags         = local.common_tags

  instance_type      = "t3.micro"
  desired_capacity   = 1       # Dev: minimum instances
  min_size           = 1
  max_size           = 2
  use_spot_instances = true    # Dev: spot for 60-70% cost savings
  cpu_target_value   = 60.0
  admin_cidr_blocks  = ["YOUR_IP/32"]
  key_name           = "phase1-key"
  ami_id             = data.aws_ami.ubuntu.id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
