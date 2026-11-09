#!/usr/bin/env bash
set -e


REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "920734714556")

vaciar_bucket() {
  local bucket="$1"
  if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
    echo "  -> Vaciando s3://${bucket}..."
    aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
    aws s3api delete-objects --bucket "${bucket}" \
      --delete "$(aws s3api list-object-versions --bucket "${bucket}" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" >/dev/null 2>&1 || true
    aws s3api delete-objects --bucket "${bucket}" \
      --delete "$(aws s3api list-object-versions --bucket "${bucket}" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" >/dev/null 2>&1 || true
  fi
}

echo "[INFO] Iniciando Teardown para costo $0 en AWS (Región: ${REGION})..."

for env in dev staging prod; do
  STACK="siniestros-${env}"

  if aws cloudformation describe-stacks --stack-name "${STACK}" --region "${REGION}" >/dev/null 2>&1; then
    echo "[INFO] Procesando ambiente: ${env}..."

    vaciar_bucket "siniestros-${env}-frontend-${ACCOUNT_ID}"
    vaciar_bucket "siniestros-${env}-reports-${ACCOUNT_ID}"

    echo "  -> Eliminando stack ${STACK} en CloudFormation..."
    aws cloudformation delete-stack --stack-name "${STACK}" --region "${REGION}"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK}" --region "${REGION}"
    echo "  [OK] Stack ${STACK} eliminado."
  fi
done

echo "[OK] Teardown completado exitosamente. Todos los recursos fueron eliminados. Costo en AWS = $0."
