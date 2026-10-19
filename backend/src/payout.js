// Payout adapters. Each returns { status: 'success' | 'pending' | 'failed', payoutRef?, reason? }.
//
// The PayU request shapes below follow PayU's Payouts API as we understand it. Check them
// against the docs PayU gives you with your payout credentials before going live, and
// run with PAYOUT_MODE=mock until then.

function mockPayout() {
  return {
    async send({ ref, vpa }) {
      if (vpa.startsWith('fail')) return { status: 'failed', reason: 'MOCK_DECLINED' };
      if (vpa.startsWith('slow')) return { status: 'pending', payoutRef: `MOCK${ref}` };
      return { status: 'success', payoutRef: `MOCK${ref}` };
    },
  };
}

function payuPayout(cfg, fetchImpl = fetch) {
  let token = null;
  let tokenExpiry = 0;

  async function getToken() {
    if (token && Date.now() < tokenExpiry - 60_000) return token;
    const res = await fetchImpl(cfg.tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'password',
        scope: 'create_payout_transactions',
        client_id: cfg.clientId,
        username: cfg.username,
        password: cfg.password,
      }),
    });
    if (!res.ok) throw new Error(`PayU token HTTP ${res.status}`);
    const body = await res.json();
    token = body.access_token;
    tokenExpiry = Date.now() + (body.expires_in || 3600) * 1000;
    return token;
  }

  return {
    async send({ ref, vpa, amountPaise }) {
      const res = await fetchImpl(cfg.payoutUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${await getToken()}`,
          payoutMerchantId: cfg.merchantId,
        },
        body: JSON.stringify([
          {
            beneficiaryName: vpa,
            vpa,
            amount: (amountPaise / 100).toFixed(2),
            merchantRefId: ref,
            paymentType: 'UPI',
            purpose: 'ZYVPAY transfer',
            batchId: ref,
          },
        ]),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok || body.status === 1 || body.error) {
        return { status: 'failed', reason: String(body.msg || body.error || `HTTP_${res.status}`).slice(0, 60) };
      }
      // PayU confirms the final state via webhook; treat the accepted request as pending.
      return { status: 'pending', payoutRef: ref };
    },
  };
}

function createPayout(cfg) {
  return cfg.mode === 'payu' ? payuPayout(cfg.payu) : mockPayout();
}

module.exports = { createPayout, mockPayout, payuPayout };
