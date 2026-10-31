#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Medicion Automatizada de las 4 Metricas DORA en CloudWatch (Namespace: SiniestrosDORA)
# 1) Deployment Frequency: Se incrementa en cada despliegue exitoso.
# 2) Lead Time for Changes: Minutos entre el timestamp del commit en Git y el deploy.
# 3) Change Failure Rate (CFR): Se registra 1 si el deploy fallo/hizo rollback, 0 si tuvo exito.
# 4) Mean Time to Restore (MTTR): Tiempo de restauracion ante incidente o rollback.
# ==============================================================================

ENV="${1:-dev}"
STATUS="${2:-SUCCESS}" # SUCCESS | FAILURE
MTTR_MINUTES="${3:-0}"
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="SiniestrosDORA"

NOW_EPOCH=$(date +%s)
if git rev-parse --git-dir > /dev/null 2>&1 && git log -1 --format=%ct > /dev/null 2>&1; then
  COMMIT_EPOCH=$(git log -1 --format=%ct)
  LEAD_TIME_MIN=$(( (NOW_EPOCH - COMMIT_EPOCH) / 60 ))
  if (( LEAD_TIME_MIN < 1 )); then LEAD_TIME_MIN=1; fi
else
  LEAD_TIME_MIN=5
fi

if [[ "${STATUS}" == "SUCCESS" ]]; then
  FAILURE_VAL=0
else
  FAILURE_VAL=1
fi

echo "[INFO] Publicando metricas DORA en CloudWatch (${NAMESPACE} | Env=${ENV} | Status=${STATUS} | LeadTime=${LEAD_TIME_MIN}m)..."

aws cloudwatch put-metric-data \
  --namespace "${NAMESPACE}" \
  --region "${REGION}" \
  --metric-data \
    "MetricName=DeploymentFrequency,Dimensions=[{Name=Environment,Value=${ENV}}],Value=1,Unit=Count" \
    "MetricName=LeadTimeMinutes,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${LEAD_TIME_MIN},Unit=Count" \
    "MetricName=ChangeFailureCount,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${FAILURE_VAL},Unit=Count" \
    "MetricName=MeanTimeToRestoreMinutes,Dimensions=[{Name=Environment,Value=${ENV}}],Value=${MTTR_MINUTES},Unit=Count"

echo "[OK] Metricas DORA registradas en CloudWatch."

