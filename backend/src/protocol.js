// ZP1 SMS protocol. Every message fits in a single 160-char GSM-7 SMS.
//
// App -> server
//   ZP1 R <sid> <regCode>                      register: binds the sender SIM to the device
//   ZP1 P <sid> <ctr> <amt> <vpa> <mac>        pay <amt> paise to <vpa>
//   ZP1 B <sid> <ctr> <mac>                    balance enquiry
//
// Server -> app (human text first, machine tag in square brackets at the end)
//   ... [ZP1 S <ctr> OK <ref> <balance>]
//   ... [ZP1 S <ctr> PEND <ref>]
//   ... [ZP1 S <ctr> FAIL <code>]
//   ... [ZP1 V <sid> OK]                      registration confirmed
//
// <mac> = first 16 chars of base64url(HMAC-SHA256(pinKey, canonical)), where
// canonical is the message fields joined by "|" and pinKey = HMAC-SHA256(deviceSecret, "pin|" + PIN).
// The server only ever stores pinKey; the device only stores deviceSecret and needs the PIN to sign.
const crypto = require('crypto');

const VERSION = 'ZP1';
const MAC_LEN = 16;
const VPA_RE = /^[a-z0-9._-]{1,64}@[a-z0-9.-]{2,32}$/;
const SID_RE = /^[A-Z0-9]{6,10}$/;

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function derivePinKey(deviceSecret, pin) {
  return crypto.createHmac('sha256', deviceSecret).update(`pin|${pin}`).digest();
}

function mac(pinKey, fields) {
  const h = crypto.createHmac('sha256', pinKey).update(fields.join('|')).digest();
  return b64url(h).slice(0, MAC_LEN);
}

function macEquals(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function normalizePhone(p) {
  const digits = String(p || '').replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : null;
}

// Returns {type, ...fields, signed} or null when the text is not a ZP1 request.
function parseRequest(text) {
  const parts = String(text || '').trim().split(/\s+/);
  if (parts[0] !== VERSION) return null;
  const type = parts[1];
  if (type === 'R' && parts.length === 4) {
    const [, , sid, regCode] = parts;
    if (!SID_RE.test(sid) || !/^\d{6}$/.test(regCode)) return null;
    return { type, sid, regCode };
  }
  if (type === 'P' && parts.length === 7) {
    const [, , sid, ctrS, amtS, vpaRaw, m] = parts;
    const vpa = vpaRaw.toLowerCase();
    if (!SID_RE.test(sid) || !/^\d{1,9}$/.test(ctrS) || !/^\d{1,9}$/.test(amtS) || !VPA_RE.test(vpa)) return null;
    const ctr = Number(ctrS);
    const amount = Number(amtS);
    return { type, sid, ctr, amount, vpa, mac: m, signed: [VERSION, type, sid, ctrS, amtS, vpa] };
  }
  if (type === 'B' && parts.length === 5) {
    const [, , sid, ctrS, m] = parts;
    if (!SID_RE.test(sid) || !/^\d{1,9}$/.test(ctrS)) return null;
    return { type, sid, ctr: Number(ctrS), mac: m, signed: [VERSION, type, sid, ctrS] };
  }
  return null;
}

function rupees(paise) {
  return (paise / 100).toFixed(2);
}

const reply = {
  registered: (sid) => `ZYVPAY: Aapka number verify ho gaya. [${VERSION} V ${sid} OK]`,
  ok: (ctr, ref, amount, vpa, balance) =>
    `ZYVPAY: Rs ${rupees(amount)} paid to ${vpa}. Ref ${ref}. [${VERSION} S ${ctr} OK ${ref} ${balance}]`,
  pending: (ctr, ref, amount, vpa) =>
    `ZYVPAY: Rs ${rupees(amount)} to ${vpa} processing. Ref ${ref}. [${VERSION} S ${ctr} PEND ${ref}]`,
  balance: (ctr, balance) => `ZYVPAY: Balance Rs ${rupees(balance)}. [${VERSION} S ${ctr} OK - ${balance}]`,
  fail: (ctr, code) => `ZYVPAY: Payment failed (${code}). [${VERSION} S ${ctr} FAIL ${code}]`,
};

module.exports = { VERSION, derivePinKey, mac, macEquals, normalizePhone, parseRequest, reply, rupees, b64url };
