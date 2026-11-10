import test from 'node:test';
import assert from 'node:assert/strict';
import { maskPii, handler as claimsHandler } from '../claims/index.mjs';
import { handler as documentsHandler } from '../documents/index.mjs';

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
