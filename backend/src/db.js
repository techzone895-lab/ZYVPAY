const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const _schema = (s) => (/^[a-z_][a-z0-9_]*$/i.test(s || '') ? s : 'zyvpay');

// Every connection in the pool runs with the ZYVPAY schema first on its search_path,
// so the same unqualified SQL works whether the database is dedicated or shared.
function createPool(connectionString, schema = 'zyvpay') {
  return new Pool({ connectionString, options: `-c search_path=${_schema(schema)},public` });
}

async function migrate(pool, schema = 'zyvpay') {
  const s = _schema(schema);
  const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  await pool.query(`CREATE SCHEMA IF NOT EXISTS ${s}; SET search_path TO ${s}, public;\n${sql}`);
}

async function tx(pool, fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

module.exports = { createPool, migrate, tx };
