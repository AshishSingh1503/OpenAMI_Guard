# Intelligent Self-Healing AMI Pipeline

This project builds a hardened Ubuntu 24.04 Golden AMI with Packer and extends it into an automated AMI lifecycle pipeline on AWS. The pipeline detects vulnerability drift, rebuilds the image, validates it before release, rolls it out with a canary strategy, and rolls back automatically if health checks fail.

## What It Does

- Detects new risk automatically by checking AWS Inspector findings on the currently published AMI
- Detects upstream Ubuntu base AMI drift and rebuilds when the source image changes
- Rebuilds a replacement AMI with Packer
- Validates the candidate AMI by launching a temporary EC2 instance and running an automated validation suite through SSM
- Rolls out the AMI gradually through an Auto Scaling Group canary refresh
- Promotes the AMI only after the canary remains healthy
- Rolls back to the previous launch template version if the canary fails

## Repository Structure

```text
.
|-- .github/workflows/self-healing-ami.yml
|-- ubuntu.pkr.hcl
|-- variables.pkr.hcl
|-- scripts/
|   |-- bootstrap.sh
|   |-- harden.sh
|   |-- validate.sh
|   |-- detect_vulnerabilities.sh
|   |-- test_ami.sh
|   |-- canary_rollout.sh
|   |-- check_canary_health.sh
|   |-- promote_ami.sh
|   `-- rollback_ami.sh
`-- README.md
```

## Local Build

```bash
packer init .
packer validate -var-file="variables.pkr.hcl" ubuntu.pkr.hcl
packer build -var-file="variables.pkr.hcl" ubuntu.pkr.hcl
```

The Packer build writes `manifest.json`, which the GitHub Actions workflow uses to capture the AMI ID.

## Workflow Stages

1. Detect vulnerability drift and new upstream Ubuntu base images.
2. Build a new AMI if drift is detected or a manual rebuild is forced.
3. Launch a temporary validation instance and test the AMI through SSM.
   The validation layer checks service health, closed ports, agent readiness, SSH hardening, and baseline release tests.
4. Update the Auto Scaling Group to a new launch template version and start a canary instance refresh.
5. Check a CloudWatch alarm after the canary bake window.
6. Promote the AMI to SSM Parameter Store if healthy, or roll back automatically if unhealthy.

## Required GitHub Secrets

- `AWS_ROLE_TO_ASSUME`
- `TEST_SUBNET_ID`
- `TEST_SECURITY_GROUP_ID`
- `TEST_INSTANCE_PROFILE`
- `LAUNCH_TEMPLATE_ID`
- `AUTO_SCALING_GROUP_NAME`
- `HEALTH_ALARM_NAME`

## Required SSM Parameters

- `/golden/ubuntu24/ami_id`
- `/golden/ubuntu24/last_known_good_ami_id`

## Use Cases

- Auto Scaling Group base images
- Immutable EC2 fleets
- EKS worker node golden image pipelines
- Secure rebuild automation after new CVEs
