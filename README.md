# AWS Zero-Downtime Server Rehydration Pipeline

An enterprise-grade, immutable infrastructure delivery pipeline engineered for zero-downtime Golden AMI replacement, automated Auto Scaling Group (ASG) instance refreshes, and synthetic health verification with automated rollback circuit breakers.

---

## 1. Architectural Overview & Design Philosophy

Traditional server maintenance relies on in-place patching, introducing configuration drift, unpredictable runtime dependencies, and configuration decay across long-lived instances. This repository implements an **Immutable Infrastructure Lifecycle** where servers are treated as ephemeral compute targets and replaced via automated rehydration.


```

+--------------------------------------------------------------------------------------------------+
|                                  Continuous Delivery Boundary                                    |
|                                                                                                  |
|  [Commit / Trigger] ---> [Packer + Ansible] ---> [Manifest JSON] ---> [Terraform Launch Template]|
|                               (Bake Stage)         (AMI Artifact)         (Version Bump)         |
+----------------------------------------------------------------------------------|---------------+
v
+--------------------------------------------------------------------------------------------------+
|                                    AWS Infrastructure Fabric                                     |
|                                                                                                  |
|                      +----------------------------------------------------+                      |
|                      |             Application Load Balancer              |                      |
|                      +-------------------------+--------------------------+                      |
|                                                |                                                 |
|                        Draining (300s)         | Registration & Warmup (300s)                    |
|                                                v                                                 |
|                      +----------------------------------------------------+                      |
|                      |            Auto Scaling Group (Multi-AZ)           |                      |
|                      |                                                    |                      |
|                      |    [Old Instance]              [New Instance]      |                      |
|                      |    State: Terminating          State: InService    |                      |
|                      |    LaunchTemplate: v(N-1)      LaunchTemplate: v(N)|                      |
|                      +----------------------------------------------------+                      |
|                                                ^                                                 |
+------------------------------------------------|-------------------------------------------------+
|
+------------------------+------------------------+
|                                                 |
[Health Gate Passes]                             [Health Gate Fails]
|                                                 |
v                                                 v
Rehydration Finalized                            Trigger `auto-rollback`
(Pipeline Complete)                         (Cancel Refresh & Restore v(N-1))

```

### Core Architectural Tenets

* **Zero Configuration Drift:** No configuration changes, security patches, or package upgrades occur on live nodes. Any modification yields a newly baked, encrypted Golden AMI that replaces the existing fleet.
* **Deterministic Rollouts:** OS baselines, CIS benchmarks, monitoring agents, and systemd units are baked during the CI/CD build phase. Instances boot into service without pulling external runtime dependencies during launch.
* **Connection Preservation:** Active HTTP/S client sessions are protected through Application Load Balancer target group deregistration delays. Instances slated for retirement stop receiving new traffic and allow existing transactions to complete cleanly.
* **Automated Rollback Circuit Breakers:** Health checks run throughout the deployment window. If new instances fail synthetic assertions, the pipeline halts termination of the remaining healthy nodes and cancels the instance refresh automatically.

---

## 2. End-to-End Pipeline Execution Lifecycle

The server rehydration lifecycle moves through six discrete operational stages:


```

[Stage 01: Lint & Validate]
│
├── terraform fmt -check & terraform validate
└── Gating Check: Syntax and structural validation
│
[Stage 02: Bake Golden AMI]
│
├── Provision temporary builder EC2 in private subnet
├── Execute Ansible local provisioning (CIS controls, services, cleanup)
├── Create encrypted EBS snapshot & AMI
└── Emit packer-manifest.json artifact containing AMI ID
│
[Stage 03: Plan Rehydration]
│
├── Ingest artifact ID via jq
├── Generate execution diff for Launch Template version update
└── Output binary plan artifact (tfplan.binary)
│
[Stage 04: Execute Rehydration (Production Gate)]
│
├── Apply Terraform plan to update AWS Launch Template
└── Trigger ASG Instance Refresh using rolling swap preferences
│
[Stage 05: Verify Health]
│
├── Poll ALB Target Group health via AWS CLI until 100% healthy
└── Execute synthetic curl validation against /healthz endpoint
│
[Stage 06: Rollback on Failure (Conditional)]
│
├── Activated only if Stage 05 exits with non-zero status
└── Call aws autoscaling cancel-instance-refresh to revert instance targets

```

---

