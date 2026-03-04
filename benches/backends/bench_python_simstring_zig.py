#!/usr/bin/env python3
import argparse
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path
from statistics import mean, stdev
from types import SimpleNamespace


def lib_name() -> str:
    system = platform.system().lower()
    if system == "windows":
        return "simstring_zig_native.dll"
    if system == "darwin":
        return "libsimstring_zig_native.dylib"
    return "libsimstring_zig_native.so"


def load_company_names(path: str) -> list[str]:
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def compute_stats(samples: list[float]) -> dict:
    if not samples:
        return {"mean": 0.0, "stddev": 0.0, "iterations": 0}
    return {
        "mean": mean(samples),
        "stddev": stdev(samples) if len(samples) > 1 else 0.0,
        "iterations": len(samples),
    }


def bench_insert(sim, companies, seconds, iterations, out):
    for ngram in [2, 3, 4]:
        samples = []
        suite_start = time.perf_counter()
        while len(samples) < iterations and (time.perf_counter() - suite_start) < seconds:
            db = sim.HashDb(sim.CharacterNgrams(n=ngram, endmarker=" "))
            start = time.perf_counter()
            for c in companies:
                db.insert(c)
            samples.append((time.perf_counter() - start) * 1000)

        out.append(
            {
                "language": "python",
                "backend": "simstring-zig (python bindings)",
                "benchmark": "insert",
                "parameters": {"ngram_size": ngram, "threshold": None},
                "stats": compute_stats(samples),
            }
        )


def bench_search(sim, companies, seconds, iterations, out):
    terms = companies[:100]

    for ngram in [2, 3, 4]:
        db = sim.HashDb(sim.CharacterNgrams(n=ngram, endmarker=" "))
        for c in companies:
            db.insert(c)
        searcher = sim.Searcher(db, sim.Cosine())

        for threshold in [0.6, 0.7, 0.8, 0.9]:
            samples = []
            suite_start = time.perf_counter()
            while len(samples) < iterations and (time.perf_counter() - suite_start) < seconds:
                start = time.perf_counter()
                for term in terms:
                    searcher.search(term, threshold)
                samples.append((time.perf_counter() - start) * 1000)

            out.append(
                {
                    "language": "python",
                    "backend": "simstring-zig (python bindings)",
                    "benchmark": "search",
                    "parameters": {"ngram_size": ngram, "threshold": threshold},
                    "stats": compute_stats(samples),
                }
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--iterations", type=int, default=50)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]

    subprocess.run(["zig", "build", "python-lib", "-Doptimize=ReleaseFast"], cwd=repo, check=True)

    env = os.environ.copy()
    env["SIMSTRING_ZIG_LIB"] = str((repo / "zig-out" / "lib" / lib_name()).resolve())
    env["PYTHONPATH"] = str((repo / "python").resolve()) + os.pathsep + env.get("PYTHONPATH", "")

    # Re-exec in a clean subprocess with updated env so imports use built native library.
    if os.getenv("_SIMSTRING_ZIG_BENCH_SUBPROC") != "1":
        new_env = env.copy()
        new_env["_SIMSTRING_ZIG_BENCH_SUBPROC"] = "1"
        proc = subprocess.run([sys.executable, __file__, *sys.argv[1:]], env=new_env, capture_output=True, text=True, check=True)
        print(proc.stdout.strip())
        return

    from simstring_zig import CharacterNgrams, Cosine, HashDb, Searcher  # type: ignore

    _api = SimpleNamespace(
        CharacterNgrams=CharacterNgrams,
        Cosine=Cosine,
        HashDb=HashDb,
        Searcher=Searcher,
    )

    companies = load_company_names(args.dataset)

    results = []
    bench_insert(_api, companies, args.seconds, args.iterations, results)
    bench_search(_api, companies, args.seconds, args.iterations, results)
    print(json.dumps(results))


if __name__ == "__main__":
    main()
