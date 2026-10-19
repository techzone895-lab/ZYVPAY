const config = require('./config');
const { createPool, migrate } = require('./db');

(async () => {
  const pool = createPool(config.databaseUrl);
  await migrate(pool);
  await pool.end();
  console.log('migrated');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
