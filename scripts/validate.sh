#!/bin/bash
set -e

echo "[INFO] Checking installed tools"
command -v amazon-ssm-agent
command -v amazon-cloudwatch-agent
command -v curl

echo "[INFO] Checking agent status"
sudo systemctl status amazon-ssm-agent | grep active

echo "[INFO] Validating deploy user"
id deploy

echo "[INFO] Verifying SSH hardening"
sudo sshd -T | grep -E '^permitrootlogin no$'
sudo sshd -T | grep -E '^passwordauthentication no$'

echo "[INFO] Running package audit"
sudo apt-get install -y debsecan >/dev/null
sudo debsecan --format compact --suite noble --only-fixed | head -n 20 || true

echo "[INFO] Validation complete"
