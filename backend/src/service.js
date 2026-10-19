const crypto = require('crypto');
const { tx } = require('./db');
const P = require('./protocol');

const SID_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function randomSid() {
  const bytes = crypto.randomBytes(8);
  return Array.from(bytes, (b) => SID_CHARS[b % SID_CHARS.length]).join('');
}

function randomDigits(n) {
  let s = '';
  while (s.length < n) s += crypto.randomInt(0, 10);
  return s;
}

function createService({ pool, payout, config, log = () => {} }) {
  const limits = config.limits;

  async function enqueueSms(to, body, client = pool) {
    await client.query('INSERT INTO sms_outbox (to_phone, body) VALUES ($1, $2)', [to, body]);
  }

  async function createDevice({ phone, pinKey }) {
    const norm = P.normalizePhone(phone);
    if (!norm) throw Object.assign(new Error('invalid phone'), { status: 400 });
    const key = Buffer.from(String(pinKey || ''), 'base64');
    if (key.length !== 32) throw Object.assign(new Error('invalid pinKey'), { status: 400 });
    const sid = randomSid();
    const regCode = randomDigits(6);
    await pool.query('INSERT INTO devices (sid, phone, pin_key, reg_code) VALUES ($1, $2, $3, $4)', [
      sid,
      norm,
      key,
      regCode,
    ]);
    return { sid, regCode, gatewayNumber: config.gatewayNumber };
  }

  async function deviceStatus(sid) {
    const { rows } = await pool.query('SELECT verified, locked FROM devices WHERE sid = $1', [sid]);
    return rows[0] || null;
  }

  // The registration SMS proves the device holds the SIM it claimed. Older devices on the
  // same number are locked and their balance moves to the new one, like a UPI app re-bind.
  async function verifyRegistration(req, fromPhone) {
    return tx(pool, async (c) => {
      const { rows } = await c.query('SELECT * FROM devices WHERE sid = $1 FOR UPDATE', [req.sid]);
      const d = rows[0];
      if (!d || d.verified || d.reg_code !== req.regCode || d.phone !== fromPhone) return false;
      const old = await c.query(
        'SELECT sid, balance_paise FROM devices WHERE phone = $1 AND sid <> $2 AND verified AND NOT locked FOR UPDATE',
        [d.phone, d.sid],
      );
      let moved = 0;
      for (const o of old.rows) {
        const bal = Number(o.balance_paise);
        moved += bal;
        await c.query('UPDATE devices SET locked = TRUE, balance_paise = 0 WHERE sid = $1', [o.sid]);
        if (bal) await c.query('INSERT INTO ledger (sid, delta_paise, reason) VALUES ($1, $2, $3)', [o.sid, -bal, 'rebind_out']);
      }
      await c.query('UPDATE devices SET verified = TRUE, balance_paise = balance_paise + $2 WHERE sid = $1', [d.sid, moved]);
      if (moved) await c.query('INSERT INTO ledger (sid, delta_paise, reason) VALUES ($1, $2, $3)', [d.sid, moved, 'rebind_in']);
      await enqueueSms(d.phone, P.reply.registered(d.sid), c);
      return true;
    });
  }

  function result(code, extra = {}) {
    return { ok: false, code, ...extra };
  }

  function paymentResult(p, balance) {
    const base = { ctr: Number(p.ctr), ref: p.ref, amount: Number(p.amount_paise), vpa: p.vpa, status: p.status };
    if (p.status === 'failed') return { ...base, ok: false, code: p.fail_reason || 'FAILED' };
    return { ...base, ok: true, balance };
  }

  // Shared by the SMS and the internet channel. Never throws for user errors: the caller
  // always gets a result it can turn into a reply.
  async function processRequest(req, { channel, fromPhone }) {
    const pre = await tx(pool, async (c) => {
      const { rows } = await c.query('SELECT * FROM devices WHERE sid = $1 FOR UPDATE', [req.sid]);
      const d = rows[0];
      if (!d) return result('UNKNOWN');
      if (!d.verified) return result('NOT_REGISTERED');
      if (d.locked) return result('LOCKED');
      if (channel === 'sms' && fromPhone !== d.phone) return result('SIM_MISMATCH');

      if (!P.macEquals(P.mac(d.pin_key, req.signed), req.mac)) {
        const failed = d.failed_macs + 1;
        await c.query('UPDATE devices SET failed_macs = $2, locked = $3 WHERE sid = $1', [
          d.sid,
          failed,
          failed >= limits.maxFailedMacs,
        ]);
        return result(failed >= limits.maxFailedMacs ? 'LOCKED' : 'BAD_PIN', { ctr: req.ctr });
      }

      // The same signed request can arrive twice (SMS + internet retry). Answer it again.
      if (req.type === 'P') {
        const dup = await c.query('SELECT * FROM payments WHERE sid = $1 AND ctr = $2', [d.sid, req.ctr]);
        if (dup.rows[0]) return { done: paymentResult(dup.rows[0], Number(d.balance_paise)) };
      }
      if (req.ctr <= Number(d.last_ctr)) return result('REPLAY', { ctr: req.ctr });
      await c.query('UPDATE devices SET failed_macs = 0, last_ctr = $2 WHERE sid = $1', [d.sid, req.ctr]);

      const balance = Number(d.balance_paise);
      if (req.type === 'B') return { done: { ok: true, ctr: req.ctr, balance, status: 'balance' } };

      if (req.amount <= 0 || req.amount > limits.perPaymentPaise) return result('LIMIT', { ctr: req.ctr });
      const day = await c.query(
        `SELECT COALESCE(SUM(amount_paise), 0) AS s FROM payments
         WHERE sid = $1 AND status <> 'failed' AND created_at > now() - interval '24 hours'`,
        [d.sid],
      );
      if (Number(day.rows[0].s) + req.amount > limits.perDayPaise) return result('DAY_LIMIT', { ctr: req.ctr });
      if (balance < req.amount) return result('LOW_BALANCE', { ctr: req.ctr, balance });

      const ref = randomDigits(12);
      const ins = await c.query(
        `INSERT INTO payments (sid, ctr, amount_paise, vpa, channel, status, ref)
         VALUES ($1, $2, $3, $4, $5, 'processing', $6) RETURNING *`,
        [d.sid, req.ctr, req.amount, req.vpa, channel, ref],
      );
      await c.query('UPDATE devices SET balance_paise = balance_paise - $2 WHERE sid = $1', [d.sid, req.amount]);
      await c.query('INSERT INTO ledger (sid, delta_paise, reason, payment_id) VALUES ($1, $2, $3, $4)', [
        d.sid,
        -req.amount,
        'payment',
        ins.rows[0].id,
      ]);
      return { payment: ins.rows[0], balance: balance - req.amount };
    });

    if (!pre.payment) return pre.done || pre;

    const p = pre.payment;
    let out;
    try {
      out = await payout.send({ ref: p.ref, vpa: p.vpa, amountPaise: Number(p.amount_paise) });
    } catch (e) {
      // Unknown outcome: keep the money held and reconcile instead of refunding blindly.
      log('payout error', p.ref, e.message);
      out = { status: 'pending', reason: 'PAYOUT_ERROR' };
    }
    const final = await settle(p.ref, out.status, out.payoutRef, out.reason);
    return paymentResult(final.payment, final.balance);
  }

  // Moves a payment to its final state. Refunds on failure. Safe to call more than once.
  async function settle(ref, status, payoutRef, reason) {
    return tx(pool, async (c) => {
      const { rows } = await c.query('SELECT * FROM payments WHERE ref = $1 FOR UPDATE', [ref]);
      const p = rows[0];
      if (!p) return null;
      if (p.status === 'processing' || p.status === 'pending') {
        await c.query(
          `UPDATE payments SET status = $2, payout_ref = COALESCE($3, payout_ref), fail_reason = $4, updated_at = now()
           WHERE id = $1`,
          [p.id, status, payoutRef || null, reason || null],
        );
        if (status === 'failed') {
          await c.query('UPDATE devices SET balance_paise = balance_paise + $2 WHERE sid = $1', [p.sid, p.amount_paise]);
          await c.query('INSERT INTO ledger (sid, delta_paise, reason, payment_id) VALUES ($1, $2, $3, $4)', [
            p.sid,
            p.amount_paise,
            'refund',
            p.id,
          ]);
        }
        p.status = status;
        p.fail_reason = reason || null;
      }
      const d = await c.query('SELECT phone, balance_paise FROM devices WHERE sid = $1', [p.sid]);
      return { payment: p, balance: Number(d.rows[0].balance_paise), phone: d.rows[0].phone };
    });
  }

  function replyText(r) {
    if (r.status === 'balance') return P.reply.balance(r.ctr, r.balance);
    if (r.ok && r.status === 'success') return P.reply.ok(r.ctr, r.ref, r.amount, r.vpa, r.balance);
    if (r.ok) return P.reply.pending(r.ctr, r.ref, r.amount, r.vpa);
    return P.reply.fail(r.ctr ?? 0, r.code);
  }

  async function handleInboundSms(from, body) {
    const fromPhone = P.normalizePhone(from);
    const req = P.parseRequest(body);
    let outcome = 'ignored';
    if (fromPhone && req) {
      if (req.type === 'R') {
        outcome = (await verifyRegistration(req, fromPhone)) ? 'registered' : 'reg_rejected';
      } else {
        const r = await processRequest(req, { channel: 'sms', fromPhone });
        outcome = r.ok ? r.status : r.code;
        // Unknown or mismatched senders get no reply, so the gateway cannot be used to spam.
        if (!['UNKNOWN', 'SIM_MISMATCH'].includes(r.code)) await enqueueSms(fromPhone, replyText(r));
      }
    }
    await pool.query('INSERT INTO sms_inbox (from_phone, body, result) VALUES ($1, $2, $3)', [
      String(from).slice(0, 20),
      String(body).slice(0, 500),
      outcome,
    ]);
    return outcome;
  }

  // Called when PayU reports the final state of a pending payout.
  async function finalizePayout(ref, status, reason) {
    if (!['success', 'failed'].includes(status)) return null;
    const r = await settle(ref, status, null, reason);
    if (r) await enqueueSms(r.phone, replyText(paymentResult(r.payment, r.balance)));
    return r;
  }

  async function claimOutbox(limit = 10) {
    const { rows } = await pool.query(
      `UPDATE sms_outbox SET status = 'sending', attempts = attempts + 1, lease_until = now() + interval '60 seconds'
       WHERE id IN (
         SELECT id FROM sms_outbox
         WHERE status = 'queued' OR (status = 'sending' AND lease_until < now())
         ORDER BY id LIMIT $1 FOR UPDATE SKIP LOCKED)
       RETURNING id, to_phone AS "to", body`,
      [limit],
    );
    return rows;
  }

  async function ackOutbox(id, ok, error) {
    await pool.query(
      `UPDATE sms_outbox SET
         status = CASE WHEN $2 THEN 'sent' WHEN attempts >= 3 THEN 'failed' ELSE 'queued' END,
         error = $3, lease_until = NULL
       WHERE id = $1 AND status = 'sending'`,
      [id, ok, error || null],
    );
  }

  async function credit(phone, amountPaise, reason = 'admin_credit') {
    return tx(pool, async (c) => {
      const { rows } = await c.query(
        'SELECT sid FROM devices WHERE phone = $1 AND verified AND NOT locked ORDER BY created_at DESC LIMIT 1 FOR UPDATE',
        [P.normalizePhone(phone)],
      );
      if (!rows[0]) return null;
      const u = await c.query('UPDATE devices SET balance_paise = balance_paise + $2 WHERE sid = $1 RETURNING balance_paise', [
        rows[0].sid,
        amountPaise,
      ]);
      await c.query('INSERT INTO ledger (sid, delta_paise, reason) VALUES ($1, $2, $3)', [rows[0].sid, amountPaise, reason]);
      return { sid: rows[0].sid, balance: Number(u.rows[0].balance_paise) };
    });
  }

  return {
    createDevice,
    deviceStatus,
    processRequest,
    handleInboundSms,
    finalizePayout,
    claimOutbox,
    ackOutbox,
    credit,
    replyText,
  };
}

module.exports = { createService };
