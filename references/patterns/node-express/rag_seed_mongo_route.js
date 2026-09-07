const { MongoClient } = require('mongodb');
const { OpenAI } = require('openai');
const tracer = require('dd-trace');

// Pattern: LLM Obs — Embed and store documents in MongoDB for RAG
// Adapt: replace document schema with domain-specific fields
const client = new MongoClient(process.env.MONGODB_URL || 'mongodb://demo:demo@mongodb:27017/demo');
const db = client.db();
const oai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const llmobs = tracer.llmobs;

const _embed = llmobs.wrap({ kind: 'embedding', modelName: 'text-embedding-3-small', modelProvider: 'openai' },
  async function embed(texts) {
    const resp = await oai.embeddings.create({ model: 'text-embedding-3-small', input: texts });
    return resp.data.map(e => e.embedding);
  }
);

async function seedDocuments(req, res) {
  const docs = req.body.documents || [];
  const texts = docs.map(d => d.content);
  const vectors = await _embed(texts);
  const records = docs.map((doc, i) => ({ title: doc.title, content: doc.content, embedding: vectors[i] }));
  await db.collection('documents').insertMany(records);
  res.json({ stored: docs.length });
}

module.exports = { seedDocuments };
