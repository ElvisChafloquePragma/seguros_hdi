// ==============================================================================
// Caso de Uso IA #3 (ChatOps en Tiempo Real):
// CloudWatch Alarm -> SNS (AlertsTopic) -> Lambda IncidentAI -> CloudWatch Logs
// -> Sanitizacion PII (SFC) -> Amazon Bedrock (Nova Micro) -> SNS (ChatOpsSummaryTopic)
// ==============================================================================

// Cumplimiento SFC / Ley 1581: Enmascara PII (correos, llaves AWS, telefonos y cedulas)
// antes de enviar fragmentos de logs a Amazon Bedrock o canales ChatOps (Correo/Slack/Teams)
export function sanitizeLogText(rawText = '') {
  return String(rawText)
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[REDACTED_EMAIL]')
    .replace(/(AKIA|ASIA)[0-9A-Z]{16}/g, '[REDACTED_AWS_KEY]')
    .replace(/\+57\d{10}\b/g, '[REDACTED_PHONE]')
    .replace(/\b\d{7,10}\b/g, '[REDACTED_ID]');
}

export function resolveTargetLogGroup(alarmName = '', env = 'dev', project = 'siniestros') {
  const lower = String(alarmName).toLowerCase();
  if (lower.includes('document')) {
    return process.env.DOCUMENTS_LOG_GROUP || `/aws/lambda/${project}-${env}-documents`;
  }
  if (lower.includes('apigw') || lower.includes('5xx')) {
    return process.env.API_LOG_GROUP || `/aws/apigateway/${project}-${env}-api-access`;
  }
  return process.env.CLAIMS_LOG_GROUP || `/aws/lambda/${project}-${env}-claims`;
}

async function loadAwsClients(deps = {}) {
  if (deps.logsClient && deps.bedrockClient && deps.snsClient) {
    return deps;
  }
  const [logsMod, bedrockMod, snsMod] = await Promise.all([
    import('@aws-sdk/client-cloudwatch-logs'),
    import('@aws-sdk/client-bedrock-runtime'),
    import('@aws-sdk/client-sns')
  ]);
  return {
    logsClient: deps.logsClient || new logsMod.CloudWatchLogsClient({}),
    FilterLogEventsCommand: logsMod.FilterLogEventsCommand,
    bedrockClient: deps.bedrockClient || new bedrockMod.BedrockRuntimeClient({}),
    ConverseCommand: bedrockMod.ConverseCommand,
    snsClient: deps.snsClient || new snsMod.SNSClient({}),
    PublishCommand: snsMod.PublishCommand
  };
}

