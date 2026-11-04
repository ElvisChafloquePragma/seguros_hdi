#!/usr/bin/env bash
set -e

# Despliegue de Frontend React (S3 + Invalidación CloudFront)

ENV="${1:-dev}"
STACK_NAME="siniestros-${ENV}"
REGION="${AWS_REGION:-us-east-1}"

echo "[INFO] 1. Consultando datos del stack ${STACK_NAME} en CloudFormation..."

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

echo "[INFO] 2. Subiendo archivos estáticos (.js, .css) con caché de 1 año..."
aws s3 sync "frontend/dist/" "s3://${FRONTEND_BUCKET}/" \
  --exclude "index.html" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete \
  --region "${REGION}"

echo "[INFO] 3. Subiendo index.html sin caché (no-cache)..."
aws s3 cp "frontend/dist/index.html" "s3://${FRONTEND_BUCKET}/index.html" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "text/html; charset=utf-8" \
  --region "${REGION}"

echo "[INFO] 4. Limpiando caché (Invalidación) en CloudFront (${CF_DIST_ID})..."
aws cloudfront create-invalidation \
  --distribution-id "${CF_DIST_ID}" \
  --paths "/index.html" "/" > /dev/null

echo "[OK] Frontend publicado exitosamente en: ${CF_URL}"
