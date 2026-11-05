# ==============================================================================
# Imagen de Jenkins para el pipeline de Siniestros HDI (DevSecOps reproducible)
#
# Por que existe: las herramientas de seguridad y de despliegue NO deben instalarse
# a mano dentro del contenedor ni descargarse en cada build. Con esta imagen el
# runner es determinista: versiones fijas, auditables y reconstruibles en minutos.
#
# Construir:   docker build -t jenkins-hdi:1.0 ci/jenkins
# Ejecutar:    docker run -d --name jenkins-lab -p 8080:8080 -p 50000:50000 \
#                -v <ruta_local>/jenkins_home:/var/jenkins_home \
#                -v /var/run/docker.sock:/var/run/docker.sock jenkins-hdi:1.0
# (Mismo jenkins_home: jobs, credenciales y plugins se conservan.)
# ==============================================================================
FROM jenkins/jenkins:lts-jdk21

USER root

ARG GITLEAKS_VERSION=8.18.4
ARG SAM_CLI_VERSION=1.170.0
ARG SEMGREP_VERSION=1.183.0
ARG CHECKOV_VERSION=3.4.3
ARG CHECK_JSONSCHEMA_VERSION=0.39.0

# Utilidades base + Node.js (build/test del backend y frontend) + Python (venvs)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      nodejs npm jq curl unzip git ca-certificates \
      python3 python3-pip python3-venv \
 && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 (oficial)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
 && unzip -q /tmp/awscliv2.zip -d /tmp \
 && /tmp/aws/install \
 && rm -rf /tmp/aws /tmp/awscliv2.zip

# AWS SAM CLI (oficial, version fija)
RUN curl -fsSL "https://github.com/aws/aws-sam-cli/releases/download/v${SAM_CLI_VERSION}/aws-sam-cli-linux-x86_64.zip" -o /tmp/sam.zip \
 && unzip -q /tmp/sam.zip -d /tmp/sam-installation \
 && /tmp/sam-installation/install \
 && rm -rf /tmp/sam-installation /tmp/sam.zip

# Gitleaks (binario oficial, version fija)
RUN curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks \
 && chmod +x /usr/local/bin/gitleaks

# Herramientas Python: un entorno virtual por herramienta, porque sus dependencias
# (p. ej. click) son incompatibles entre si. Versiones fijas.
RUN python3 -m venv /opt/semgrep && /opt/semgrep/bin/pip install --no-cache-dir "semgrep==${SEMGREP_VERSION}" \
 && python3 -m venv /opt/checkov && /opt/checkov/bin/pip install --no-cache-dir "checkov==${CHECKOV_VERSION}" \
 && python3 -m venv /opt/check-jsonschema && /opt/check-jsonschema/bin/pip install --no-cache-dir "check-jsonschema==${CHECK_JSONSCHEMA_VERSION}" \
 && ln -s /opt/semgrep/bin/semgrep /usr/local/bin/semgrep \
 && ln -s /opt/checkov/bin/checkov /usr/local/bin/checkov \
 && ln -s /opt/check-jsonschema/bin/check-jsonschema /usr/local/bin/check-jsonschema

# El script validate-params.sh y ai-devops-assistant.sh usan python3 con PyYAML/json
RUN apt-get update && apt-get install -y --no-install-recommends python3-yaml \
 && rm -rf /var/lib/apt/lists/*

USER jenkins
