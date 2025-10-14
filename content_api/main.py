#!/usr/bin/env python3
from fastapi import FastAPI, HTTPException, Query
from typing import List, Optional
import os
import sqlite3

DB_DEFAULT = os.getenv("DB_PATH", "out/dev/content-dev.sqlite")

app = FastAPI(title="Content API", version="0.1.0")

def get_conn(db_path: Optional[str] = None):
    path = db_path or DB_DEFAULT
    if not os.path.exists(path):
        raise HTTPException(status_code=500, detail=f"DB not found: {path}")
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/repos")
def list_repos(db: Optional[str] = None):
    with get_conn(db) as c:
        rows = c.execute("SELECT id, owner, name, default_branch FROM repos ORDER BY owner, name").fetchall()
        return [dict(r) for r in rows]

@app.get("/assets")
def list_assets(
    db: Optional[str] = None,
    repo: Optional[str] = Query(default=None, description="owner/name"),
    ext: Optional[str] = None,
    q: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
):
    with get_conn(db) as c:
        where = []
        params = []
        if repo:
            owner, name = repo.split("/", 1)
            where.append("r.owner=? AND r.name=?")
            params += [owner, name]
        if ext:
            where.append("a.path LIKE ?")
            params.append(f"%.{ext}")
        if q:
            where.append("a.path LIKE ?")
            params.append(f"%{q}%")
        sql = """
        SELECT a.id, r.owner||'/'||r.name AS repo, a.path, a.rel_path, a.content_type, a.size, a.sha, a.ref, a.url, a.stored_path, a.created_at
        FROM assets a JOIN repos r ON a.repo_id=r.id
        """
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += " ORDER BY a.created_at DESC LIMIT ? OFFSET ?"
        params += [limit, offset]
        rows = c.execute(sql, params).fetchall()
        return [dict(r) for r in rows]

@app.get("/assets/{asset_id}")
def get_asset(asset_id: int, db: Optional[str] = None):
    with get_conn(db) as c:
        r = c.execute(
            "SELECT a.id, r.owner||'/'||r.name AS repo, a.* FROM assets a JOIN repos r ON a.repo_id=r.id WHERE a.id=?",
            (asset_id,),
        ).fetchone()
        if not r:
            raise HTTPException(status_code=404, detail="asset not found")
        return dict(r)

@app.get("/modules")
def list_modules(db: Optional[str] = None, repo: Optional[str] = None):
    with get_conn(db) as c:
        where = []
        params = []
        if repo:
            owner, name = repo.split("/", 1)
            where.append("r.owner=? AND r.name=?")
            params += [owner, name]
        sql = """
        SELECT m.id, r.owner||'/'||r.name AS repo, m.module_name, m.gist_id, m.gist_url, m.visibility, m.description, m.created_at
        FROM modules m JOIN repos r ON m.repo_id=r.id
        """
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += " ORDER BY m.created_at DESC"
        rows = c.execute(sql, params).fetchall()
        return [dict(r) for r in rows]

@app.get("/modules/{module_id}/files")
def module_files(module_id: int, db: Optional[str] = None):
    with get_conn(db) as c:
        rows = c.execute("SELECT filename, raw_url FROM module_files WHERE module_id=?", (module_id,)).fetchall()
        return [dict(r) for r in rows]
