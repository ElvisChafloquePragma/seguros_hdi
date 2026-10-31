#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script de Teardown (Limpieza total de recursos para garantizar costo $0 post-evaluacion)
# Vacía los buckets S3 versionados y elimina los stacks prod, staging y dev.
# ==============================================================================

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

empty_versioned_bucket() {
  local bucket="$1"
  if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
    echo "[INFO] Vaciando objetos y versiones de s3://${bucket}..."
    aws s3 rm "s3://${bucket}" --recursive --region "${REGION}" || true
    aws s3api list-object-versions --bucket "${bucket}" --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' | \
      jq -c 'select(.Objects != null)' | \
      while read -r objs; do
        aws s3api delete-objects --bucket "${bucket}" --delete "${objs}" >/dev/null || true
      done
    aws s3api list-object-versions --bucket "${bucket}" --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' | \
      jq -c 'select(.Objects != null)' | \
      while read -r markers; do
        aws s3api delete-objects --bucket "${bucket}" --delete "${markers}" >/dev/null || true
      done
  fi
}

for env in prod staging dev; do
  empty_versioned_bucket "siniestros-${env}-frontend-${ACCOUNT_ID}"
  empty_versioned_bucket "siniestros-${env}-reports-${ACCOUNT_ID}"
  echo "[INFO] Eliminando stack siniestros-${env}..."
  aws cloudformation delete-stack --stack-name "siniestros-${env}" --region "${REGION}" || true
  aws cloudformation wait stack-delete-complete --stack-name "siniestros-${env}" --region "${REGION}" || true
done

echo "[OK] Teardown completado."
