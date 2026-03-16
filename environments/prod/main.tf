locals {
  project     = "myapp"
  environment = "prod"
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
  single_nat_gateway = false   # Prod: one NAT per AZ for HA
}

module "compute" {
  source = "../../modules/compute"

  project             = local.project
  environment         = local.environment
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  common_tags         = local.common_tags

  instance_type      = "t3.medium"
  desired_capacity   = 2       # Prod: always 2 for HA across AZs
  min_size           = 2
  max_size           = 6
  use_spot_instances = false   # Prod: on-demand for reliability
  cpu_target_value   = 50.0
}
