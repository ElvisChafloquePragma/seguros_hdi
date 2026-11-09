#!/usr/bin/env bash
set -e

# Smoke Tests (Verificación Post-Despliegue en Vivo)

ENV="${1:-dev}"
STACK="siniestros-${ENV}"

# Obtener la URL del API Gateway desde CloudFormation
API_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK}" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpointUrl'].OutputValue" \
  --output text)

echo "[INFO] Ejecutando Smoke Tests contra: ${API_URL}"

#  Crear un siniestro de prueba
echo "  -> 1. POST /claims (Crear siniestro en DynamoDB)..."
RESPUESTA=$(curl -s --fail -X POST "${API_URL}/claims" \
  -H "Content-Type: application/json" \
  -d '{"policyNumber":"POL-123","vehiclePlate":"HDI789","insuredId":"102030"}')

ID=$(echo "${RESPUESTA}" | jq -r '.data.claimId')
echo "     [OK] Creado con ID: ${ID}"

#  Consultar el siniestro recién creado
echo "  -> 2. GET /claims/${ID} (Consultar en DynamoDB)..."
curl -s --fail "${API_URL}/claims/${ID}" > /dev/null
echo "     [OK] Consulta exitosa"

#  Actualizar el estado del siniestro
echo "  -> 3. PATCH /claims/${ID} (Actualizar estado)..."
curl -s --fail -X PATCH "${API_URL}/claims/${ID}" \
  -H "Content-Type: application/json" \
  -d '{"status":"IN_REVIEW"}' > /dev/null
echo "     [OK] Estado actualizado a IN_REVIEW"

#  Generar el reporte PDF en S3
echo "  -> 4. POST /documents/report (Generar PDF en S3)..."
curl -s --fail -X POST "${API_URL}/documents/report" \
  -H "Content-Type: application/json" \
  -d "{\"claimId\":\"${ID}\"}" > /dev/null
echo "     [OK] PDF generado y guardado en S3"

echo "[OK] Las 4 pruebas pasaron exitosamente en ${ENV}."
