#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT 4: Publicación de las 4 Métricas DORA en Amazon CloudWatch
# 1. Deployment Frequency: Suma 1 despliegue.
# 2. Lead Time for Changes: Minutos entre la hora del commit y la hora actual.
# 3. Change Failure Rate: Envía 0 si hubo éxito, o 1 si hubo fallo.
# 4. Mean Time to Restore (MTTR): Minutos que tomó recuperarse de un fallo.
# ==============================================================================

ENV="${1:-dev}"
STATUS="${2:-SUCCESS}"      # Recibe SUCCESS o FAILURE desde Jenkins
MTTR_MINUTES="${3:-0}"      # Minutos de recuperación (0 si no hubo fallo)
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="SiniestrosDORA"

# 1. Calcular el Lead Time real (Hora actual menos Hora del último commit en Git)
HORA_ACTUAL=$(date +%s)
HORA_COMMIT=$(git log -1 --format=%ct 2>/dev/null || echo "${HORA_ACTUAL}")
LEAD_TIME_MIN=$(( (HORA_ACTUAL - HORA_COMMIT) / 60 ))

# Si el despliegue tardó menos de 1 minuto, registramos mínimo 1 minuto
if [ "${LEAD_TIME_MIN}" -lt 1 ]; then
  LEAD_TIME_MIN=1
fi

# 2. Definir si hubo fallo (0 = Exitoso, 1 = Fallido)
if [ "${STATUS}" = "SUCCESS" ]; then
  FAILURE_VAL=0
else
  FAILURE_VAL=1
fi

echo "[INFO] Enviando métricas DORA a CloudWatch (Ambiente=${ENV}, Estado=${STATUS}, LeadTime=${LEAD_TIME_MIN} min)..."

# 3. Enviar las 4 métricas a CloudWatch
aws cloudwatch put-metric-data \
  --namespace "${NAMESPACE}" \
  --region "${REGION}" \
  --metric-data \
    "MetricName=DeploymentFrequency,Dimensions=[{Name=Environment,Value=${ENV}}],Value=1,Unit=Count" \
    "MetricName=LeadTimeMinutes,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${LEAD_TIME_MIN},Unit=Count" \
    "MetricName=ChangeFailureCount,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${FAILURE_VAL},Unit=Count" \
    "MetricName=MeanTimeToRestoreMinutes,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${MTTR_MINUTES},Unit=Count"

echo "[OK] Métricas DORA registradas en CloudWatch."
