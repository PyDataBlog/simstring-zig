#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--iterations", type=int, default=50)
    parser.add_argument("--reserve", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]

    cmd = [
        "zig",
        "build",
        "bench",
        "-Doptimize=ReleaseFast",
        "--",
        "--dataset",
        args.dataset,
        "--seconds",
        str(args.seconds),
        "--iterations",
        str(args.iterations),
    ]
    if args.reserve:
        cmd.append("--reserve")

    proc = subprocess.run(cmd, cwd=repo, capture_output=True, text=True, check=True)
    data = json.loads(proc.stdout)
    print(json.dumps(data))


if __name__ == "__main__":
    main()
