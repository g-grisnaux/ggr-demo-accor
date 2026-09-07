const { Pool } = require('pg');

// Pattern: DBM slow query — artificial delay via pg_sleep
// Adapt: replace 'your_table' with a domain entity table
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://demo:demo@postgresql:5432/demo',
});

async function findAllSlow() {
  const { rows } = await pool.query(
    "SELECT *, pg_sleep(0.3) FROM your_table ORDER BY created_at DESC LIMIT 50"
  );
  return rows;
}

module.exports = { findAllSlow };
