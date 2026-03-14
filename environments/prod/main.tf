locals {
  project     = "myapp"
  environment = "prod"
  region      = "us-east-1"
  # ... same common_tags ...
}

module "networking" {
  source = "../../modules/networking"
  # ...
  single_nat_gateway = false   # Prod: one NAT per AZ for HA
}

module "compute" {
  source = "../../modules/compute"
  # ...
  instance_type      = "t3.medium"
  desired_capacity   = 2       # Prod: always 2 for HA across AZs
  min_size           = 2
  max_size           = 6
  use_spot_instances = false   # Prod: on-demand for reliability
  cpu_target_value   = 50.0
}
