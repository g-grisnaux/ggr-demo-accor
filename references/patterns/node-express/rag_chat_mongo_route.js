const { MongoClient } = require('mongodb');
const { OpenAI } = require('openai');
const tracer = require('dd-trace');

// Pattern: LLM Obs — RAG chat using MongoDB vector search
// Adapt: replace system prompt and retrieval logic with domain context
const client = new MongoClient(process.env.MONGODB_URL || 'mongodb://demo:demo@mongodb:27017/demo');
const db = client.db();
const oai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const llmobs = tracer.llmobs;

const _embedQuery = llmobs.wrap({ kind: 'embedding', modelName: 'text-embedding-3-small', modelProvider: 'openai' },
  async function embedQuery(text) {
    const resp = await oai.embeddings.create({ model: 'text-embedding-3-small', input: [text] });
    return resp.data[0].embedding;
  }
);

const _searchDocs = llmobs.wrap({ kind: 'retrieval' },
  async function searchDocs(queryVec) {
    return db.collection('documents').aggregate([
      { $vectorSearch: { index: 'vector_index', path: 'embedding', queryVector: queryVec, numCandidates: 50, limit: 3 } },
      { $project: { title: 1, content: 1, score: { $meta: 'vectorSearchScore' } } },
    ]).toArray();
  }
);

const _generate = llmobs.wrap({ kind: 'llm', modelName: 'gpt-4o-mini', modelProvider: 'openai' },
  async function generate(messages) {
    const resp = await oai.chat.completions.create({ model: 'gpt-4o-mini', messages });
    return resp.choices[0].message.content;
  }
);

const chat = llmobs.wrap({ kind: 'workflow', name: 'rag-chat-mongo' },
  async function ragChat(req, res) {
    const { message, history = [] } = req.body;
    const queryVec = await _embedQuery(message);
    const sources = await _searchDocs(queryVec);
    const context = sources.map(s => `[${s.title}]: ${s.content}`).join('\n\n');
    const messages = [
      { role: 'system', content: `Answer using this context:\n${context}` },
      ...history,
      { role: 'user', content: message },
    ];
    const answer = await _generate(messages);
    res.json({ response: answer, sources: sources.map(s => ({ title: s.title, score: s.score })) });
  }
);

module.exports = { chat };
