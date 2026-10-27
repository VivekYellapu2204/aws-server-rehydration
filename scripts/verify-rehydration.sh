#!/usr/bin/env bash
set -euo pipefail

TARGET_GROUP_ARN="${TARGET_GROUP_ARN:-}"
ALB_ENDPOINT="${ALB_ENDPOINT:-http://127.0.0.1}"
MAX_RETRIES=15
RETRY_INTERVAL_SEC=20

if [[ -z "${TARGET_GROUP_ARN}" ]]; then
  echo "Error: TARGET_GROUP_ARN environment variable is not defined."
  exit 1
fi

echo "--- Gating Check: AWS ALB Target Group State ---"
for ((i=1; i<=MAX_RETRIES; i++)); do
  UNHEALTHY_COUNT=$(aws elbv2 describe-target-health \
    --target-group-arn "${TARGET_GROUP_ARN}" \
    --query "TargetHealthDescriptions[?TargetHealth.State!='healthy'] | length(@)" \
    --output text)

  TOTAL_TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "${TARGET_GROUP_ARN}" \
    --query "TargetHealthDescriptions | length(@)" \
    --output text)

  echo "Evaluation [${i}/${MAX_RETRIES}]: Total Targets = ${TOTAL_TARGETS}, Non-Healthy = ${UNHEALTHY_COUNT}"

  if [[ "${TOTAL_TARGETS}" -gt 0 ]] && [[ "${UNHEALTHY_COUNT}" -eq 0 ]]; then
    echo "All target nodes passed ELB health verification."
    break
  fi

  if [[ $i -eq $MAX_RETRIES ]]; then
    echo "Health check timeout exceeded: Rehydrated instances failed to achieve 100% healthy status."
    exit 1
  fi
  sleep "${RETRY_INTERVAL_SEC}"
done

echo "--- Gating Check: Synthetic Endpoint Validation ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${ALB_ENDPOINT}/healthz" || echo "000")

if [[ "${HTTP_STATUS}" -eq 200 ]]; then
  echo "Synthetic check passed: ${ALB_ENDPOINT}/healthz returned 200 OK."
  exit 0
else
  echo "Synthetic check failed: ${ALB_ENDPOINT}/healthz returned HTTP status ${HTTP_STATUS}."
  exit 1
fi
