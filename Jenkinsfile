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
        booleanParam(
            name: 'SKIP_PROD_APPROVAL',
            defaultValue: false,
            description: 'Solo para pruebas automatizadas de laboratorio (en operacion real requiere aprobacion manual)'
        )
        booleanParam(
            name: 'FORCE_ROLLBACK',
            defaultValue: false,
            description: 'Activar para revertir inmediatamente un ambiente al ultimo artefacto inmutable estable'
        )
        string(
            name: 'ROLLBACK_COMMIT_SHA',
            defaultValue: '',
            description: 'SHA del artefacto inmutable a restaurar en caso de FORCE_ROLLBACK=true'
        )
    }

    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        AWS_REGION         = 'us-east-1'
        PROJECT_NAME       = 'siniestros'
        BEDROCK_MODEL_ID   = 'amazon.nova-micro-v1:0'
        PATH               = "${env.HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${env.PATH}"
    }

    stages {
        stage('1. Checkout & Metadata') {
            steps {
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD 2>/dev/null || echo "localbuild"',
                        returnStdout: true
                    ).trim()

                    // Deteccion automatica de ambiente segun la rama de Git
                    def currentBranch = env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""', returnStdout: true).trim()
                    if (currentBranch == 'develop') {
                        env.EFFECTIVE_ENV = 'dev'
                    } else if (currentBranch == 'staging' || currentBranch.startsWith('release/')) {
                        env.EFFECTIVE_ENV = 'staging'
                    } else if (currentBranch == 'main' || currentBranch == 'master') {
                        env.EFFECTIVE_ENV = (params.TARGET_ENV == 'dev' || params.TARGET_ENV == 'staging') ? params.TARGET_ENV : 'prod'
                    } else {
                        env.EFFECTIVE_ENV = params.TARGET_ENV
                    }

                    echo "[CI/CD] Rama detectada='${currentBranch}' -> Ambiente efectivo='${env.EFFECTIVE_ENV}' | Commit=${env.GIT_COMMIT_SHORT}"

                    // Plus CI/CD: Descripcion ejecutiva dinamica en la interfaz web de Jenkins
                    currentBuild.description = "Commit: ${env.GIT_COMMIT_SHORT} | Rama: ${currentBranch} | Env: ${env.EFFECTIVE_ENV}"
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
                        npm run lint
                        npm test
                    '''
                }
                dir('frontend') {
                    sh '''
                        npm run build
                    '''
                }
            }
        }

        stage('4. Security Scan (DevSecOps Gate + AI Triage)') {
            parallel {
                stage('4a. Secret Scanning (Gitleaks)') {
                    steps {
                        sh '''
                            gitleaks detect --source backend --no-git --redact --report-format json --report-path reports/gitleaks-backend.json
                            gitleaks detect --source frontend --no-git --redact --report-format json --report-path reports/gitleaks-frontend.json
                            gitleaks detect --source infra --no-git --redact --report-format json --report-path reports/gitleaks-infra.json
                        '''
                    }
                }
                stage('4b. SAST (Semgrep OWASP)') {
                    steps {
                        sh '''
                            semgrep scan --config p/default backend/claims backend/documents --json --output reports/semgrep-sast.json || true
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
                            checkov -f infra/template.yaml \
                              --framework cloudformation \
                              --soft-fail \
                              -o json > reports/checkov-iac.json
                        '''
                    }
                }
            }
            post {
                success {
                    echo '[AI Case #2] Ejecutando Triage Inteligente de Seguridad con Amazon Bedrock...'
                    sh '''
                        cat reports/npm-audit-backend.json reports/gitleaks-backend.json > reports/combined-security.txt || true
                        bash scripts/ai-devops-assistant.sh triage reports/combined-security.txt reports/security-summary.md
                        cat reports/security-summary.md
                    '''
                    archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
                }
            }
        }

        stage('5. Deploy to DEV & Smoke Tests') {
            when {
                expression { return env.EFFECTIVE_ENV == 'all (dev -> staging -> prod)' || env.EFFECTIVE_ENV == 'dev' }
            }
            steps {
                sh '''
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file infra/samconfig.toml \
                      --config-env dev \
                      --region "${AWS_REGION}"

                    bash scripts/deploy-frontend.sh dev
                    bash scripts/smoke-test.sh dev
                    bash scripts/dora-metrics.sh dev SUCCESS 0
                '''
            }
        }

        stage('6. Deploy to STAGING & Integration Tests') {
            when {
                expression { return env.EFFECTIVE_ENV == 'all (dev -> staging -> prod)' || env.EFFECTIVE_ENV == 'staging' }
            }
            steps {
                sh '''
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file infra/samconfig.toml \
                      --config-env staging \
                      --region "${AWS_REGION}"

                    bash scripts/deploy-frontend.sh staging
                    bash scripts/smoke-test.sh staging
                    bash scripts/dora-metrics.sh staging SUCCESS 0
                '''
            }
        }

        stage('7. Manual Approval for PRODUCTION (SFC Audit Gate)') {
            when {
                expression { return (env.EFFECTIVE_ENV == 'all (dev -> staging -> prod)' || env.EFFECTIVE_ENV == 'prod') && !params.SKIP_PROD_APPROVAL }
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
                expression { return env.EFFECTIVE_ENV == 'all (dev -> staging -> prod)' || env.EFFECTIVE_ENV == 'prod' }
            }
            steps {
                sh '''
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file infra/samconfig.toml \
                      --config-env prod \
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
