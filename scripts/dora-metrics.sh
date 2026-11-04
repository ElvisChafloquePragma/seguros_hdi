#!/usr/bin/env bash
set -e

#  Publicación de las 4 Métricas DORA en Amazon CloudWatch

ENV="${1:-dev}"
STATUS="${2:-SUCCESS}"      
MTTR_MINUTES="${3:-0}"      
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="SiniestrosDORA"

#  Calcular el Lead Time real (Hora actual menos Hora del último commit en Git)
HORA_ACTUAL=$(date +%s)
HORA_COMMIT=$(git log -1 --format=%ct 2>/dev/null || echo "${HORA_ACTUAL}")
LEAD_TIME_MIN=$(( (HORA_ACTUAL - HORA_COMMIT) / 60 ))

# Si el despliegue tardó menos de 1 minuto, registramos mínimo 1 minuto
if [ "${LEAD_TIME_MIN}" -lt 1 ]; then
  LEAD_TIME_MIN=1
fi

#  Definir si hubo fallo (0 = Exitoso, 1 = Fallido)
if [ "${STATUS}" = "SUCCESS" ]; then
  FAILURE_VAL=0
else
  FAILURE_VAL=1
fi

echo "[INFO] Enviando métricas DORA a CloudWatch (Ambiente=${ENV}, Estado=${STATUS}, LeadTime=${LEAD_TIME_MIN} min)..."

aws cloudwatch put-metric-data \
  --namespace "${NAMESPACE}" \
  --region "${REGION}" \
  --metric-data \
    "MetricName=DeploymentFrequency,Dimensions=[{Name=Environment,Value=${ENV}}],Value=1,Unit=Count" \
    "MetricName=LeadTimeMinutes,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${LEAD_TIME_MIN},Unit=Count" \
    "MetricName=ChangeFailureCount,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${FAILURE_VAL},Unit=Count" \
    "MetricName=MeanTimeToRestoreMinutes,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${MTTR_MINUTES},Unit=Count"

echo "[OK] Métricas DORA registradas en CloudWatch."
