// End-to-end tests against a real Postgres. Set TEST_DATABASE_URL to an empty, throwaway database.
const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const { createPool, migrate } = require('../src/db');
const { createService } = require('../src/service');
const { createApp } = require('../src/app');
const { mockPayout } = require('../src/payout');
const P = require('../src/protocol');

const url = process.env.TEST_DATABASE_URL;
const config = {
  gatewayToken: 'gw-test',
  adminToken: 'admin-test',
  gatewayNumber: '9000000000',
  limits: { perPaymentPaise: 200000, perDayPaise: 500000, maxFailedMacs: 3 },
};

test('sms payment flow', { skip: !url && 'TEST_DATABASE_URL not set' }, async (t) => {
  const pool = createPool(url);
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate(pool);
  const service = createService({ pool, payout: mockPayout(), config });
  const server = createApp({ service, config }).listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.close();
    await pool.end();
  });

  const call = async (method, path, body, headers = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...headers },
      body: body && JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  };
  const gw = { 'X-Gateway-Token': 'gw-test' };
  const sms = (from, body) => call('POST', '/gateway/inbound', { from, body }, gw);
  const outbox = async () => {
    const { body } = await call('GET', '/gateway/outbox', null, gw);
    for (const m of body.messages) await call('POST', `/gateway/outbox/${m.id}/ack`, { ok: true }, gw);
    return body.messages;
  };

  const phone = '+91 98765 43210';
  const secret = crypto.randomBytes(32);
  const pinKey = P.derivePinKey(secret, '246810');
  let ctr = 0;
  const sign = (fields) => `${fields.join(' ')} ${P.mac(pinKey, fields)}`;
  const pay = (amt, vpa, key = pinKey) => {
    ctr += 1;
    const f = ['ZP1', 'P', sid, String(ctr), String(amt), vpa];
    return `${f.join(' ')} ${P.mac(key, f)}`;
  };

  assert.strictEqual((await call('GET', '/gateway/outbox')).status, 401);

  const reg = await call('POST', '/api/devices', { phone, pinKey: pinKey.toString('base64') });
  assert.strictEqual(reg.status, 201);
  const { sid, regCode } = reg.body;
  assert.strictEqual(reg.body.gatewayNumber, '9000000000');

  // Registration from a different SIM is ignored.
  assert.strictEqual((await sms('+911111111111', `ZP1 R ${sid} ${regCode}`)).body.outcome, 'reg_rejected');
  assert.strictEqual((await sms('919876543210', `ZP1 R ${sid} ${regCode}`)).body.outcome, 'registered');
  assert.strictEqual((await call('GET', `/api/devices/${sid}`)).body.verified, true);
  assert.match((await outbox())[0].body, new RegExp(`\\[ZP1 V ${sid} OK\\]`));

  const credit = await call('POST', '/admin/credit', { phone, amountPaise: 300000 }, { 'X-Admin-Token': 'admin-test' });
  assert.strictEqual(credit.body.balance, 300000);

  // Happy path over SMS.
  assert.strictEqual((await sms('9876543210', pay(25050, 'shop@okaxis'))).body.outcome, 'success');
  let [m] = await outbox();
  assert.strictEqual(m.to, '9876543210');
  assert.match(m.body, /\[ZP1 S 1 OK \d{12} 274950\]$/);

  // Same SMS again (e.g. resent) is answered, not charged twice.
  ctr -= 1;
  const again = pay(25050, 'shop@okaxis');
  assert.strictEqual((await sms('9876543210', again)).body.outcome, 'success');
  assert.match((await outbox())[0].body, /274950\]$/);

  // Wrong PIN, wrong SIM, over limit, low balance, declined payout (refunded).
  const wrongKey = P.derivePinKey(secret, '000000');
  assert.strictEqual((await sms('9876543210', pay(100, 'a@okaxis', wrongKey))).body.outcome, 'BAD_PIN');
  assert.strictEqual((await sms('9999999999', pay(100, 'a@okicici'))).body.outcome, 'SIM_MISMATCH');
  assert.strictEqual((await sms('9876543210', pay(200001, 'a@okicici'))).body.outcome, 'LIMIT');
  assert.strictEqual((await sms('9876543210', pay(5000, 'fail@okicici'))).body.outcome, 'MOCK_DECLINED');
  [, , m] = await outbox();
  assert.match(m.body, /FAIL MOCK_DECLINED\]$/);

  // Internet channel uses the same signed text; balance query shows the refund worked.
  ctr += 1;
  const bal = await call('POST', '/api/request', { text: sign(['ZP1', 'B', sid, String(ctr)]) });
  assert.strictEqual(bal.body.balance, 274950);

  // Old counter is a replay.
  const old = sign(['ZP1', 'B', sid, '1']);
  assert.strictEqual((await call('POST', '/api/request', { text: old })).body.code, 'REPLAY');

  // Pending payout settled later by webhook.
  const slow = await call('POST', '/api/request', { text: pay(1000, 'slow@okhdfc') });
  assert.strictEqual(slow.body.status, 'pending');
  await outbox();
  const hook = await call('POST', '/webhooks/payu', { merchantRefId: slow.body.ref, status: 'SUCCESS' }, { 'X-Webhook-Token': 'admin-test' });
  assert.strictEqual(hook.status, 200);
  assert.match((await outbox())[0].body, /OK \d{12} 273950\]$/);

  // Rs 260.50 spent so far today. Low balance first, then the Rs 5,000 daily limit.
  assert.strictEqual((await sms('9876543210', pay(200000, 'x@okaxis'))).body.outcome, 'success');
  assert.strictEqual((await sms('9876543210', pay(100000, 'x@okaxis'))).body.outcome, 'LOW_BALANCE');
  await call('POST', '/admin/credit', { phone, amountPaise: 300000 }, { 'X-Admin-Token': 'admin-test' });
  assert.strictEqual((await sms('9876543210', pay(200000, 'x@okaxis'))).body.outcome, 'success');
  assert.strictEqual((await sms('9876543210', pay(100000, 'x@okaxis'))).body.outcome, 'DAY_LIMIT');

  // Ledger always agrees with the balance.
  const { rows } = await pool.query(
    'SELECT d.balance_paise, (SELECT SUM(delta_paise) FROM ledger l WHERE l.sid = d.sid) AS sum FROM devices d WHERE sid = $1',
    [sid],
  );
  assert.strictEqual(Number(rows[0].balance_paise), Number(rows[0].sum));

  // Three wrong PINs in a row lock the device.
  await sms('9876543210', pay(100, 'a@okaxis', wrongKey));
  await sms('9876543210', pay(100, 'a@okaxis', wrongKey));
  assert.strictEqual((await sms('9876543210', pay(100, 'a@okaxis', wrongKey))).body.outcome, 'LOCKED');
});
