#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${1:-dashboard/explain-report.json}"
mkdir -p "$(dirname "$OUTPUT_PATH")"

EXPLAIN_REASON="${EXPLAIN_REASON:-No infra change required}"
AFFECTED_PACKAGES_JSON="${AFFECTED_PACKAGES_JSON:-[]}"
ACTION_TAKEN="${ACTION_TAKEN:-No rebuild triggered}"
CONFIDENCE="${CONFIDENCE:-75%}"
GENERATED_AT="${GENERATED_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

cat > "$OUTPUT_PATH" <<EOF
{
  "reason": "${EXPLAIN_REASON}",
  "affected_packages": ${AFFECTED_PACKAGES_JSON},
  "action_taken": "${ACTION_TAKEN}",
  "confidence": "${CONFIDENCE}",
  "generated_at": "${GENERATED_AT}"
}
EOF

echo "[INFO] Explain report written to ${OUTPUT_PATH}"
