const mysql = require('mysql2/promise');

// Pattern: DBM slow query — artificial delay via MySQL SLEEP
// Adapt: replace 'your_table' with a domain entity table
const pool = mysql.createPool(process.env.MYSQL_URL || 'mysql://demo:demo@mysql:3306/demo');

async function findAllSlow() {
  const [rows] = await pool.query(
    "SELECT *, SLEEP(0.3) FROM your_table ORDER BY created_at DESC LIMIT 50"
  );
  return rows;
}

module.exports = { findAllSlow };
