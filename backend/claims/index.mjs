import { randomUUID } from 'node:crypto';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const secrets = new SecretsManagerClient({});

const HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PATCH,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization'
};

// Cumplimiento SFC / Ley 1581: Oculta datos sensibles (PII) antes de escribir en CloudWatch Logs
export function maskPii(data = {}) {
  return {
    ...data,
    insuredId: data.insuredId ? `***${String(data.insuredId).slice(-3)}` : undefined,
    insuredName: data.insuredName ? `${String(data.insuredName).charAt(0)}***` : undefined,
    insuredPhone: data.insuredPhone ? `***${String(data.insuredPhone).slice(-3)}` : undefined
  };
}

export const handler = async (event) => {
  const tableName = process.env.CLAIMS_TABLE_NAME || 'siniestros-dev-claims';
  const secretArn = process.env.INTEGRATION_SECRET_ARN;
  const method = event.httpMethod?.toUpperCase() || 'GET';

  if (method === 'OPTIONS') {
    return { statusCode: 200, headers: HEADERS, body: JSON.stringify({ ok: true }) };
  }

  try {
    // 1. POST /api/v1/claims - Registrar siniestro
    if (method === 'POST') {
      const body = event.body ? JSON.parse(event.body) : {};
      if (!body.policyNumber || !body.vehiclePlate || !body.insuredId) {
        return {
          statusCode: 400,
          headers: HEADERS,
          body: JSON.stringify({ error: 'Faltan campos obligatorios (policyNumber, vehiclePlate, insuredId)' })
        };
      }

      // Leer credencial de integracion desde AWS Secrets Manager (cifrado con KMS)
      if (secretArn) {
        await secrets.send(new GetSecretValueCommand({ SecretId: secretArn })).catch(() => null);
      }

      const item = {
        claimId: `CLM-${Date.now().toString(36).toUpperCase()}-${randomUUID().slice(0, 4).toUpperCase()}`,
        policyNumber: body.policyNumber,
        vehiclePlate: body.vehiclePlate,
        insuredId: body.insuredId,
        insuredName: body.insuredName || 'Asegurado Registrado',
        insuredPhone: body.insuredPhone || '+573000000000',
        city: body.city || body.location?.city || 'Bogotá',
        description: body.description || 'Reporte en terreno',
        estimatedAmountCop: Number(body.estimatedAmountCop || 0),
        status: 'REGISTERED',
        createdAt: new Date().toISOString()
      };

      await ddb.send(new PutCommand({ TableName: tableName, Item: item }));
      console.log(JSON.stringify({ level: 'INFO', event: 'CLAIM_CREATED', claim: maskPii(item) }));

      return { statusCode: 201, headers: HEADERS, body: JSON.stringify({ message: 'Siniestro creado', data: item }) };
    }

    // 2. GET /api/v1/claims/{id} - Consultar siniestro
    if (method === 'GET') {
      const claimId = event.pathParameters?.id;
      const res = await ddb.send(new GetCommand({ TableName: tableName, Key: { claimId } }));
      if (!res?.Item) {
        return { statusCode: 404, headers: HEADERS, body: JSON.stringify({ error: 'Siniestro no encontrado' }) };
      }
      return { statusCode: 200, headers: HEADERS, body: JSON.stringify({ data: res.Item }) };
    }

    // 3. PATCH /api/v1/claims/{id} - Actualizar estado o notas del siniestro
    if (method === 'PATCH') {
      const claimId = event.pathParameters?.id;
      const body = event.body ? JSON.parse(event.body) : {};
      const res = await ddb.send(
        new UpdateCommand({
          TableName: tableName,
          Key: { claimId },
          UpdateExpression: 'SET #status = :s, adjusterNotes = :n, updatedAt = :u',
          ExpressionAttributeNames: { '#status': 'status' },
          ExpressionAttributeValues: {
            ':s': body.status || 'IN_REVIEW',
            ':n': body.adjusterNotes || 'Actualizado por agente',
            ':u': new Date().toISOString()
          },
          ReturnValues: 'ALL_NEW'
        })
      );
      console.log(JSON.stringify({ level: 'INFO', event: 'CLAIM_UPDATED', claimId, status: body.status }));
      return { statusCode: 200, headers: HEADERS, body: JSON.stringify({ message: 'Actualizado', data: res?.Attributes }) };
    }

    return { statusCode: 405, headers: HEADERS, body: JSON.stringify({ error: 'Metodo no permitido' }) };
  } catch (err) {
    console.error(JSON.stringify({ level: 'ERROR', message: err.message }));
    return { statusCode: 500, headers: HEADERS, body: JSON.stringify({ error: 'Error interno', detail: err.message }) };
  }
};

