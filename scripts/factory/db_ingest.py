#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
import time
from pathlib import Path

SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS repos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner TEXT NOT NULL,
  name TEXT NOT NULL,
  default_branch TEXT,
  UNIQUE(owner, name)
);
CREATE TABLE IF NOT EXISTS assets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  repo_id INTEGER NOT NULL,
  path TEXT NOT NULL,
  rel_path TEXT NOT NULL,
  content_type TEXT,
  size INTEGER,
  sha TEXT,
  ref TEXT,
  url TEXT,
  stored_path TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(repo_id) REFERENCES repos(id)
);
"""

def ensure_schema(conn: sqlite3.Connection):
    conn.executescript(SCHEMA)
    conn.commit()

def upsert_repo(conn, owner, name, default_branch):
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO repos(owner,name,default_branch) VALUES(?,?,?) ON CONFLICT(owner,name) DO UPDATE SET default_branch=excluded.default_branch",
        (owner, name, default_branch),
    )
    conn.commit()
    cur.execute("SELECT id FROM repos WHERE owner=? AND name=?", (owner, name))
    return cur.fetchone()[0]

def insert_asset(conn, repo_id, item):
    conn.execute(
        """
        INSERT INTO assets(repo_id,path,rel_path,content_type,size,sha,ref,url,stored_path)
        VALUES(?,?,?,?,?,?,?,?,?)
        """,
        (
            repo_id,
            item.get("path"),
            item.get("rel_path"),
            item.get("content_type"),
            int(item.get("size") or 0),
            item.get("sha"),
            item.get("branch"),
            item.get("url"),
            item.get("rel_path"),
        ),
    )

def main():
    ap = argparse.ArgumentParser(description="Ingest collected content into SQLite")
    ap.add_argument("catalog", help="Path to files.json produced by collect-content.ps1")
    ap.add_argument("out_db", help="Path to output SQLite DB file")
    args = ap.parse_args()

    catalog_path = Path(args.catalog)
    out_db = Path(args.out_db)
    out_db.parent.mkdir(parents=True, exist_ok=True)

    data = json.loads(catalog_path.read_text(encoding="utf-8"))
    conn = sqlite3.connect(str(out_db))
    ensure_schema(conn)

    # Cache repo IDs
    repo_cache = {}
    for item in data:
        owner_repo = item.get("ownerRepo", "")
        if "/" in owner_repo:
            owner, name = owner_repo.split("/", 1)
        else:
            owner, name = "", owner_repo
        key = (owner, name)
        if key not in repo_cache:
            repo_id = upsert_repo(conn, owner, name, item.get("branch"))
            repo_cache[key] = repo_id
        repo_id = repo_cache[key]
        insert_asset(conn, repo_id, item)

    conn.commit()
    conn.close()
    print(f"✅ Wrote database: {out_db}")

if __name__ == "__main__":
    main()
