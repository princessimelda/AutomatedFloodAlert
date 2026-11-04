import argparse
import json

import psycopg

from .bundle import DEFAULT_BUNDLE, load_bundle
from .store import PostgresStore, db_config
from .worker import run_worker


def main():
    parser = argparse.ArgumentParser(
        description="Experimental GFS rainfall worker with PostgreSQL persistence"
    )
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run")
    run.add_argument("--db-config-file")
    run.add_argument("--bundle", default=str(DEFAULT_BUNDLE))
    export = commands.add_parser("export-bundle")
    export.add_argument("source")
    export.add_argument("destination")
    args = parser.parse_args()
    if args.command == "export-bundle":
        from .export import export_bundle

        print(export_bundle(args.source, args.destination)["manifest"]["model_version"])
        return
    try:
        bundle = load_bundle(args.bundle)
        with psycopg.connect(**db_config(args.db_config_file)) as connection:
            result = run_worker(bundle, PostgresStore(connection))
        print(json.dumps(result))
        if result["status"] not in {"ready", "already_complete", "busy"}:
            raise SystemExit(2)
    except Exception as error:  # noqa: BLE001 -- CLI boundary must not print credentials from exception messages.
        # Database/provider exception text may contain endpoints/configuration.
        print(json.dumps({"status": "failed", "error_code": type(error).__name__}))
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
