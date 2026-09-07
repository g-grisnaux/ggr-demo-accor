const { Pool } = require('pg');

// Pattern: Code Security — SQL injection via string concatenation
// WARNING: intentionally vulnerable for IAST demo
// Adapt: replace table/column with domain entity
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://demo:demo@postgresql:5432/demo',
});

async function search(req, res) {
  const q = req.query.q || '';
  const { rows } = await pool.query(
    `SELECT * FROM items WHERE name LIKE '%${q}%'`  // eslint-disable-line no-sql-injection
  );
  res.json(rows);
}

module.exports = { search };
