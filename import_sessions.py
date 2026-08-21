#!/usr/bin/env python3
"""
Standalone fallback ingestion for claude-mem.

Reads .jsonl transcripts from ~/.claude/projects/ and writes observations
to the claude-mem SQLite database at ~/.claude-mem/claude-mem.db.

Use this when the built-in Bun ingestion script is unavailable:
    python3 import_sessions.py
    python3 import_sessions.py --claude-dir /path/to/.claude --db /path/to/claude-mem.db
"""

import argparse
import json
import sqlite3
from pathlib import Path


DEFAULT_CLAUDE_DIR = Path.home() / ".claude" / "projects"
DEFAULT_DB_PATH = Path.home() / ".claude-mem" / "claude-mem.db"


def setup_db(conn):
    with conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS observations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                project TEXT,
                type TEXT NOT NULL,
                text_content TEXT NOT NULL,
                timestamp TEXT,
                source_file TEXT
            );
        """)
        conn.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS observations_fts
            USING fts5(text_content, content=observations, content_rowid=id);
        """)
        conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_observations_session
            ON observations(session_id);
        """)
        conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_observations_project
            ON observations(project);
        """)


def classify_type(data):
    role = data.get("type") or data.get("role", "unknown")
    if role == "tool_use":
        return "tool_use"
    if role == "tool_result":
        return "tool_result"
    if role == "assistant":
        return "response"
    if role == "human" or role == "user":
        return "prompt"
    return role


def import_sessions(claude_dir, db_path):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    setup_db(conn)

    if not claude_dir.exists():
        print(f"Directory {claude_dir} does not exist.")
        return

    jsonl_files = list(claude_dir.rglob("*.jsonl"))
    print(f"Found {len(jsonl_files)} transcript files.")

    imported = 0
    for file_path in jsonl_files:
        session_id = file_path.stem
        project_name = file_path.parent.name

        with open(file_path, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue

                obs_type = classify_type(data)
                content = str(data.get("message") or data.get("content", ""))
                if not content.strip():
                    continue

                ts = data.get("timestamp", "")

                with conn:
                    cur = conn.execute(
                        """INSERT INTO observations
                           (session_id, project, type, text_content, timestamp, source_file)
                           VALUES (?, ?, ?, ?, ?, ?)""",
                        (session_id, project_name, obs_type, content, ts, str(file_path)),
                    )
                    conn.execute(
                        """INSERT INTO observations_fts(rowid, text_content)
                           VALUES (?, ?)""",
                        (cur.lastrowid, content),
                    )
                    imported += 1

    conn.close()
    print(f"Imported {imported} observations into {db_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Import Claude CLI sessions into claude-mem")
    parser.add_argument(
        "--claude-dir", type=Path, default=DEFAULT_CLAUDE_DIR,
        help=f"Path to Claude projects directory (default: {DEFAULT_CLAUDE_DIR})",
    )
    parser.add_argument(
        "--db", type=Path, default=DEFAULT_DB_PATH,
        help=f"Path to claude-mem SQLite database (default: {DEFAULT_DB_PATH})",
    )
    args = parser.parse_args()
    import_sessions(args.claude_dir, args.db)
