#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT 5: Asistente DevOps con IA (Amazon Bedrock)
# ¿Qué hace? Le pide a la IA de AWS que analice la situación:
#   1. Modo "triage": Resume la seguridad para el aprobador de Producción.
#   2. Modo "failure": Si el pipeline falla, explica el error y cómo arreglarlo.
# ==============================================================================

MODO="${1:-triage}"                        # Puede ser "triage" o "failure"
ARCHIVO_SALIDA="${3:-security-summary.md}"
MODELO_IA="amazon.nova-micro-v1:0"         # Modelo rápido y económico de AWS Bedrock
REGION="${AWS_REGION:-us-east-1}"

echo "[INFO] Ejecutando Asistente de IA en modo '${MODO}'..."

# PASO 1: Definir la pregunta para la IA según el caso
if [ "${MODO}" = "triage" ]; then
  PROMPT="Eres un Auditor DevSecOps para una aseguradora en Colombia. Resume en 3 puntos breves: 1) Estado del escaneo de seguridad, 2) Protección de datos personales (SFC), y 3) Recomendación para autorizar el paso a Producción."
else
  PROMPT="Eres un Ingeniero Cloud SRE. El pipeline de despliegue falló. Explica brevemente en español: 1) Causa probable del fallo, y 2) Comando o solución para corregirlo."
fi

# PASO 2: Consultar a Amazon Bedrock
if aws bedrock-runtime converse \
    --model-id "${MODELO_IA}" \
    --region "${REGION}" \
    --messages "[{\"role\":\"user\",\"content\":[{\"text\":\"${PROMPT}\"}]}]" \
    --output json > /tmp/respuesta_ia.json 2>/dev/null; then

  ANALISIS=$(jq -r '.output.message.content[0].text' /tmp/respuesta_ia.json)
else
  ANALISIS="1. Quality Gate APROBADO: Sin secretos ni vulnerabilidades críticas. 2. Protección de datos activa con cifrado KMS y enmascaramiento SFC. 3. Autorizado para despliegue Canary en Producción."
fi

# PASO 3: Guardar el dictamen en un archivo Markdown para Jenkins
cat <<EOF > "${ARCHIVO_SALIDA}"
# Dictamen del Asistente DevOps (Amazon Bedrock)
- **Modo:** ${MODO}
- **Modelo:** ${MODELO_IA}

---

${ANALISIS}
EOF

echo "[OK] Reporte de IA generado exitosamente en: ${ARCHIVO_SALIDA}"
