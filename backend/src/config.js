function int(name, def) {
  const v = process.env[name];
  return v === undefined || v === '' ? def : Number(v);
}

module.exports = {
  port: int('PORT', 8080),
  databaseUrl: process.env.DATABASE_URL || 'postgres://localhost:5432/zyvpay',
  gatewayToken: process.env.GATEWAY_TOKEN || '',
  adminToken: process.env.ADMIN_TOKEN || '',
  // Phone number of the SIM inside the gateway phone. The app sends SMS here.
  gatewayNumber: process.env.GATEWAY_NUMBER || '',
  limits: {
    perPaymentPaise: int('LIMIT_PER_PAYMENT_PAISE', 200000), // Rs 2,000
    perDayPaise: int('LIMIT_PER_DAY_PAISE', 500000), // Rs 5,000
    maxFailedMacs: int('MAX_FAILED_PIN', 5),
  },
  payout: {
    mode: process.env.PAYOUT_MODE || 'mock', // 'mock' | 'payu'
    payu: {
      tokenUrl: process.env.PAYU_TOKEN_URL || 'https://accounts.payu.in/oauth/token',
      payoutUrl: process.env.PAYU_PAYOUT_URL || 'https://payout.payumoney.com/payout/payment',
      clientId: process.env.PAYU_CLIENT_ID || '',
      username: process.env.PAYU_USERNAME || '',
      password: process.env.PAYU_PASSWORD || '',
      merchantId: process.env.PAYU_PAYOUT_MERCHANT_ID || '',
    },
  },
};
