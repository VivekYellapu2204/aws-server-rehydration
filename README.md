# AWS Zero-Downtime Server Rehydration Pipeline

An automated immutable server lifecycle system engineered for zero-downtime AMI replacements, multi-AZ instance refreshes, and automated rollback circuit breakers.

## Operational Architecture
* **Delivery Engine:** GitLab CI/CD with automated validation, rollout staging, and instant failure rollbacks.
* **Orchestration:** AWS Auto Scaling Group Instance Refresh with strict target group connection draining.
* **Gating:** Metric-based CloudWatch alerts coupled with synthetic health-check assertion scripts.

## Usage
1. Configure AWS credentials and environment variables in your CI/CD runner.
2. Push launch template configuration updates to the repository.
3. The pipeline verifies IaC definitions, computes the execution diff, and rolls replacement instances through the cluster without dropping live sessions.
