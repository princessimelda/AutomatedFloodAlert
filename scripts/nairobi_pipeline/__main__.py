import argparse
import sys

from .data import Config
from .runner import evaluate_test, generate_schedule, run_pipeline


def main():
    parser = argparse.ArgumentParser(
        description="Explicit-source Nairobi station ETL and experimental models; not operational flood prediction."
    )
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run")
    for name in [
        "source_root",
        "notebook",
        "output_root",
        "calibration_end",
        "train_end",
        "validation_end",
    ]:
        run.add_argument("--" + name.replace("_", "-"), default=getattr(Config(), name))
    run.add_argument(
        "--mode",
        choices=["audit", "rainfall_proxy", "observed_labels"],
        default="rainfall_proxy",
    )
    run.add_argument("--labels")
    sub.add_parser(
        "prepare-runtime", help="Optional pinned OpenMP setup for an Intel Mac"
    )
    schedule = sub.add_parser("schedule-template")
    schedule.add_argument(
        "--destination",
        default="data/processed/nairobi_stations/org.floodsafe.station-pipeline.plist",
    )
    schedule.add_argument("--python", default=sys.executable)
    schedule.add_argument("--hour", type=int, default=7)
    schedule.add_argument("--minute", type=int, default=0)
    final = sub.add_parser("evaluate-test")
    final.add_argument("run_directory")
    args = vars(parser.parse_args())
    command = args.pop("command")
    if command == "run":
        print(run_pipeline(Config(**args)))
    elif command == "evaluate-test":
        print(evaluate_test(args["run_directory"]))
    elif command == "schedule-template":
        print(
            generate_schedule(
                args["destination"], args["python"], args["hour"], args["minute"]
            )
        )
    else:
        from .macos_runtime import prepare_macos_runtime

        print(prepare_macos_runtime(download=True))


if __name__ == "__main__":
    main()
