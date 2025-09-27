# app.py
import os
import json
from typing import Dict, Any, List, Optional, Protocol
from abc import ABC, abstractmethod

import psycopg
from psycopg.rows import dict_row
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware

# --- config ---
DB_DSN = os.environ.get("DB_DSN", "postgresql://sead_user:***@localhost:5432/sead")
AUTO_ACCEPT = float(os.environ.get("AUTO_ACCEPT_THRESHOLD", "0.90"))
ID_BASE = os.environ.get("ID_BASE", "https://w3id.org/sead/id/")

# --- Strategy Pattern for Entity-Specific Reconciliation ---

class ReconciliationStrategy(ABC):
    """Abstract base class for entity-specific reconciliation strategies"""
    
    @abstractmethod
    async def find_candidates(self, query: str, cursor, limit: int = 10) -> List[Dict[str, Any]]:
        """Find candidate matches for the given query"""
        pass
    
    @abstractmethod
    def get_entity_id_field(self) -> str:
        """Return the ID field name for this entity type"""
        pass
    
    @abstractmethod
    def get_label_field(self) -> str:
        """Return the label field name for this entity type"""
        pass
    
    @abstractmethod
    def get_id_path(self) -> str:
        """Return the URL path segment for this entity type"""
        pass

class SiteReconciliationStrategy(ReconciliationStrategy):
    """Site-specific reconciliation with place names and coordinates"""
    
    def get_entity_id_field(self) -> str:
        return "site_id"
    
    def get_label_field(self) -> str:
        return "label"
    
    def get_id_path(self) -> str:
        return "site"
    
    async def find_candidates(self, query: str, cursor, limit: int = 10) -> List[Dict[str, Any]]:
        candidates = []
        
        # Parse query for additional context (this could be more sophisticated)
        query_parts = self._parse_query(query)
        
        # 1) Exact match by national site identifier
        if query_parts.get("identifier"):
            exact_sql = """
                SELECT site_id, label, 1.0 AS name_sim, latitude_dd, longitude_dd
                FROM authority.sites
                WHERE national_site_identifier = %(identifier)s
                LIMIT 1
            """
            await cursor.execute(exact_sql, {"identifier": query_parts["identifier"]})
            row = await cursor.fetchone()
            if row:
                candidates.append(dict(row))
        
        # 2) Fuzzy name matching with enhanced scoring
        if not candidates:
            candidates.extend(await self._fuzzy_name_search(query_parts["name"], cursor, limit))
        
        # 3) Geographic proximity boost if coordinates provided
        if query_parts.get("coordinates") and candidates:
            candidates = await self._apply_geographic_scoring(
                candidates, query_parts["coordinates"], cursor
            )
        
        # 4) Place name context boost
        if query_parts.get("place") and candidates:
            candidates = await self._apply_place_context_scoring(
                candidates, query_parts["place"], cursor
            )
        
        return sorted(candidates, key=lambda x: x.get("name_sim", 0), reverse=True)[:limit]
    
    def _parse_query(self, query: str) -> Dict[str, Any]:
        """Parse query string to extract different components"""
        # This is a simple implementation - you could make this more sophisticated
        # Examples of what you might parse:
        # "Site ABC near Stockholm (59.3293, 18.0686)"
        # "Site XYZ | ID: SE123456"
        
        parts = {"name": query.strip()}
        
        # Extract coordinates if present (lat, lon) format
        import re
        coord_pattern = r'\((-?\d+\.?\d*),\s*(-?\d+\.?\d*)\)'
        coord_match = re.search(coord_pattern, query)
        if coord_match:
            parts["coordinates"] = {
                "lat": float(coord_match.group(1)),
                "lon": float(coord_match.group(2))
            }
            parts["name"] = re.sub(coord_pattern, "", query).strip()
        
        # Extract identifier if present
        id_pattern = r'ID:\s*([^\s|]+)'
        id_match = re.search(id_pattern, query)
        if id_match:
            parts["identifier"] = id_match.group(1)
            parts["name"] = re.sub(id_pattern, "", parts["name"]).strip(" |")
        
        # Extract place context
        place_pattern = r'\bnear\s+([^(]+?)(?:\s*\(|$)'
        place_match = re.search(place_pattern, parts["name"], re.IGNORECASE)
        if place_match:
            parts["place"] = place_match.group(1).strip()
            parts["name"] = re.sub(place_pattern, "", parts["name"], flags=re.IGNORECASE).strip()
        
        return parts
    
    async def _fuzzy_name_search(self, name: str, cursor, limit: int) -> List[Dict[str, Any]]:
        """Perform fuzzy name search"""
        fuzzy_sql = "SELECT * FROM authority.fuzzy_sites(%(q)s, %(n)s);"
        await cursor.execute(fuzzy_sql, {"q": name, "n": limit})
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]
    
    async def _apply_geographic_scoring(self, candidates: List[Dict], coords: Dict, cursor) -> List[Dict]:
        """Boost scores based on geographic proximity"""
        if not coords or not candidates:
            return candidates
        
        # Create a list of site IDs for batch geographic query
        site_ids = [c["site_id"] for c in candidates]
        
        geo_sql = """
            SELECT site_id, 
                   ST_Distance(
                       ST_Transform(ST_SetSRID(ST_MakePoint(longitude_dd, latitude_dd), 4326), 3857),
                       ST_Transform(ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326), 3857)
                   ) / 1000.0 as distance_km
            FROM authority.sites 
            WHERE site_id = ANY(%(site_ids)s) 
              AND latitude_dd IS NOT NULL 
              AND longitude_dd IS NOT NULL
        """
        
        await cursor.execute(geo_sql, {
            "lat": coords["lat"], 
            "lon": coords["lon"], 
            "site_ids": site_ids
        })
        
        geo_results = {row["site_id"]: row["distance_km"] for row in await cursor.fetchall()}
        
        # Apply distance-based scoring boost
        for candidate in candidates:
            site_id = candidate["site_id"]
            if site_id in geo_results:
                distance = geo_results[site_id]
                # Boost score based on proximity (closer = higher boost)
                # Max boost of 0.2 for sites within 1km, diminishing to 0 at 100km
                proximity_boost = max(0, 0.2 * (1 - min(distance / 100.0, 1.0)))
                candidate["name_sim"] = min(1.0, candidate["name_sim"] + proximity_boost)
                candidate["distance_km"] = distance
        
        return candidates
    
    async def _apply_place_context_scoring(self, candidates: List[Dict], place: str, cursor) -> List[Dict]:
        """Boost scores based on place name context"""
        # This could query a places/regions table or use external geocoding
        # For now, simple implementation checking site descriptions
        
        place_sql = """
            SELECT site_id, similarity(site_description, %(place)s) as place_sim
            FROM authority.sites 
            WHERE site_id = ANY(%(site_ids)s) 
              AND site_description IS NOT NULL
        """
        
        site_ids = [c["site_id"] for c in candidates]
        await cursor.execute(place_sql, {"place": place, "site_ids": site_ids})
        
        place_results = {row["site_id"]: row["place_sim"] for row in await cursor.fetchall()}
        
        # Apply place context boost
        for candidate in candidates:
            site_id = candidate["site_id"]
            if site_id in place_results and place_results[site_id] > 0.3:
                place_boost = place_results[site_id] * 0.1  # Max boost of 0.1
                candidate["name_sim"] = min(1.0, candidate["name_sim"] + place_boost)
        
        return candidates

