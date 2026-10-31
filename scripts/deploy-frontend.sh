#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Estrategia de Despliegue del Frontend SPA (S3 + Invalidacion CloudFront)
# 1) Sincroniza assets con hash inmutable (Cache-Control: 1 año, immutable).
# 2) Sincroniza index.html con Cache-Control: no-cache, no-store, must-revalidate.
# 3) Ejecuta invalidacion en CloudFront sobre /index.html (1,000 rutas/mes gratis).
# ==============================================================================

ENV="${1:-dev}"
STACK_NAME="siniestros-${ENV}"
REGION="${AWS_REGION:-us-east-1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/frontend/dist"

echo "[INFO] Obteniendo Outputs del stack ${STACK_NAME}..."
FRONTEND_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='FrontendBucketName'].OutputValue" \
  --output text)

CF_DIST_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
  --output text)

CF_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontUrl'].OutputValue" \
  --output text)

echo "[INFO] Sincronizando assets estaticos versionados hacia s3://${FRONTEND_BUCKET}..."
aws s3 sync "${DIST_DIR}/" "s3://${FRONTEND_BUCKET}/" \
  --exclude "index.html" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete \
  --region "${REGION}"

echo "[INFO] Subiendo index.html con politica no-cache..."
aws s3 cp "${DIST_DIR}/index.html" "s3://${FRONTEND_BUCKET}/index.html" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "text/html; charset=utf-8" \
  --region "${REGION}"

echo "[INFO] Creando invalidacion en CloudFront (${CF_DIST_ID})..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "${CF_DIST_ID}" \
  --paths "/index.html" "/" \
  --query "Invalidation.Id" \
  --output text)

echo "[OK] Frontend desplegado en ${CF_URL} (Invalidation ID: ${INVALIDATION_ID})"

