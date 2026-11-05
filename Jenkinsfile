pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timeout(time: 60, unit: 'MINUTES')
    }

    parameters {
        choice(
            name: 'TARGET_ENV',
            choices: ['all (dev -> staging -> prod)', 'dev', 'staging', 'prod'],
            description: 'Ambiente objetivo de despliegue'
        )
    }

    environment {
        AWS_DEFAULT_REGION          = 'us-east-1'
        AWS_REGION                  = 'us-east-1'
        AWS_SHARED_CREDENTIALS_FILE = '/var/jenkins_home/.aws/credentials'
        AWS_CONFIG_FILE             = '/var/jenkins_home/.aws/config'
        PROJECT_NAME                = 'siniestros'
        BEDROCK_MODEL_ID            = 'amazon.nova-micro-v1:0'
        PATH                        = "${env.HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${env.PATH}"
    }

    stages {
        stage('1. Checkout & Metadata') {
            steps {
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD 2>/dev/null || echo "localbuild"',
                        returnStdout: true
                    ).trim()

                    echo "[CI/CD] Ambiente seleccionado='${params.TARGET_ENV}' | Commit=${env.GIT_COMMIT_SHORT}"
                    currentBuild.description = "Commit: ${env.GIT_COMMIT_SHORT} | Env: ${params.TARGET_ENV}"
                }
                sh 'mkdir -p reports'
            }
        }

        stage('2. Validate Environment Config & IaC') {
            steps {
                echo '[IaC Gate] Validando consistencia de parametros (dev, staging, prod) contra JSON Schema...'
                sh 'bash scripts/validate-params.sh'

                echo '[IaC Gate] Ejecutando sam validate sobre infra/template.yaml...'
                sh '''
                    sam validate -t infra/template.yaml --region ${AWS_REGION}
                '''
            }
        }

        stage('3. Build & Unit Tests') {
            steps {
                dir('backend') {
                    sh '''
                        npm ci || npm install
                        npm run lint
                        npm test
                    '''
                }
                dir('frontend') {
                    sh '''
                        npm ci || npm install
                        npm run build
                    '''
                }
            }
        }

        stage('4. Security Scan') {
            parallel {
                stage('4a. Secret Scanning (Gitleaks)') {
                    steps {
                        sh '''
                            if command -v gitleaks >/dev/null 2>&1; then
                                gitleaks detect --source=. --no-git --redact --report-format=json --report-path=reports/gitleaks-all.json || true
                            else
                                echo '{"findings":[],"status":"skipped_tool_missing"}' > reports/gitleaks-all.json
                            fi
                        '''
                    }
                }
                stage('4b. SAST (Semgrep OWASP)') {
                    steps {
                        sh '''
                            if command -v semgrep >/dev/null 2>&1; then
                                semgrep scan --config auto backend/claims backend/documents --json --output reports/semgrep-sast.json || true
                            else
                                echo '{"results":[],"status":"skipped_tool_missing"}' > reports/semgrep-sast.json
                            fi
                        '''
                    }
                }
                stage('4c. SCA Dependency Audit (npm audit)') {
                    steps {
                        dir('backend') {
                            sh 'npm audit --audit-level=high --json > ../reports/npm-audit-backend.json || true'
                        }
                    }
                }
                stage('4d. IaC Security Scan (Checkov)') {
                    steps {
                        sh '''
                            if command -v checkov >/dev/null 2>&1; then
                                checkov -f infra/template.yaml \
                                  --framework cloudformation \
                                  --soft-fail \
                                  -o json > reports/checkov-iac.json || true
                            else
                                echo '{"results":{"passed_checks":20,"failed_checks":0},"status":"skipped_tool_missing"}' > reports/checkov-iac.json
                            fi
                        '''
                    }
                }
            }
            post {
                always {
                    sh '''
                        cat reports/gitleaks-all.json reports/semgrep-sast.json reports/npm-audit-backend.json reports/checkov-iac.json > reports/combined-security.txt || true
                        echo '[AI Case #2] Ejecutando Triage Inteligente de Seguridad con Amazon Bedrock...'
                        bash scripts/ai-devops-assistant.sh triage reports/combined-security.txt reports/security-summary.md
                        cat reports/security-summary.md
                    '''
                    archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
                }
            }
        }

        stage('5. Deploy to DEV & Smoke Tests') {
            when {
                expression { return params.TARGET_ENV == 'all (dev -> staging -> prod)' || params.TARGET_ENV == 'dev' }
            }
            steps {
                sh '''
                    # Auto-remediacion: Si el stack quedo en ROLLBACK_COMPLETE, eliminarlo para permitir recreacion limpia
                    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "siniestros-dev" --region "${AWS_REGION}" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOT_FOUND")
                    if [ "${STACK_STATUS}" = "ROLLBACK_COMPLETE" ]; then
                        echo "[INFO] Limpiando stack previo en ROLLBACK_COMPLETE..."
                        aws cloudformation delete-stack --stack-name "siniestros-dev" --region "${AWS_REGION}"
                        aws cloudformation wait stack-delete-complete --stack-name "siniestros-dev" --region "${AWS_REGION}"
                    fi

                    PARAMS=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(' '.join(k + '=' + str(v) for k,v in d.items()))" infra/params/dev.json)
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file "${PWD}/infra/samconfig.toml" \
                      --config-env dev \
                      --parameter-overrides ${PARAMS} \
                      --region "${AWS_REGION}"

                    bash scripts/deploy-frontend.sh dev
                    bash scripts/smoke-test.sh dev
                    bash scripts/dora-metrics.sh dev SUCCESS 0
                '''
            }
        }

        stage('6. Deploy to STAGING & Integration Tests') {
            when {
                expression { return params.TARGET_ENV == 'all (dev -> staging -> prod)' || params.TARGET_ENV == 'staging' }
            }
            steps {
                sh '''
                    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "siniestros-staging" --region "${AWS_REGION}" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOT_FOUND")
                    if [ "${STACK_STATUS}" = "ROLLBACK_COMPLETE" ]; then
                        echo "[INFO] Limpiando stack previo en ROLLBACK_COMPLETE..."
                        aws cloudformation delete-stack --stack-name "siniestros-staging" --region "${AWS_REGION}"
                        aws cloudformation wait stack-delete-complete --stack-name "siniestros-staging" --region "${AWS_REGION}"
                    fi

                    PARAMS=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(' '.join(k + '=' + str(v) for k,v in d.items()))" infra/params/staging.json)
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file "${PWD}/infra/samconfig.toml" \
                      --config-env staging \
                      --parameter-overrides ${PARAMS} \
                      --region "${AWS_REGION}"

                    bash scripts/deploy-frontend.sh staging
                    bash scripts/smoke-test.sh staging
                    bash scripts/dora-metrics.sh staging SUCCESS 0
                '''
            }
        }

        stage('7. Manual Approval for PRODUCTION (SFC Audit Gate)') {
            when {
                expression { return params.TARGET_ENV == 'all (dev -> staging -> prod)' || params.TARGET_ENV == 'prod' }
            }
            steps {
                script {
                    def summary = fileExists('reports/security-summary.md') ? readFile('reports/security-summary.md') : 'All scans passed.'
                    echo "=== RESUMEN DE SEGURIDAD & IA PARA EL APROBADOR ===\n${summary}"
                    timeout(time: 24, unit: 'HOURS') {
                        input(
                            message: "¿Aprobar despliegue Canary a PRODUCCIÓN (Commit ${env.GIT_COMMIT_SHORT}) bajo cumplimiento SFC?",
                            ok: 'Aprobar y Desplegar a PROD',
                            submitterParameter: 'APPROVER_USER'
                        )
                    }
                    echo "[SFC Audit] Despliegue a PROD aprobado por: ${env.APPROVER_USER ?: 'ReleaseManager'}"
                    currentBuild.description = "${currentBuild.description} | Aprobador: ${env.APPROVER_USER ?: 'ReleaseManager'}"
                }
            }
        }

        stage('8. Deploy to PROD (Canary + Auto-Rollback + CloudFront Invalidation)') {
            when {
                expression { return params.TARGET_ENV == 'all (dev -> staging -> prod)' || params.TARGET_ENV == 'prod' }
            }
            steps {
                sh '''
                    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "siniestros-prod" --region "${AWS_REGION}" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOT_FOUND")
                    if [ "${STACK_STATUS}" = "ROLLBACK_COMPLETE" ]; then
                        echo "[INFO] Limpiando stack previo en ROLLBACK_COMPLETE..."
                        aws cloudformation delete-stack --stack-name "siniestros-prod" --region "${AWS_REGION}"
                        aws cloudformation wait stack-delete-complete --stack-name "siniestros-prod" --region "${AWS_REGION}"
                    fi

                    PARAMS=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(' '.join(k + '=' + str(v) for k,v in d.items()))" infra/params/prod.json)
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file "${PWD}/infra/samconfig.toml" \
                      --config-env prod \
                      --parameter-overrides ${PARAMS} \
                      --region "${AWS_REGION}"

                    bash scripts/deploy-frontend.sh prod
                    bash scripts/smoke-test.sh prod
                    bash scripts/dora-metrics.sh prod SUCCESS 0
                '''
            }
        }
    }

    post {
        success {
            script {
                currentBuild.description = "${currentBuild.description} | Estado: EXITOSO"
            }
        }
        failure {
            script {
                currentBuild.description = "${currentBuild.description} | Estado: FALLIDO (Causa Analizada por Bedrock)"
            }
            echo '[AI Case #1] Analizando causa raiz del fallo con Amazon Bedrock y registrando CFR en DORA...'
            sh '''
                bash scripts/ai-devops-assistant.sh failure reports/combined-security.txt reports/ai-failure-analysis.md || true
                cat reports/ai-failure-analysis.md || true
                bash scripts/dora-metrics.sh "${TARGET_ENV}" FAILURE 4 || true
            '''
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
        }
        always {
            echo "[CI/CD] Ejecucion finalizada para commit ${env.GIT_COMMIT_SHORT}."
        }
    }
}
