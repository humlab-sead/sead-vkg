# app.py
import os
import json
from typing import Dict, Any

import psycopg
from psycopg.rows import dict_row
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware

# --- config ---
DB_DSN = os.environ.get("DB_DSN", "postgresql://sead_user:***@localhost:5432/sead")
AUTO_ACCEPT = float(os.environ.get("AUTO_ACCEPT_THRESHOLD", "0.90"))  # score >= 0.90 => match=true
ID_BASE = os.environ.get("ID_BASE", "https://w3id.org/sead/id/site/")

app = FastAPI(title="SEAD Site Reconciliation")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.on_event("startup")
async def startup():
    # Single async connection (simple & fine for OpenRefine use)
    app.state.conn = await psycopg.AsyncConnection.connect(DB_DSN)

@app.on_event("shutdown")
async def shutdown():
    await app.state.conn.close()

# --- OpenRefine Reconciliation: service metadata ---
@app.get("/reconcile")
async def meta():
    return {
        "name": "SEAD Site Reconciliation",
        "identifierSpace": "https://w3id.org/sead/id/",
        "schemaSpace": "http://www.w3.org/2004/02/skos/core#",
        "defaultTypes": [{"id": "Site", "name": "Site"}],
    }

def _as_candidate(site_id: Any, label: str, score: float) -> Dict[str, Any]:
    return {
        "id": f"{ID_BASE}{site_id}",
        "name": label,
        "score": int(round(score * 100)),   # OpenRefine expects 0..100
        "match": bool(score >= AUTO_ACCEPT),
        "type": [{"id": "Site", "name": "Site"}],
    }

# --- OpenRefine Reconciliation: batch queries (POST is standard) ---
@app.post("/reconcile")
async def reconcile(request: Request):
    payload = await request.json()
    queries = payload.get("queries")
    if isinstance(queries, str):  # OpenRefine sometimes sends a JSON string
        queries = json.loads(queries)

    results: Dict[str, Any] = {}
    async with app.state.conn.cursor(row_factory=dict_row) as cur:
        for qid, q in queries.items():
            text = (q.get("query") or "").strip()
            if not text:
                results[qid] = {"result": []}
                continue
            
            # 1) exact match by external identifier if provided (national_site_identifier)
            hard_sql = """
                SELECT site_id, label, 1.0 AS name_sim
                FROM authority.sites
                WHERE national_site_identifier = %(txt)s
                LIMIT 1
            """
            await cur.execute(hard_sql, {"txt": text})
            row = await cur.fetchone()

            candidates = []
            if row:
                candidates.append(_as_candidate(row["site_id"], row["label"], 1.0))
            else:
                # 2) fuzzy name match on norm_label (uses pg_trgm via % operator)
                await cur.execute(
                    "SELECT * FROM authority.fuzzy_sites(%(q)s, %(n)s);",
                    {"q": text, "n": 10}
                )
                rows = await cur.fetchall()
                for r in rows:
                    candidates.append(_as_candidate(r["site_id"], r["label"], float(r["name_sim"])))

            results[qid] = {"result": candidates}

    return JSONResponse(results)

# --- Optional tiny HTML preview (OpenRefine can show on hover) ---
@app.get("/reconcile/preview")
async def preview(id: str):
    return HTMLResponse(f"<div style='padding:8px;font:14px system-ui'>SEAD Site: {id}</div>")
