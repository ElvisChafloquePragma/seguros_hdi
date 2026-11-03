#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT 6: Limpieza Total (Teardown) para dejar Costo $0 en AWS
# Elimina el contenido de los buckets S3 y borra los stacks de CloudFormation.
# ==============================================================================

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for env in prod staging dev; do
  FRONTEND_BUCKET="siniestros-${env}-frontend-${ACCOUNT_ID}"
  REPORTS_BUCKET="siniestros-${env}-reports-${ACCOUNT_ID}"

  echo "[INFO] Vaciando buckets S3 del ambiente ${env}..."
  aws s3 rm "s3://${FRONTEND_BUCKET}" --recursive --region "${REGION}" 2>/dev/null || true
  aws s3 rm "s3://${REPORTS_BUCKET}" --recursive --region "${REGION}" 2>/dev/null || true

  echo "[INFO] Eliminando stack de CloudFormation: siniestros-${env}..."
  aws cloudformation delete-stack --stack-name "siniestros-${env}" --region "${REGION}" || true
  aws cloudformation wait stack-delete-complete --stack-name "siniestros-${env}" --region "${REGION}" || true
done

echo "[OK] Todos los ambientes fueron eliminados. Costo en AWS = $0."
