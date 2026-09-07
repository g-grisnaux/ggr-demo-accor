const mysql = require('mysql2/promise');

// Pattern: DBM N+1 — one query per parent row (MySQL)
// Adapt: replace table/column names with domain entities
const pool = mysql.createPool(process.env.MYSQL_URL || 'mysql://demo:demo@mysql:3306/demo');

async function itemsWithDetails(req, res) {
  const [parents] = await pool.query('SELECT * FROM parents');
  const results = [];
  for (const parent of parents) {
    const [children] = await pool.query(
      'SELECT * FROM children WHERE parent_id = ?', [parent.id]
    );
    results.push({ parent, children });
  }
  res.json(results);
}

module.exports = { itemsWithDetails };
