# ── Identity ─────────────────────────────────────────────────────
variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ── Networking ───────────────────────────────────────────────────
variable "vpc_id" {
  description = "VPC ID to deploy compute resources into"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EC2 instances"
  type        = list(string)
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed SSH access to bastion host"
  type        = list(string)
}

# ── Compute ──────────────────────────────────────────────────────
variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

variable "user_data" {
  description = "User data script to run on instance launch"
  type        = string
  default     = ""
}

# ── Auto Scaling ─────────────────────────────────────────────────
variable "desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 4
}

variable "use_spot_instances" {
  description = "Use Spot instances for cost savings (non-prod only)"
  type        = bool
  default     = false
}

variable "cpu_target_value" {
  description = "Target CPU utilization % for Auto Scaling policy"
  type        = number
  default     = 50.0
}
