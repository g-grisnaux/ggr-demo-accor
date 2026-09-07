import os
import json
import psycopg2
from openai import OpenAI
from flask import request, jsonify
from ddtrace.llmobs.decorators import workflow, embedding, retrieval, llm

# Pattern: LLM Obs — RAG chat: embed query, search pgvector, generate response
# Adapt: replace system prompt and retrieval logic with domain context
DB_URL = os.environ.get("DATABASE_URL", "postgresql://demo:demo@postgresql:5432/demo")
_oai = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))


@embedding(model_name="text-embedding-3-small", model_provider="openai")
def _embed_query(text):
    resp = _oai.embeddings.create(model="text-embedding-3-small", input=[text])
    return resp.data[0].embedding


@retrieval
def _search_docs(query_vec):
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    cur.execute(
        "SELECT title, content, 1 - (embedding <=> %s::vector) AS score "
        "FROM documents ORDER BY embedding <=> %s::vector LIMIT 3",
        (json.dumps(query_vec), json.dumps(query_vec)),
    )
    rows = [{"title": r[0], "content": r[1], "score": float(r[2])} for r in cur.fetchall()]
    cur.close()
    conn.close()
    return rows


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
