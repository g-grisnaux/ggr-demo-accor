import os
import json
import psycopg2
from openai import OpenAI
from flask import request, jsonify
from ddtrace.llmobs.decorators import embedding

# Pattern: LLM Obs — Embed and store documents in pgvector for RAG
# Adapt: replace document schema with domain-specific fields
DB_URL = os.environ.get("DATABASE_URL", "postgresql://demo:demo@postgresql:5432/demo")
_oai = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))


@embedding(model_name="text-embedding-3-small", model_provider="openai")
def _embed(texts):
    resp = _oai.embeddings.create(model="text-embedding-3-small", input=texts)
    return [e.embedding for e in resp.data]


def seed_documents():
    docs = request.json.get("documents", [])
    texts = [d["content"] for d in docs]
    vectors = _embed(texts)
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    for doc, vec in zip(docs, vectors):
        cur.execute(
            "INSERT INTO documents (title, content, embedding) VALUES (%s, %s, %s::vector)",
            (doc["title"], doc["content"], json.dumps(vec)),
        )
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"stored": len(docs)})
