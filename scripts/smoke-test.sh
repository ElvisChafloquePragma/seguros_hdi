#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Smoke Tests & Pruebas de Integracion End-to-End contra el ambiente desplegado
# Verifica:
#  1) POST /api/v1/claims (Registro de siniestro)
#  2) GET /api/v1/claims/{id} (Consulta de siniestro)
#  3) PATCH /api/v1/claims/{id} (Actualizacion de siniestro)
#  4) POST /api/v1/documents/report (Generacion de PDF en S3 + URL prefirmada)
# ==============================================================================

ENV="${1:-dev}"
STACK_NAME="siniestros-${ENV}"
REGION="${AWS_REGION:-us-east-1}"

API_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpointUrl'].OutputValue" \
  --output text)

echo "[INFO] Ejecutando pruebas E2E contra ${API_URL} (${ENV})..."

# 1. Crear siniestro
CREATE_RES=$(curl -sS -w "\n%{http_code}" -X POST "${API_URL}/claims" \
  -H "Content-Type: application/json" \
  -d '{
    "policyNumber": "POL-654321",
    "vehiclePlate": "BOG789",
    "insuredId": "1015202530",
    "insuredName": "Laura Valentina Mendoza",
    "insuredPhone": "+573152223344",
    "insuredEmail": "laura.mendoza@asegurados.co",
    "incidentDate": "2026-10-29T12:00:00.000Z",
    "location": {
      "city": "Bogotá",
      "address": "Calle 100 # 15-20",
      "latitude": 4.686,
      "longitude": -74.048
    },
    "description": "Colisión lateral durante lluvia intensa; daños en puerta derecha.",
    "estimatedAmountCop": 2900000
  }')

HTTP_CODE=$(echo "${CREATE_RES}" | tail -n1)
BODY=$(echo "${CREATE_RES}" | sed '$d')

if [[ "${HTTP_CODE}" != "201" ]]; then
  echo "[ERROR] Fallo POST /claims (HTTP ${HTTP_CODE}): ${BODY}"
  exit 1
fi

CLAIM_ID=$(echo "${BODY}" | jq -r '.data.claimId')
echo "  [PASS] POST /claims -> Creado ${CLAIM_ID}"

# 2. Consultar siniestro
GET_CODE=$(curl -sS -o /dev/null -w "%{http_code}" "${API_URL}/claims/${CLAIM_ID}")
if [[ "${GET_CODE}" != "200" ]]; then
  echo "[ERROR] Fallo GET /claims/${CLAIM_ID} (HTTP ${GET_CODE})"
  exit 1
fi
echo "  [PASS] GET /claims/${CLAIM_ID} -> HTTP 200"

# 3. Actualizar siniestro
PATCH_CODE=$(curl -sS -o /dev/null -w "%{http_code}" -X PATCH "${API_URL}/claims/${CLAIM_ID}" \
  -H "Content-Type: application/json" \
  -d '{"status":"IN_REVIEW","adjusterNotes":"Verificado por smoke test automatizado CI/CD"}')
if [[ "${PATCH_CODE}" != "200" ]]; then
  echo "[ERROR] Fallo PATCH /claims/${CLAIM_ID} (HTTP ${PATCH_CODE})"
  exit 1
fi
echo "  [PASS] PATCH /claims/${CLAIM_ID} -> HTTP 200 (status=IN_REVIEW)"

# 4. Generar reporte PDF
DOC_RES=$(curl -sS -w "\n%{http_code}" -X POST "${API_URL}/documents/report" \
  -H "Content-Type: application/json" \
  -d "{\"claimId\":\"${CLAIM_ID}\",\"includeAdjusterNotes\":true}")
DOC_CODE=$(echo "${DOC_RES}" | tail -n1)
DOC_BODY=$(echo "${DOC_RES}" | sed '$d')

if [[ "${DOC_CODE}" != "201" ]]; then
  echo "[ERROR] Fallo POST /documents/report (HTTP ${DOC_CODE}): ${DOC_BODY}"
  exit 1
fi

REPORT_KEY=$(echo "${DOC_BODY}" | jq -r '.data.reportKey')
echo "  [PASS] POST /documents/report -> PDF almacenado en S3 (${REPORT_KEY})"
echo "[OK] Smoke tests E2E superados con exito en ${ENV}."

