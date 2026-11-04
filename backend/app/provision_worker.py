"""Create a restricted worker login; keep the generated configuration private."""

import argparse
import json
import os
import secrets
from pathlib import Path

import psycopg
from psycopg import sql

from .config import Settings


def provision(settings, output):
    output = Path(output)
    if output.exists():
        raise ValueError(
            "Private worker configuration already exists; refusing to rotate it silently."
        )
    login = "floodsafe_ingestor"
    password = secrets.token_urlsafe(40)
    with psycopg.connect(**settings.connection_kwargs()) as connection:
        if connection.execute("SELECT 1 FROM pg_roles WHERE rolname=%s", (login,)).fetchone():
            raise ValueError(
                "Worker login already exists; recover its configuration instead of rotating it."
            )
        if not connection.execute(
            "SELECT to_regclass('floodsafe_pipeline.worker_runs')"
        ).fetchone()[0]:
            raise ValueError("Apply the weather-worker migration first.")
        connection.execute(
            sql.SQL("CREATE ROLE {} LOGIN NOINHERIT NOBYPASSRLS PASSWORD {}").format(
                sql.Identifier(login), sql.Literal(password)
            )
        )
        connection.execute(sql.SQL("GRANT floodsafe_worker TO {}").format(sql.Identifier(login)))
        # Session-pooler usernames have role.projectref form; direct connections
        # use just the role. Do not copy administrative privileges to the worker.
        suffix = settings.db_user.partition(".")[2]
        username = login + ("." + suffix if suffix else "")
        config = {
            "host": settings.db_host,
            "port": settings.db_port,
            "dbname": settings.db_name,
            "user": username,
            "password": password,
            "sslmode": settings.db_sslmode,
        }
        descriptor = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            handle.write(json.dumps(config, indent=2) + "\n")
    return output


def main():
    parser = argparse.ArgumentParser(
        description="Provision the limited PostgreSQL weather-worker login"
    )
    parser.add_argument(
        "--output", default=str(Path(__file__).resolve().parents[2] / ".env.worker")
    )
    args = parser.parse_args()
    try:
        path = provision(Settings(), args.output)
        print(f"Restricted worker login provisioned; private configuration saved to {path}.")
    except (ValueError, OSError, psycopg.Error):
        parser.exit(
            1,
            "Worker provisioning failed. No credentials were printed; inspect project state before retrying.\n",
        )


if __name__ == "__main__":
    main()
