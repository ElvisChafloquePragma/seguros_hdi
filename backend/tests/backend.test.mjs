import test from 'node:test';
import assert from 'node:assert/strict';
import { maskPii, handler as claimsHandler } from '../claims/index.mjs';
import { handler as documentsHandler } from '../documents/index.mjs';
import { sanitizeLogText, resolveTargetLogGroup, handler as incidentAiHandler } from '../incident-ai/index.mjs';

test('Cumplimiento SFC: maskPii oculta cedula, nombre y telefono en los logs', () => {
  const masked = maskPii({
    insuredId: '1020304050',
    insuredName: 'Carlos Perez',
    insuredPhone: '+573001234567',
    vehiclePlate: 'ABC123'
  });
  assert.equal(masked.insuredId, '***050');
  assert.equal(masked.insuredName, 'C***');
  assert.equal(masked.insuredPhone, '***567');
  assert.equal(masked.vehiclePlate, 'ABC123');
});

test('Claims Lambda: responde 200 en OPTIONS y 400 cuando faltan datos en POST', async () => {
  const optRes = await claimsHandler({ httpMethod: 'OPTIONS' });
  assert.equal(optRes.statusCode, 200);

  const badPost = await claimsHandler({ httpMethod: 'POST', body: JSON.stringify({}) });
  assert.equal(badPost.statusCode, 400);
});

test('Documents Lambda: responde 200 en OPTIONS y 400 cuando falta claimId', async () => {
  const optRes = await documentsHandler({ httpMethod: 'OPTIONS' });
  assert.equal(optRes.statusCode, 200);

  const badPost = await documentsHandler({ httpMethod: 'POST', body: JSON.stringify({}) });
  assert.equal(badPost.statusCode, 400);
});

test('IncidentAI ChatOps (Caso IA #3): sanitiza PII y genera RCA con Bedrock ante estado ALARM', async () => {
  const clean = sanitizeLogText('Error con usuario carlos@hdi.com.co cedula 1020304050 key AKIAIOSFODNN7EXAMPLE');
  assert.ok(!clean.includes('carlos@hdi.com.co'));
  assert.ok(!clean.includes('1020304050'));
  assert.ok(!clean.includes('AKIAIOSFODNN7EXAMPLE'));
  assert.equal(resolveTargetLogGroup('siniestros-dev-documents-lambda-errors'), '/aws/lambda/siniestros-dev-documents');

  let publishedSns = null;
  process.env.CHATOPS_TOPIC_ARN = 'arn:aws:sns:us-east-1:123456789012:siniestros-dev-chatops-summary';

  const mockDeps = {
    logsClient: {
      send: async () => ({
        events: [{ message: 'ERROR ValidationException DynamoDB user test@hdi.com.co id 1098765432' }]
      })
    },
    bedrockClient: {
      send: async () => ({
        output: {
          message: {
            content: [{ text: '1) Causa Raiz: Error en DynamoDB. 2) CodeDeploy ejecutara auto-rollback. 3) Verificar tabla.' }]
          }
        }
      })
    },
    snsClient: {
      send: async (cmd) => {
        publishedSns = cmd;
        return { MessageId: 'msg-123' };
      }
    }
  };

  // 1. Verificar que ignora estado OK (ahorro FinOps)
  const okRes = await incidentAiHandler({
    Records: [{ Sns: { Message: JSON.stringify({ AlarmName: 'siniestros-dev-claims-errors', NewStateValue: 'OK' }) } }]
  }, mockDeps);
  assert.equal(okRes.results[0].status, 'SKIPPED_NON_ALARM');

  // 2. Verificar flujo completo en estado ALARM
  const alarmRes = await incidentAiHandler({
    Records: [{
      Sns: {
        Message: JSON.stringify({
          AlarmName: 'siniestros-dev-claims-lambda-errors',
          NewStateValue: 'ALARM',
          NewStateReason: 'Threshold Crossed: 1 datapoint >= 1.0'
        })
      }
    }]
  }, mockDeps);

  assert.equal(alarmRes.statusCode, 200);
  assert.equal(alarmRes.results[0].status, 'RCA_PUBLISHED');
  assert.ok(publishedSns.Message.includes('Causa Raiz'));
  assert.ok(publishedSns.Message.includes('[REDACTED_EMAIL]'));
});


