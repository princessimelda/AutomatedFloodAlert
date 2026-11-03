"""CLI: python -m scripts.openmeteo_pipeline --help."""

import argparse
import json
from dataclasses import fields

from .runner import evaluate_test, generate_schedule, run_pipeline
from .source import Config


def main():
    parser = argparse.ArgumentParser(
        description="Open-Meteo research ETL and rainfall-model comparison"
    )
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run")
    for field in fields(Config):
        kind = type(field.default) if field.default is not None else str
        run.add_argument(
            "--" + field.name.replace("_", "-"), default=field.default, type=kind
        )
    run.add_argument(
        "--refresh",
        action="store_true",
        help="Fetch new raw receipts, preserving previous evidence",
    )
    run.add_argument(
        "--quick",
        action="store_true",
        help="Small smoke-test models; not the full comparison",
    )
    test = commands.add_parser("evaluate-test")
    test.add_argument("run")
    schedule = commands.add_parser("schedule-template")
    schedule.add_argument("destination")
    schedule.add_argument("--hour", type=int, default=7)
    schedule.add_argument("--minute", type=int, default=0)
    refresh = commands.add_parser(
        "refresh-inputs",
        help="Fetch seven completed UTC days and prepare today's model inputs",
    )
    refresh.add_argument("--output-root", default="data/live/openmeteo")
    refresh.add_argument("--cache-root", default="data/raw/openmeteo_live")
    refresh.add_argument("--reference-run")
    commands.add_parser(
        "input-status", help="Read fresh inputs with expiry and integrity checks"
    )
    fresh_schedule = commands.add_parser("fresh-schedule-template")
    fresh_schedule.add_argument("destination")
    fresh_schedule.add_argument("--python-executable", default=None)
    fresh_schedule.add_argument("--interval", type=int, default=3600)
    fresh_schedule.add_argument("--reference-run")
    args = vars(parser.parse_args())
    command = args.pop("command")
    if command == "run":
        refresh, quick = args.pop("refresh"), args.pop("quick")
        print(run_pipeline(Config(**args), refresh=refresh, quick=quick))
    elif command == "evaluate-test":
        print(json.dumps(evaluate_test(args["run"]), indent=2))
    elif command == "schedule-template":
        print(generate_schedule(**args))
    else:
        from .fresh import generate_fresh_schedule, latest_inputs, refresh_inputs

        if command == "refresh-inputs":
            result = refresh_inputs(**args)
            print(json.dumps(result, indent=2))
            if result["status"] != "ready":
                raise SystemExit(2)
        elif command == "input-status":
            print(json.dumps(latest_inputs(), indent=2))
        else:
            if args["python_executable"] is None:
                args.pop("python_executable")
            print(generate_fresh_schedule(**args))


if __name__ == "__main__":
    main()
