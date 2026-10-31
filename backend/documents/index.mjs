import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';
import { S3Client, PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const s3 = new S3Client({});

const HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization'
};

// Construye un archivo PDF válido con los datos del siniestro (sin requerir librerías externas)
function buildSimplePdf(claim) {
  const text = `REPORTE OFICIAL DE SINIESTRO (SFC) | ID: ${claim.claimId} | Poliza: ${claim.policyNumber} | Placa: ${claim.vehiclePlate} | Estado: ${claim.status} | Monto COP: ${claim.estimatedAmountCop}`;
  return Buffer.from(
    `%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj\n4 0 obj<</Length ${text.length + 35}>>stream\nBT /F1 11 Tf 40 720 Td (${text}) Tj ET\nendstream\nendobj\n5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\nxref\n0 6\n0000000000 65535 f \ntrailer<</Size 6/Root 1 0 R>>\nstartxref\n0\n%%EOF`
  );
}

export const handler = async (event) => {
  const tableName = process.env.CLAIMS_TABLE_NAME || 'siniestros-dev-claims';
  const bucketName = process.env.REPORTS_BUCKET_NAME || 'siniestros-dev-reports';
  const kmsKeyArn = process.env.KMS_KEY_ARN;

  if (event.httpMethod?.toUpperCase() === 'OPTIONS') {
    return { statusCode: 200, headers: HEADERS, body: JSON.stringify({ ok: true }) };
  }

  try {
    const body = event.body ? JSON.parse(event.body) : {};
    if (!body.claimId) {
      return { statusCode: 400, headers: HEADERS, body: JSON.stringify({ error: 'claimId es requerido' }) };
    }

    // 1. Consultar siniestro en DynamoDB
    const res = await ddb.send(new GetCommand({ TableName: tableName, Key: { claimId: body.claimId } }));
    if (!res?.Item) {
      return { statusCode: 404, headers: HEADERS, body: JSON.stringify({ error: 'Siniestro no encontrado' }) };
    }

    // 2. Generar reporte PDF y almacenarlo en el bucket S3 cifrado con KMS CMK
    const reportKey = `reports/${body.claimId}/reporte-${Date.now()}.pdf`;
    const pdfBuffer = buildSimplePdf(res.Item);

    await s3.send(
      new PutObjectCommand({
        Bucket: bucketName,
        Key: reportKey,
        Body: pdfBuffer,
        ContentType: 'application/pdf',
        ...(kmsKeyArn ? { ServerSideEncryption: 'aws:kms', SSEKMSKeyId: kmsKeyArn } : {})
      })
    );

    // 3. Generar URL prefirmada temporal (5 minutos = 300s) para proteger PII
    const downloadUrl = await getSignedUrl(
      s3,
      new GetObjectCommand({ Bucket: bucketName, Key: reportKey }),
      { expiresIn: 300 }
    );

    console.log(JSON.stringify({ level: 'INFO', event: 'PDF_REPORT_GENERATED', claimId: body.claimId, reportKey }));

    return {
      statusCode: 201,
      headers: HEADERS,
      body: JSON.stringify({
        message: 'Reporte PDF generado exitosamente',
        data: { claimId: body.claimId, reportKey, expiresInSeconds: 300, downloadUrl }
      })
    };
  } catch (err) {
    console.error(JSON.stringify({ level: 'ERROR', message: err.message }));
    return { statusCode: 500, headers: HEADERS, body: JSON.stringify({ error: 'Error generando PDF', detail: err.message }) };
  }
};