export const handler = async (event, deps = {}) => {
  const env = process.env.ENV || 'dev';
  const project = process.env.PROJECT_NAME || 'siniestros';
  const modelId = process.env.BEDROCK_MODEL_ID || 'amazon.nova-micro-v1:0';
  const chatopsTopicArn = process.env.CHATOPS_TOPIC_ARN;

  const records = Array.isArray(event?.Records) ? event.Records : [];
  if (records.length === 0) {
    return { statusCode: 400, processed: 0, reason: 'No SNS records found' };
  }

  const results = [];

  for (const record of records) {
    const rawSnsMessage = record?.Sns?.Message || '{}';
    let alarmPayload;
    try {
      alarmPayload = JSON.parse(rawSnsMessage);
    } catch {
      alarmPayload = {
        AlarmName: record?.Sns?.Subject || `${project}-${env}-manual-alert`,
        NewStateValue: 'ALARM',
        NewStateReason: rawSnsMessage
      };
    }

    const alarmName = alarmPayload.AlarmName || `${project}-${env}-unknown-alarm`;
    const stateValue = alarmPayload.NewStateValue || 'ALARM';
    const stateReason = alarmPayload.NewStateReason || 'Umbral de error superado';

    // Mejora FinOps: Ignorar transiciones a OK o INSUFFICIENT_DATA para no consumir Bedrock
    if (stateValue !== 'ALARM') {
      console.info(JSON.stringify({
        action: 'CHATOPS_SKIPPED_NON_ALARM',
        alarmName,
        stateValue
      }));
      results.push({ alarmName, status: 'SKIPPED_NON_ALARM' });
      continue;
    }

    const targetLogGroup = resolveTargetLogGroup(alarmName, env, project);
    const clients = await loadAwsClients(deps);

    // 1. Consultar los ultimos 10 minutos de logs en CloudWatch Logs
    let rawLogs = 'Sin eventos de error recientes en el LogGroup.';
    try {
      const startTime = Date.now() - 10 * 60 * 1000;
      const cmd = clients.FilterLogEventsCommand
        ? new clients.FilterLogEventsCommand({
            logGroupName: targetLogGroup,
            startTime,
            limit: 15
          })
        : { logGroupName: targetLogGroup, startTime, limit: 15 };
      const logRes = await clients.logsClient.send(cmd);
      const events = (logRes?.events || []).map((e) => e.message).filter(Boolean);
      if (events.length > 0) {
        rawLogs = events.slice(-10).join('\n');
      }
    } catch (logErr) {
      rawLogs = `No fue posible leer ${targetLogGroup}: ${logErr.message}`;
    }

    // 2. Sanitizar PII antes de enviar a Amazon Bedrock (Cumplimiento SFC CE 005/007 y Ley 1581)
    const sanitizedReason = sanitizeLogText(stateReason);
    const sanitizedLogs = sanitizeLogText(rawLogs);

    // 3. Invocar Amazon Bedrock (Nova Micro) para Diagnostico de Causa Raiz (RCA)
    const prompt = [
      'Eres un Ingeniero SRE Senior de una aseguradora colombiana regulada por la SFC.',
      'Analiza esta alerta critica en tiempo real y responde en espanol (maximo 140 palabras) con:',
      '1) Causa Raiz Probable,',
      '2) Estado del Auto-Rollback en AWS CodeDeploy,',
      '3) Comando o accion inmediata de verificacion.',
      '',
      `Ambiente: ${env}`,
      `Alarma disparada: ${alarmName}`,
      `Motivo de la alarma: ${sanitizedReason}`,
      `LogGroup inspeccionado: ${targetLogGroup}`,
      `Ultimos logs sanitizados:\n${sanitizedLogs}`
    ].join('\n');

    let aiDiagnosis = 'Diagnostico IA no disponible temporalmente. Revisar CloudWatch Logs manualmente.';
    try {
      const converseInput = {
        modelId,
        messages: [{ role: 'user', content: [{ text: prompt }] }],
        inferenceConfig: { maxTokens: 320, temperature: 0.1 }
      };
      const cmd = clients.ConverseCommand
        ? new clients.ConverseCommand(converseInput)
        : converseInput;
      const bedrockRes = await clients.bedrockClient.send(cmd);
      const text = bedrockRes?.output?.message?.content?.[0]?.text;
      if (text) {
        aiDiagnosis = sanitizeLogText(text.trim());
      }
    } catch (aiErr) {
      aiDiagnosis = `Fallback deterministico (Bedrock no disponible: ${aiErr.message}). Verificar ${targetLogGroup} y estado de rollback en CodeDeploy.`;
    }

    // 4. Construir reporte ejecutivo para Correo / Slack / Microsoft Teams (AWS Chatbot)
    const reportMessage = [
      `==================================================================`,
      `[HDI SEGUROS - CHATOPS INCIDENT RCA (${env.toUpperCase()})]`,
      `==================================================================`,
      `Alarma:      ${alarmName}`,
      `Estado:      ${stateValue}`,
      `LogGroup:    ${targetLogGroup}`,
      `Motivo:      ${sanitizedReason}`,
      `------------------------------------------------------------------`,
      `DIAGNOSTICO AUTOMATICO AMAZON BEDROCK (${modelId}):`,
      `${aiDiagnosis}`,
      `------------------------------------------------------------------`,
      `EVIDENCIA EN LOGS (PII SANITIZADO - CUMPLIMIENTO SFC):`,
      `${sanitizedLogs.slice(0, 800)}`,
      `==================================================================`
    ].join('\n');

    console.info(JSON.stringify({
      action: 'CHATOPS_RCA_GENERATED',
      alarmName,
      targetLogGroup,
      modelId,
      diagnosisPreview: aiDiagnosis.slice(0, 180)
    }));

    // 5. Publicar en el topico secundario ChatOpsSummaryTopic (evita bucle infinito con AlertsTopic)
    if (chatopsTopicArn) {
      const pubInput = {
        TopicArn: chatopsTopicArn,
        Subject: `[HDI Siniestros][RCA IA - ${env.toUpperCase()}] ${alarmName}`.slice(0, 100),
        Message: reportMessage
      };
      const pubCmd = clients.PublishCommand
        ? new clients.PublishCommand(pubInput)
        : pubInput;
      await clients.snsClient.send(pubCmd);
    }

    results.push({
      alarmName,
      status: 'RCA_PUBLISHED',
      targetLogGroup,
      diagnosis: aiDiagnosis
    });
  }

  return {
    statusCode: 200,
    processed: results.length,
    results
  };
};

