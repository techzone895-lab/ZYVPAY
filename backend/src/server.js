const config = require('./config');
const { createPool, migrate } = require('./db');
const { createPayout } = require('./payout');
const { createService } = require('./service');
const { createApp } = require('./app');

(async () => {
  if (!config.gatewayToken || !config.adminToken) throw new Error('GATEWAY_TOKEN and ADMIN_TOKEN must be set');
  const pool = createPool(config.databaseUrl);
  await migrate(pool);
  const service = createService({ pool, payout: createPayout(config.payout), config, log: console.log });
  createApp({ service, config }).listen(config.port, () => console.log(`zyvpay backend on :${config.port}`));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
