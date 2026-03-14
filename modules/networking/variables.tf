variable "project"      { type = string }
variable "environment"  { type = string }
variable "region"       { type = string }
variable "vpc_cidr"     { type = string }
variable "azs"          { type = list(string) }
variable "common_tags"  { type = map(string) }
variable "single_nat_gateway" {
  type        = bool
  description = "Use single NAT GW (cheaper for non-prod)"
  default     = true
}
