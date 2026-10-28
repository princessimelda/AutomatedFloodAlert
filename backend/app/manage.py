"""Explicit migration/seed commands. Never run automatically on API startup."""

import argparse
import hashlib
from pathlib import Path

import psycopg
from psycopg.rows import dict_row

from .config import Settings

ROOT = Path(__file__).resolve().parents[2]


def migrate(connection, directory=ROOT / "supabase" / "migrations"):
    applied = []
    with connection.transaction():
        connection.execute("SELECT pg_advisory_xact_lock(hashtext('floodsafe-migrations'))")
        connection.execute("CREATE SCHEMA IF NOT EXISTS floodsafe_internal")
        connection.execute("REVOKE ALL ON SCHEMA floodsafe_internal FROM PUBLIC")
        connection.execute("""CREATE TABLE IF NOT EXISTS floodsafe_internal.schema_migrations (
            version text PRIMARY KEY, checksum text NOT NULL,
            applied_at timestamptz NOT NULL DEFAULT now())""")
        for path in sorted(directory.glob("*.sql")):
            content = path.read_bytes()
            checksum = hashlib.sha256(content).hexdigest()
            previous = connection.execute(
                "SELECT checksum FROM floodsafe_internal.schema_migrations WHERE version=%s",
                (path.stem,),
            ).fetchone()
            if previous:
                if previous["checksum"] != checksum:
                    raise ValueError(
                        "An applied migration was edited. Create a new migration instead."
                    )
                continue
            connection.execute(content.decode(), prepare=False)
            connection.execute(
                "INSERT INTO floodsafe_internal.schema_migrations(version,checksum) VALUES (%s,%s)",
                (path.stem, checksum),
            )
            applied.append(path.stem)
    return applied


def seed(connection):
    with connection.transaction():
        connection.execute((ROOT / "supabase" / "seed.sql").read_text(), prepare=False)


def main():
    parser = argparse.ArgumentParser(
        description="FloodSafe database management (credentials are never printed)"
    )
    parser.add_argument("command", choices=["check", "migrate", "seed"])
    args = parser.parse_args()
    settings = Settings()
    if args.command == "seed" and not settings.allow_demo_data:
        parser.error("Development seed requires FLOODSAFE_ALLOW_DEMO_DATA=true.")
    try:
        with psycopg.connect(**settings.connection_kwargs(), row_factory=dict_row) as connection:
            if args.command == "check":
                connection.execute("SELECT 1")
                print("Database connection succeeded. No schema changes made.")
            elif args.command == "migrate":
                versions = migrate(connection)
                print(f"Applied {len(versions)} migration(s).")
            else:
                seed(connection)
                print("Development scenarios seeded. Existing validity dates were preserved.")
    except (psycopg.Error, ValueError):
        # Connection exceptions can include connection details. Keep output safe.
        parser.exit(
            1,
            "Database operation failed. Check local configuration, project status, and migration prerequisites. Credentials were not printed.\n",
        )


if __name__ == "__main__":
    main()
