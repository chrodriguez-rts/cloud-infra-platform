# Architecture Decision Records (ADR)

## ADR-001: Single NAT Gateway in Non-Production
**Decision:** Use one NAT Gateway per environment in dev/staging instead of one per AZ.
**Reasoning:** NAT Gateways cost ~$32/month each. Non-production environments don't
require the availability guarantees of per-AZ NAT. If the NAT Gateway fails in dev,
developers redeploy — acceptable disruption for ~$32/month savings per environment.
**Tradeoff:** Reduced availability in dev/staging. All private subnet traffic routes
through one AZ for internet egress. Accepted for non-production.

## ADR-002: Spot Instances for Non-Production Compute
**Decision:** Use Spot instances with On-Demand base capacity of 1 for dev/staging ASGs.
**Reasoning:** Application is stateless (session data in ElastiCache, files in S3).
Spot interruptions cause a brief auto-scaling event, not data loss. 60-70% cost
reduction vs On-Demand for non-production workloads that don't need SLA guarantees.
**Tradeoff:** Occasional 2-minute interruption notices in dev. Handled by ASG
automatically with replacement instances. No user impact in production.

## ADR-003: IMDSv2 Enforcement
**Decision:** Require IMDSv2 (http_tokens = "required") on all EC2 instances.
**Reasoning:** IMDSv2 requires a PUT request with a token before GET requests to
instance metadata. This prevents SSRF (Server-Side Request Forgery) attacks where
a compromised application could request instance credentials via IMDSv1.
**Tradeoff:** Applications using IMDSv1 SDKs need updating. Modern AWS SDKs
(boto3 >= 1.9.220, AWS CLI v2) all support IMDSv2.

## ADR-004: S3 VPC Endpoint
**Decision:** Create an S3 Gateway VPC Endpoint in all environments.
**Reasoning:** Gateway Endpoints are free. Without one, EC2 → S3 traffic routes
through the internet via NAT Gateway, incurring data transfer costs (~$0.045/GB)
and adding latency. The endpoint routes traffic through the AWS private network.
**Tradeoff:** None. Gateway Endpoints are free and strictly improve security and cost.

## ADR-005: Bastion Host over SSM for SSH Access
**Decision:** Use a dedicated bastion host rather than AWS Systems Manager Session Manager.
**Reasoning:** SSM Session Manager is strictly more secure (no open port 22, no key
management). However, SSM requires the SSM Agent and appropriate IAM permissions,
which adds complexity for a learning environment. Bastion is included here to demonstrate
the security group chaining pattern. Future iteration: replace bastion with SSM.
**Tradeoff:** Maintaining a bastion increases attack surface vs SSM. Acceptable for
this project; SSM is the production recommendation.
