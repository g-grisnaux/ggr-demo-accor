const { MongoClient } = require('mongodb');

// Pattern: DBM slow aggregation — expensive pipeline on large collection
// Adapt: replace collection and field names with domain entities
const client = new MongoClient(process.env.MONGODB_URL || 'mongodb://demo:demo@mongodb:27017/demo');
const db = client.db();

async function aggregateEvents() {
  return db.collection('events').aggregate([
    { $group: { _id: '$category', total: { $sum: '$amount' }, count: { $sum: 1 } } },
    { $sort: { total: -1 } },
    { $limit: 10 },
  ]).toArray();
}

module.exports = { aggregateEvents };
