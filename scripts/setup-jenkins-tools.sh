#!/usr/bin/env bash
set -e

CONTAINER_NAME="jenkins-lab"

echo "=================================================================="
echo " Instalando herramientas (Node, Python, SAM, AWS) en Jenkins"
echo "=================================================================="

if ! docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
  echo "[ERROR] El contenedor ${CONTAINER_NAME} no esta corriendo."
  exit 1
fi

echo "[1/4] Actualizando repositorios e instalando paquetes base..."
docker exec -u root "${CONTAINER_NAME}" apt-get update -y
docker exec -u root "${CONTAINER_NAME}" apt-get install -y nodejs npm python3 python3-pip jq curl python3-jsonschema

echo "[2/4] Instalando check-jsonschema para validacion de parametros..."
docker exec -u root "${CONTAINER_NAME}" pip install --break-system-packages check-jsonschema || true

echo "[3/4] Vinculando AWS SAM CLI dentro del contenedor..."
if [ -d "/home/elvis/.local/aws-sam-cli" ]; then
  docker cp /home/elvis/.local/aws-sam-cli "${CONTAINER_NAME}":/usr/local/aws-sam-cli
  docker exec -u root "${CONTAINER_NAME}" ln -sf /usr/local/aws-sam-cli/current/bin/sam /usr/local/bin/sam
fi

echo "[4/4] Vinculando AWS CLI dentro del contenedor..."
if [ -d "/usr/local/aws-cli" ]; then
  docker cp /usr/local/aws-cli "${CONTAINER_NAME}":/usr/local/aws-cli
  docker exec -u root "${CONTAINER_NAME}" ln -sf /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws
fi

echo "=================================================================="
echo " [OK] Instalacion completada exitosamente en ${CONTAINER_NAME}."
echo " Ya puedes ir a Jenkins y hacer clic en el boton verde de Play!"
echo "=================================================================="
