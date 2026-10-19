const test = require('node:test');
const assert = require('node:assert');
const P = require('../src/protocol');

// Shared test vector: app/test/protocol_test.dart checks the same values.
const SECRET = Buffer.alloc(32, 7);
const PIN = '123456';
const PIN_KEY_B64 = 'QLsapKV6o6ftZ5m3FBNXmw9URJvIxAl0n7+DcPYkJi0=';
const PAY = 'ZP1 P ABCD2345 3 25050 shop@okaxis';
const PAY_MAC = 'pyW90s6BpJvGm5aS';

test('pin key and mac match the shared vector', () => {
  const k = P.derivePinKey(SECRET, PIN);
  assert.strictEqual(k.toString('base64'), PIN_KEY_B64);
  const req = P.parseRequest(`${PAY} ${PAY_MAC}`);
  assert.strictEqual(P.mac(k, req.signed), PAY_MAC);
});

test('parses pay, balance and register messages', () => {
  const p = P.parseRequest('ZP1 P ABCD2345 3 25050 Shop@OkAxis xxxxxxxxxxxxxxxx');
  assert.deepStrictEqual([p.type, p.sid, p.ctr, p.amount, p.vpa], ['P', 'ABCD2345', 3, 25050, 'shop@okaxis']);
  assert.strictEqual(P.parseRequest('ZP1 B ABCD2345 9 xxxxxxxxxxxxxxxx').ctr, 9);
  assert.deepStrictEqual(P.parseRequest('ZP1 R ABCD2345 123456'), { type: 'R', sid: 'ABCD2345', regCode: '123456' });
});

test('rejects malformed messages', () => {
  for (const t of ['hello', 'ZP1 P ABCD2345 3 25050 notavpa m', 'ZP1 R abc 1', 'ZP2 B ABCD2345 1 m', 'ZP1 P ABCD2345 -1 5 a@b m']) {
    assert.strictEqual(P.parseRequest(t), null, t);
  }
});

test('longest pay message fits in one SMS', () => {
  const vpa = `${'a'.repeat(64)}@${'b'.repeat(32)}`;
  const msg = `ZP1 P ABCDEFGHJK 999999999 999999999 ${vpa} ${'x'.repeat(16)}`;
  assert.ok(msg.length <= 160, String(msg.length));
  assert.ok(P.parseRequest(msg));
});

test('normalizes Indian phone numbers', () => {
  assert.strictEqual(P.normalizePhone('+91 98765-43210'), '9876543210');
  assert.strictEqual(P.normalizePhone('12345'), null);
});
