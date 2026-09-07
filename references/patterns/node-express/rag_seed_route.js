const { Pool } = require('pg');
const { OpenAI } = require('openai');
const tracer = require('dd-trace');

// Pattern: LLM Obs — Embed and store documents in pgvector for RAG
// Adapt: replace document schema with domain-specific fields
const pool = new Pool({ connectionString: process.env.DATABASE_URL || 'postgresql://demo:demo@postgresql:5432/demo' });
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
  for (let i = 0; i < docs.length; i++) {
    await pool.query(
      'INSERT INTO documents (title, content, embedding) VALUES ($1, $2, $3::vector)',
      [docs[i].title, docs[i].content, JSON.stringify(vectors[i])],
    );
  }
  res.json({ stored: docs.length });
}

module.exports = { seedDocuments };
