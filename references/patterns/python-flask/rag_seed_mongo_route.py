import os
import json
from openai import OpenAI
from pymongo import MongoClient
from flask import request, jsonify
from ddtrace.llmobs.decorators import embedding

# Pattern: LLM Obs — Embed and store documents in MongoDB for RAG
# Adapt: replace document schema with domain-specific fields
MONGO_URL = os.environ.get("MONGODB_URL", "mongodb://demo:demo@mongodb:27017/demo")
_oai = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
_db = MongoClient(MONGO_URL).get_default_database()


@embedding(model_name="text-embedding-3-small", model_provider="openai")
def _embed(texts):
    resp = _oai.embeddings.create(model="text-embedding-3-small", input=texts)
    return [e.embedding for e in resp.data]


def seed_documents():
    docs = request.json.get("documents", [])
    texts = [d["content"] for d in docs]
    vectors = _embed(texts)
    for doc, vec in zip(docs, vectors):
        _db.documents.insert_one({"title": doc["title"], "content": doc["content"], "embedding": vec})
    return jsonify({"stored": len(docs)})
