#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${1:-.openami.generated.pkrvars.hcl}"
SYSTEM_SLUG="${OPENAMI_SYSTEM_SLUG:-openami-guard}"

cat > "$OUTPUT_PATH" <<EOF
pipeline_name                = "${SYSTEM_SLUG}"
source_ami_name_pattern      = "${SOURCE_AMI_NAME_PATTERN:-ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*}"
source_ami_owner             = "${SOURCE_AMI_OWNER:-099720109477}"
source_ami_ssh_username      = "${SOURCE_AMI_SSH_USERNAME:-ubuntu}"
source_ami_virtualization_type = "${SOURCE_AMI_VIRTUALIZATION_TYPE:-hvm}"
source_ami_root_device_type  = "${SOURCE_AMI_ROOT_DEVICE_TYPE:-ebs}"
EOF

echo "[INFO] Generated OpenAMI Packer override file at ${OUTPUT_PATH}"