## 3. High Availability & Fleet Capacity Sizing

The rehydration policy uses percentage-based operational guardrails to prevent capacity degradation during rollouts:

$$\text{Active Healthy Capacity} \ge \text{Desired Capacity} \times \left(\frac{\text{min\_healthy\_percentage}}{100}\right)$$

* **Minimum Healthy Percentage (`90%`):** Ensures at least $90\%$ of total fleet capacity remains active and serving production requests during the rolling instance swap.
* **Instance Warmup Window (`300s`):** Provides a buffer period for initialization daemons, kernel parameters, and application sockets to stabilize before the ASG evaluates the node's ELB health check.
* **Deregistration Delay (`300s`):** Configured on the ALB target group to prevent dropped packets by allowing in-flight TCP sessions to finish before SIGTERM/SIGKILL signals hit terminating instances.

---

## 4. Repository Structure


```

aws-server-rehydration-pipeline/
├── .gitignore                          # Excludes state files, plan binaries, and build caches
├── .gitlab-ci.yml                      # 6-stage CI/CD pipeline definition with auto-rollback
├── README.md                           # Architecture and operational documentation
├── ansible/
│   └── playbook.yml                    # AMI hardening, daemon configuration, and sanitization
├── packer/
│   └── golden-ami.pkr.hcl              # HCL2 AMI builder template for AL2023 with EBS encryption
├── scripts/
│   └── verify-rehydration.sh           # Health polling and synthetic endpoint assertions
└── terraform/
├── main.tf                         # ALB Target Group, Launch Template, and ASG Refresh configuration
├── variables.tf                    # Parameterized operational thresholds and sizing inputs
├── outputs.tf                      # Exported ARNs and launch template revision trackers
└── terraform.tfvars.example        # Reference configuration template for deployment targets

```

---

## 5. Configuration & Environment Variables

### CI/CD Pipeline Variables
Set these variables within your GitLab CI/CD Project Settings or runner environment:

| Variable Identifier | Required | Default | Description |
| :--- | :--- | :--- | :--- |
| `AWS_DEFAULT_REGION` | Yes | `us-east-1` | AWS region where resources and pipelines execute. |
| `BUILD_VPC_ID` | Yes | — | VPC ID where the temporary Packer build instance is spun up. |
| `BUILD_SUBNET_ID` | Yes | — | Subnet ID hosting the temporary Packer build instance. |
| `ASG_NAME` | Yes | `production-asg` | Auto Scaling Group target name used for status tracking and rollback. |
| `TARGET_GROUP_ARN` | Yes | — | ARN of the ALB target group for health state polling. |
| `ALB_ENDPOINT` | Yes | `http://127.0.0.1` | Base URL used by synthetic health check probes. |
| `MIN_HEALTHY_PERCENT` | No | `90` | Minimum operational capacity maintained during refresh. |
| `INSTANCE_WARMUP_SEC` | No | `300` | Warmup buffer before evaluating instance health. |

---

## 6. Operational Runbook

### Executing a Production Rehydration
1. Merge reviewed changes to `main`.
2. The pipeline runs linting, bakes a new hardened Golden AMI, extracts the AMI ID via `jq`, and runs `terraform plan`.
3. Review the generated plan artifact in the GitLab CI console.
4. Manually trigger the `execute-refresh` job to apply the new Launch Template version and start the rolling replacement.
5. The pipeline monitors target group registration while draining in-flight connections on old instances over a 300-second window.

### Automated Failure Recovery
* If target nodes do not enter a `healthy` state within 300 seconds, or if synthetic HTTP assertions against `/healthz` fail, `verify-rehydration` exits with code `1`.
* The `auto-rollback` job detects the pipeline failure, queries the active `InstanceRefreshId`, and executes:
  ```bash
  aws autoscaling cancel-instance-refresh --auto-scaling-group-name "${ASG_NAME}"

```

* Active terminations stop immediately, and the Auto Scaling Group preserves or re-provisions instances against the previous stable Launch Template version.

### Local Development & Syntax Validation

```bash
# Validate Terraform syntax
cd terraform
terraform init -backend=false
terraform fmt -check
terraform validate

# Validate Packer template syntax
cd ../packer
packer init golden-ami.pkr.hcl
packer validate golden-ami.pkr.hcl

# Validate Ansible playbook syntax
cd ../ansible
ansible-playbook playbook.yml --syntax-check

```

```

```
