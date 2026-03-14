# Cloud Infrastructure Platform

A production-ready AWS infrastructure platform built with Terraform.
Deploys a secure, scalable three-tier architecture with environment
separation, cost optimization, and security best practices built in.

## Architecture

[architecture diagram here — draw.io, export as PNG]

## What This Deploys

- VPC with public/private/database subnet tiers across 2 AZs
- Application Load Balancer with HTTPS redirect
- Auto Scaling Group with target tracking (50% CPU)
- RDS PostgreSQL in private subnets with automated backups
- Bastion host for secure SSH access (no direct EC2 exposure)
- VPC Flow Logs + CloudTrail for full audit trail
- Cost optimization: Spot instances for non-prod, Reserved for prod

## Quick Start

\`\`\`bash
cd environments/dev
terraform init
terraform plan
terraform apply
\`\`\`

## Environments

| Environment | Instance Type | Multi-AZ | Spot Instances |
|---|---|---|---|
| dev | t3.micro | No | Yes (60% savings) |
| staging | t3.small | No | Yes |
| prod | t3.medium | Yes | No |

## Security Decisions

- No direct SSH to application servers (bastion only)
- Database subnet has no route to internet
- S3 VPC Endpoint (traffic never leaves AWS network)
- All resources tagged for cost allocation
- IAM roles use least-privilege policies

# Cost Decisions

Dev environment monthly estimate:
  t3.micro Spot (1 instance):    ~$3/month
  Single NAT Gateway:            ~$32/month
  RDS db.t3.micro:               ~$14/month
  Total dev:                     ~$49/month

Prod environment monthly estimate:
  t3.medium On-Demand (2):       ~$60/month
  NAT Gateway x2:                ~$64/month
  RDS db.t3.medium Multi-AZ:     ~$97/month
  Total prod:                    ~$221/month
