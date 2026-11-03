#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT 3: Smoke Tests (Pruebas Funcionales End-to-End en Vivo)
# Usa 'curl --fail' para que si el API responde error (4xx o 5xx), el script
# falle automáticamente y detenga el pipeline.
# ==============================================================================

ENV="${1:-dev}"
STACK_NAME="siniestros-${ENV}"
REGION="${AWS_REGION:-us-east-1}"

# 1. Obtener la URL real del API Gateway desde CloudFormation
API_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpointUrl'].OutputValue" \
  --output text)

echo "[INFO] Ejecutando Smoke Tests contra ${API_URL} (Ambiente: ${ENV})..."

# 2. Prueba POST /claims (Registrar un siniestro nuevo en DynamoDB)
echo "  -> Probando 1/4: POST /claims (Crear siniestro)..."
CREATE_RESPONSE=$(curl -s --fail -X POST "${API_URL}/claims" \
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

# Extraemos el ID del siniestro creado usando jq
CLAIM_ID=$(echo "${CREATE_RESPONSE}" | jq -r '.data.claimId')
echo "     [OK] Siniestro creado con ID: ${CLAIM_ID}"

# 3. Prueba GET /claims/{id} (Consultar el siniestro creado)
echo "  -> Probando 2/4: GET /claims/${CLAIM_ID} (Consultar siniestro)..."
curl -s --fail "${API_URL}/claims/${CLAIM_ID}" > /dev/null
echo "     [OK] Consulta exitosa (HTTP 200)"

# 4. Prueba PATCH /claims/{id} (Actualizar estado a IN_REVIEW)
echo "  -> Probando 3/4: PATCH /claims/${CLAIM_ID} (Actualizar estado)..."
curl -s --fail -X PATCH "${API_URL}/claims/${CLAIM_ID}" \
  -H "Content-Type: application/json" \
  -d '{"status":"IN_REVIEW","adjusterNotes":"Verificado por smoke test CI/CD"}' > /dev/null
echo "     [OK] Estado actualizado a IN_REVIEW (HTTP 200)"

# 5. Prueba POST /documents/report (Generar PDF en S3)
echo "  -> Probando 4/4: POST /documents/report (Generar reporte PDF en S3)..."
DOC_RESPONSE=$(curl -s --fail -X POST "${API_URL}/documents/report" \
  -H "Content-Type: application/json" \
  -d "{\"claimId\":\"${CLAIM_ID}\",\"includeAdjusterNotes\":true}")

REPORT_KEY=$(echo "${DOC_RESPONSE}" | jq -r '.data.reportKey')
echo "     [OK] PDF guardado en S3: ${REPORT_KEY}"

echo "[OK] Las 4 pruebas End-to-End pasaron con éxito en ${ENV}."
