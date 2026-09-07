const { MongoClient } = require('mongodb');

// Pattern: DBM unindexed query — collection scan (COLLSCAN)
// Adapt: replace collection and field names with domain entities
const client = new MongoClient(process.env.MONGODB_URL || 'mongodb://demo:demo@mongodb:27017/demo');
const db = client.db();

async function findByCategory(category) {
  return db.collection('events').find({ category }).sort({ created_at: -1 }).limit(50).toArray();
}

module.exports = { findByCategory };