class TaxonReconciliationStrategy(ReconciliationStrategy):
    """Future taxon reconciliation strategy"""
    
    def get_entity_id_field(self) -> str:
        return "taxon_id"
    
    def get_label_field(self) -> str:
        return "scientific_name"
    
    def get_id_path(self) -> str:
        return "taxon"
    
    async def find_candidates(self, query: str, cursor, limit: int = 10) -> List[Dict[str, Any]]:
        # Implement taxon-specific logic here
        # Could handle genus/species parsing, synonym matching, etc.
        pass

# Entity configuration with strategy classes
ENTITY_CONFIGS = {
    "Site": {
        "strategy_class": SiteReconciliationStrategy,
    },
    # Future entities
    # "Taxon": {
    #     "strategy_class": TaxonReconciliationStrategy,
    # }
}

app = FastAPI(title="SEAD Entity Reconciliation")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.on_event("startup")
async def startup():
    try:
        app.state.conn = await psycopg.AsyncConnection.connect(DB_DSN)
        # Initialize strategy instances
        app.state.strategies = {
            entity_type: config["strategy_class"]() 
            for entity_type, config in ENTITY_CONFIGS.items()
        }
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

@app.get("/reconcile")
async def meta():
    default_types = [{"id": entity_type, "name": entity_type} for entity_type in ENTITY_CONFIGS.keys()]
    return {
        "name": "SEAD Entity Reconciliation",
        "identifierSpace": f"{ID_BASE}",
        "schemaSpace": "http://www.w3.org/2004/02/skos/core#",
        "defaultTypes": default_types,
    }

def _as_candidate(entity_data: Dict[str, Any], entity_type: str, strategy: ReconciliationStrategy) -> Dict[str, Any]:
    """Convert entity data to OpenRefine candidate format"""
    entity_id = entity_data[strategy.get_entity_id_field()]
    label = entity_data[strategy.get_label_field()]
    score = float(entity_data.get("name_sim", 0))
    
    candidate = {
        "id": f"{ID_BASE}{strategy.get_id_path()}/{entity_id}",
        "name": label,
        "score": min(100.0, round(score * 100, 2)),
        "match": bool(score >= AUTO_ACCEPT),
        "type": [{"id": entity_type, "name": entity_type}],
    }
    
    # Add additional metadata if available
    if "distance_km" in entity_data:
        candidate["distance_km"] = round(entity_data["distance_km"], 2)
    
    return candidate

@app.post("/reconcile")
async def reconcile(request: Request):
    try:
        payload = await request.json()
        queries = payload.get("queries")
        if isinstance(queries, str):
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
                
                # Determine entity type and get strategy
                entity_type = q.get("type", "Site")
                if entity_type not in ENTITY_CONFIGS:
                    entity_type = "Site"
                
                strategy = app.state.strategies[entity_type]
                
                # Use strategy to find candidates
                candidate_data = await strategy.find_candidates(text, cur, limit=10)
                
                # Convert to OpenRefine format
                candidates = [
                    _as_candidate(data, entity_type, strategy) 
                    for data in candidate_data
                ]
                
                results[qid] = {"result": candidates}

        return JSONResponse(results)
    
    except psycopg.Error as e:
        return JSONResponse({"error": f"Database error: {str(e)}"}, status_code=500)
    except json.JSONDecodeError as e:
        return JSONResponse({"error": "Invalid JSON in request"}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": f"Internal server error: {str(e)}"}, status_code=500)

@app.get("/reconcile/preview")
async def preview(id: str):
    return HTMLResponse(f"<div style='padding:8px;font:14px system-ui'>SEAD Entity: {id}</div>")
