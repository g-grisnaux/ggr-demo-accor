import os
from openai import OpenAI
from pymongo import MongoClient
from flask import request, jsonify
from ddtrace.llmobs.decorators import workflow, embedding, retrieval, llm

# Pattern: LLM Obs — RAG chat using MongoDB vector search
# Adapt: replace system prompt and retrieval logic with domain context
MONGO_URL = os.environ.get("MONGODB_URL", "mongodb://demo:demo@mongodb:27017/demo")
_oai = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
_db = MongoClient(MONGO_URL).get_default_database()


@embedding(model_name="text-embedding-3-small", model_provider="openai")
def _embed_query(text):
    resp = _oai.embeddings.create(model="text-embedding-3-small", input=[text])
    return resp.data[0].embedding


@retrieval
def _search_docs(query_vec):
    results = _db.documents.aggregate([
        {"$vectorSearch": {"index": "vector_index", "path": "embedding", "queryVector": query_vec, "numCandidates": 50, "limit": 3}},
        {"$project": {"title": 1, "content": 1, "score": {"$meta": "vectorSearchScore"}}},
    ])
    return [{"title": r["title"], "content": r["content"], "score": r["score"]} for r in results]


@llm(model_name="gpt-4o-mini", model_provider="openai")
def _generate(messages):
    resp = _oai.chat.completions.create(model="gpt-4o-mini", messages=messages)
    return resp.choices[0].message.content


@workflow
def chat():
    body = request.json
    user_msg = body.get("message", "")
    history = body.get("history", [])
    query_vec = _embed_query(user_msg)
    sources = _search_docs(query_vec)
    context = "\n\n".join(f"[{s['title']}]: {s['content']}" for s in sources)
    messages = [
        {"role": "system", "content": f"Answer using this context:\n{context}"},
        *history,
        {"role": "user", "content": user_msg},
    ]
    answer = _generate(messages)
    return jsonify({"response": answer, "sources": [{"title": s["title"], "score": s["score"]} for s in sources]})
