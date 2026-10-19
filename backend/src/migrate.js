const config = require('./config');
const { createPool, migrate } = require('./db');

(async () => {
  const pool = createPool(config.databaseUrl, config.dbSchema);
  await migrate(pool, config.dbSchema);
  await pool.end();
  console.log('migrated');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
