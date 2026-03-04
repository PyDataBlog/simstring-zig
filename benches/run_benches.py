#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path

BACKENDS = {
    "zig-native": "bench_zig_native.py",
    "rust-native-ref": "bench_rust_native_ref.py",
    "python-simstring-rust": "bench_python_simstring_rust.py",
    "python-simstring-zig": "bench_python_simstring_zig.py",
}


def run_backend(backend_name: str, script: Path, dataset: str, seconds: float, iterations: int, reserve: bool) -> list[dict]:
    cmd = [
        sys.executable,
        str(script),
        "--dataset",
        dataset,
        "--seconds",
        str(seconds),
        "--iterations",
        str(iterations),
    ]
    if reserve and backend_name == "zig-native":
        cmd.append("--reserve")

    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"[WARN] backend '{backend_name}' failed:\n{proc.stderr.strip()}", file=sys.stderr)
        return []

    if not proc.stdout.strip():
        return []

    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        print(
            f"[WARN] backend '{backend_name}' returned invalid JSON: {e}\nstdout:\n{proc.stdout}",
            file=sys.stderr,
        )
        return []

    if not isinstance(data, list):
        print(f"[WARN] backend '{backend_name}' returned non-list JSON", file=sys.stderr)
        return []

    return data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", default="benches/data/company_names.txt")
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--iterations", type=int, default=50)
    parser.add_argument("--reserve", action="store_true", help="Enable reserve mode for zig-native backend")
    parser.add_argument(
        "--backends",
        nargs="*",
        default=list(BACKENDS.keys()),
        help=f"Backends to run. Available: {', '.join(BACKENDS.keys())}",
    )
    parser.add_argument("--skip-compare", action="store_true")
    args = parser.parse_args()

    benches_dir = Path(__file__).resolve().parent
    repo = benches_dir.parent
    dataset = str((repo / args.dataset).resolve())

    results: list[dict] = []

    for backend in args.backends:
        script_name = BACKENDS.get(backend)
        if script_name is None:
            print(f"[WARN] unknown backend '{backend}', skipping", file=sys.stderr)
            continue

        script_path = benches_dir / "backends" / script_name
        if not script_path.exists():
            print(f"[WARN] backend script missing: {script_path}", file=sys.stderr)
            continue

        backend_results = run_backend(
            backend,
            script_path,
            dataset,
            args.seconds,
            args.iterations,
            args.reserve,
        )
        results.extend(backend_results)

    results_path = benches_dir / "results.json"
    with open(results_path, "w") as f:
        json.dump(results, f, indent=2)

    if not args.skip_compare:
        subprocess.run([sys.executable, str(benches_dir / "compare_benches.py")], check=True)

    print(f"Wrote {len(results)} benchmark rows to {results_path}")


if __name__ == "__main__":
    main()
