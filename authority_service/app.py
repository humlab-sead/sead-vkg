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
ID_BASE = os.environ.get("ID_BASE", "https://w3id.org/sead/id/")

# Entity configuration for different types
ENTITY_CONFIGS = {
    "Site": {
        "view": "authority.sites",
        "fuzzy_func": "authority.fuzzy_sites",
        "id_field": "site_id",
        "label_field": "label",
        "exact_match_field": "national_site_identifier",
        "id_path": "site"
    },
    # Future entities can be added here
    # "Taxon": {
    #     "view": "authority.taxa", 
    #     "fuzzy_func": "authority.fuzzy_taxa",
    #     "id_field": "taxon_id",
    #     "label_field": "label",
    #     "exact_match_field": "genus_species",
    #     "id_path": "taxon"
    # }
}

app = FastAPI(title="SEAD Site Reconciliation")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.on_event("startup")
async def startup():
    # Single async connection (simple & fine for OpenRefine use)
    try:
        app.state.conn = await psycopg.AsyncConnection.connect(DB_DSN)
    except Exception as e:
        print(f"Failed to connect to database: {e}")
        raise

@app.on_event("shutdown")
async def shutdown():
    try:
        if hasattr(app.state, 'conn') and app.state.conn:
            await app.state.conn.close()
    except Exception as e:
        print(f"Error closing database connection: {e}")

# --- OpenRefine Reconciliation: service metadata ---
@app.get("/reconcile")
async def meta():
    default_types = [{"id": entity_type, "name": entity_type} for entity_type in ENTITY_CONFIGS.keys()]
    return {
        "name": "SEAD Entity Reconciliation",
        "identifierSpace": f"{ID_BASE}",
        "schemaSpace": "http://www.w3.org/2004/02/skos/core#",
        "defaultTypes": default_types,
    }

def _as_candidate(entity_id: Any, label: str, score: float, entity_type: str, config: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": f"{ID_BASE}{config['id_path']}/{entity_id}",
        "name": label,
        "score": min(100.0, round(score * 100, 2)),   # OpenRefine expects 0-100 as float
        "match": bool(score >= AUTO_ACCEPT),
        "type": [{"id": entity_type, "name": entity_type}],
    }

# --- OpenRefine Reconciliation: batch queries (POST is standard) ---
@app.post("/reconcile")
async def reconcile(request: Request):
    try:
        payload = await request.json()
        queries = payload.get("queries")
        if isinstance(queries, str):  # OpenRefine sometimes sends a JSON string
            queries = json.loads(queries)
        
        if not queries:
            return JSONResponse({"error": "No queries provided"}, status_code=400)

        results: Dict[str, Any] = {}
        async with app.state.conn.cursor(row_factory=dict_row) as cur:
            for qid, q in queries.items():
                text = (q.get("query") or "").strip()
                if not text:
                    results[qid] = {"result": []}
                    continue
                
                # Determine entity type (default to "Site" for backward compatibility)
                entity_type = q.get("type", "Site")
                if entity_type not in ENTITY_CONFIGS:
                    # Fall back to Site if type not recognized
                    entity_type = "Site"
                
                config = ENTITY_CONFIGS[entity_type]
                candidates = []
                
                # 1) exact match by external identifier if provided
                if config.get("exact_match_field"):
                    exact_sql = f"""
                        SELECT {config['id_field']}, {config['label_field']}, 1.0 AS name_sim
                        FROM {config['view']}
                        WHERE {config['exact_match_field']} = %(txt)s
                        LIMIT 1
                    """
                    await cur.execute(exact_sql, {"txt": text})
                    row = await cur.fetchone()
                    
                    if row:
                        candidates.append(_as_candidate(
                            row[config['id_field']], 
                            row[config['label_field']], 
                            1.0, 
                            entity_type, 
                            config
                        ))
                
                # 2) fuzzy name match if no exact match found
                if not candidates:
                    fuzzy_sql = f"SELECT * FROM {config['fuzzy_func']}(%(q)s, %(n)s);"
                    await cur.execute(fuzzy_sql, {"q": text, "n": 10})
                    rows = await cur.fetchall()
                    
                    for r in rows:
                        candidates.append(_as_candidate(
                            r[config['id_field']], 
                            r[config['label_field']], 
                            float(r["name_sim"]), 
                            entity_type, 
                            config
                        ))

                results[qid] = {"result": candidates}

        return JSONResponse(results)
    
    except psycopg.Error as e:
        return JSONResponse({"error": f"Database error: {str(e)}"}, status_code=500)
    except json.JSONDecodeError as e:
        return JSONResponse({"error": "Invalid JSON in request"}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": f"Internal server error: {str(e)}"}, status_code=500)

# --- Optional tiny HTML preview (OpenRefine can show on hover) ---
@app.get("/reconcile/preview")
async def preview(id: str):
    return HTMLResponse(f"<div style='padding:8px;font:14px system-ui'>SEAD Site: {id}</div>")
