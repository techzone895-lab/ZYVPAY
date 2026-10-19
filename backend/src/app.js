const crypto = require('crypto');
const express = require('express');
const P = require('./protocol');

function tokenOk(given, expected) {
  if (!expected) return false;
  const a = Buffer.from(String(given || ''));
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function requireToken(expected, header) {
  return (req, res, next) => (tokenOk(req.get(header), expected) ? next() : res.status(401).json({ error: 'unauthorized' }));
}

const wrap = (fn) => (req, res, next) => fn(req, res).catch(next);

function createApp({ service, config }) {
  const app = express();
  app.use(express.json({ limit: '16kb' }));

  app.get('/health', (req, res) => res.json({ ok: true }));

  // ---- App (internet channel) ----
  app.post(
    '/api/devices',
    wrap(async (req, res) => {
      res.status(201).json(await service.createDevice(req.body || {}));
    }),
  );

  app.get(
    '/api/devices/:sid',
    wrap(async (req, res) => {
      const s = await service.deviceStatus(req.params.sid);
      if (!s) return res.status(404).json({ error: 'not_found' });
      res.json(s);
    }),
  );

  // Body: { text: "ZP1 P ..." } - exactly the SMS the app would otherwise send.
  app.post(
    '/api/request',
    wrap(async (req, res) => {
      const parsed = P.parseRequest(req.body && req.body.text);
      if (!parsed || parsed.type === 'R') return res.status(400).json({ error: 'bad_request' });
      const r = await service.processRequest(parsed, { channel: 'net' });
      res.json({ ...r, message: service.replyText(r) });
    }),
  );

  // ---- Gateway phone ----
  const gw = requireToken(config.gatewayToken, 'X-Gateway-Token');
  app.post(
    '/gateway/inbound',
    gw,
    wrap(async (req, res) => {
      const { from, body } = req.body || {};
      if (!from || !body) return res.status(400).json({ error: 'from and body required' });
      res.json({ outcome: await service.handleInboundSms(from, body) });
    }),
  );
  app.get(
    '/gateway/outbox',
    gw,
    wrap(async (req, res) => {
      res.json({ messages: await service.claimOutbox(Math.min(Number(req.query.limit) || 10, 50)) });
    }),
  );
  app.post(
    '/gateway/outbox/:id/ack',
    gw,
    wrap(async (req, res) => {
      await service.ackOutbox(Number(req.params.id), !!(req.body && req.body.ok), req.body && req.body.error);
      res.json({ ok: true });
    }),
  );

  // ---- PayU payout status callback ----
  app.post(
    '/webhooks/payu',
    requireToken(config.adminToken, 'X-Webhook-Token'),
    wrap(async (req, res) => {
      const b = req.body || {};
      const ref = b.merchantRefId || b.ref;
      const raw = String(b.status || b.event || '').toLowerCase();
      const status = raw.includes('success') ? 'success' : raw.includes('fail') || raw.includes('reject') ? 'failed' : null;
      if (!ref || !status) return res.status(400).json({ error: 'unrecognised payload' });
      await service.finalizePayout(String(ref), status, status === 'failed' ? 'PAYOUT_FAILED' : null);
      res.json({ ok: true });
    }),
  );

  // ---- Admin (until wallet top-up is built) ----
  app.post(
    '/admin/credit',
    requireToken(config.adminToken, 'X-Admin-Token'),
    wrap(async (req, res) => {
      const { phone, amountPaise } = req.body || {};
      if (!Number.isInteger(amountPaise) || amountPaise <= 0) return res.status(400).json({ error: 'amountPaise' });
      const r = await service.credit(phone, amountPaise);
      if (!r) return res.status(404).json({ error: 'no verified device for phone' });
      res.json(r);
    }),
  );

  app.use((err, req, res, next) => {
    if (err.status) return res.status(err.status).json({ error: err.message });
    console.error(err);
    res.status(500).json({ error: 'internal' });
  });

  return app;
}

module.exports = { createApp };
