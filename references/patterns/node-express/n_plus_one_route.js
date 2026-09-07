const { Pool } = require('pg');

// Pattern: DBM N+1 — one query per parent row
// Adapt: replace table/column names with domain entities
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://demo:demo@postgresql:5432/demo',
});

async function itemsWithDetails(req, res) {
  const { rows: parents } = await pool.query('SELECT * FROM parents');
  const results = [];
  for (const parent of parents) {
    const { rows: children } = await pool.query(
      'SELECT * FROM children WHERE parent_id = $1', [parent.id]
    );
    results.push({ parent, children });
  }
  res.json(results);
}

module.exports = { itemsWithDetails };
