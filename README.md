# OpenAMI Guard

OpenAMI Guard is a plug-and-play AMI operations system for AWS teams that want secure images without building a custom platform from scratch.

It gives you one reusable workflow to:

- Secure AMIs automatically with hardening and validation
- Keep published AMIs patched continuously by watching for drift and findings
- Deploy updates safely with canary rollout and rollback
- Give developers and operators visibility into AMI and rollout health

## What You Get

- Packer-based AMI build pipeline with opinionated hardening hooks
- Automated rebuild triggers from upstream base-image drift and AWS Inspector findings
- Validation on a temporary EC2 instance through SSM
- Canary deployment through Auto Scaling instance refresh
- Automatic promotion on healthy rollout
- Automatic rollback to the last known good version on failed rollout
- A static dashboard artifact for infra health, lineage, rollout state, and canary confidence

## Why It Is Plug-and-Play

Most teams should only need to do three things:

1. Add AWS and environment secrets in GitHub.
2. Add repository variables for region, SSM parameter names, rollout thresholds, and source AMI filters.
3. Adjust the Packer var file for their naming, sizing, and encryption defaults.

The workflow already handles detection, build, validation, rollout, rollback, and dashboard generation.

## Repository Structure

```text
.
|-- .github/workflows/self-healing-ami.yml
|-- dashboard/
|   |-- index.html
|   `-- status.json
|-- ubuntu.pkr.hcl
|-- variables.pkr.hcl
|-- team.auto.pkrvars.hcl.example
|-- scripts/
|   |-- bootstrap.sh
|   |-- harden.sh
|   |-- validate.sh
|   |-- detect_vulnerabilities.sh
|   |-- test_ami.sh
|   |-- canary_rollout.sh
|   |-- check_canary_health.sh
|   |-- promote_ami.sh
|   |-- generate_dashboard_status.sh
|   `-- rollback_ami.sh
`-- README.md
```

## Quick Start

### 1. Fork or clone the repo

Keep the workflow file at `.github/workflows/self-healing-ami.yml` so GitHub Actions can run it immediately.

### 2. Configure Packer inputs

Use the defaults in `variables.pkr.hcl` or create your own file from `team.auto.pkrvars.hcl.example`.

Example local build:

```bash
packer init .
packer validate -var-file="team.auto.pkrvars.hcl" ubuntu.pkr.hcl
packer build -var-file="team.auto.pkrvars.hcl" ubuntu.pkr.hcl
```

### 3. Add GitHub Secrets

- `AWS_ROLE_TO_ASSUME`
- `TEST_SUBNET_ID`
- `TEST_SECURITY_GROUP_ID`
- `TEST_INSTANCE_PROFILE`
- `LAUNCH_TEMPLATE_ID`
- `AUTO_SCALING_GROUP_NAME`
- `HEALTH_ALARM_NAME`

### 4. Add GitHub Repository Variables

These are the main plug-and-play knobs for each team:

- `SYSTEM_NAME`
- `AWS_REGION`
- `AMI_PARAMETER_NAME`
- `LAST_KNOWN_GOOD_PARAMETER_NAME`
- `CANARY_PERCENTAGE`
- `INSTANCE_WARMUP`
- `BAKE_TIME_SECONDS`
- `SEVERITY_THRESHOLD`
- `PACKER_TEMPLATE_FILE`
- `PACKER_VARIABLE_FILE`
- `SOURCE_AMI_NAME_PATTERN`
- `SOURCE_AMI_OWNER`
- `SOURCE_AMI_VIRTUALIZATION_TYPE`
- `SOURCE_AMI_ROOT_DEVICE_TYPE`

Recommended starter values:

```text
SYSTEM_NAME=OpenAMI Guard
AWS_REGION=us-east-1
AMI_PARAMETER_NAME=/platform/amis/current
LAST_KNOWN_GOOD_PARAMETER_NAME=/platform/amis/last_known_good
CANARY_PERCENTAGE=10
INSTANCE_WARMUP=180
BAKE_TIME_SECONDS=600
SEVERITY_THRESHOLD=HIGH
PACKER_TEMPLATE_FILE=ubuntu.pkr.hcl
PACKER_VARIABLE_FILE=team.auto.pkrvars.hcl
SOURCE_AMI_NAME_PATTERN=ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*
SOURCE_AMI_OWNER=099720109477
SOURCE_AMI_VIRTUALIZATION_TYPE=hvm
SOURCE_AMI_ROOT_DEVICE_TYPE=ebs
```

### 5. Create the backing SSM parameters

The workflow promotes the live AMI and stores rollback state in Parameter Store.

- `AMI_PARAMETER_NAME`
- `LAST_KNOWN_GOOD_PARAMETER_NAME`

### 6. Run the workflow

Use `workflow_dispatch` for the first run. After that, the scheduled trigger keeps your AMIs watched and refreshed.

## Workflow Lifecycle

1. Detect vulnerability drift and upstream base-image changes.
2. Rebuild a candidate AMI when risk or drift is found, or when manually forced.
3. Launch a temporary validation instance and run health checks over SSM.
4. Start a canary refresh on the target Auto Scaling Group.
5. Evaluate health after the bake window.
6. Promote the AMI on success or roll back automatically on failure.
7. Publish a dashboard artifact with rollout and image health data.

## Developer Dashboard

The dashboard in `dashboard/index.html` gives teams a lightweight infra health view without needing a separate app stack.

- Current AMI version
- Vulnerability status
- Last patch time
- Rollout status
- AMI lineage history
- Vulnerability trend snapshots
- Rollout timeline
- Canary success rate

Each workflow run generates `dashboard/status.json` and uploads the whole `dashboard/` directory as the `openami-guard-dashboard` artifact. You can publish the same directory with GitHub Pages for an internal status page.

## Customization Points

Use this repo as a starter kit, then tailor the following to your platform:

- `scripts/harden.sh` for CIS-style hardening, agent installation, and security baselines
- `scripts/validate.sh` for image-level validation during build
- `scripts/test_ami.sh` for runtime smoke tests and service assertions
- `team.auto.pkrvars.hcl` for team naming, sizing, KMS, and image-family defaults
- Repository variables for region, rollout policy, and source image tracking

## Best Fit Teams

- Platform engineering teams managing base EC2 images
- Security teams enforcing patch and rollout controls
- DevOps teams running immutable fleets on Auto Scaling Groups
- Internal developer platforms that need a shared golden image service

## Current Scope

This starter ships with Ubuntu 24.04 defaults because that is the fastest path to adoption and a complete example. The system itself is designed to be reusable: the source AMI discovery rules, image naming, rollout thresholds, parameter names, and build inputs are all configurable.
