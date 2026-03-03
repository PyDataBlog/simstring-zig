#!/usr/bin/env python3
import argparse
import json
import time
from pathlib import Path
from statistics import mean, stdev


def maybe_import():
    try:
        from simstring_rust.database import HashDb
        from simstring_rust.extractors import CharacterNgrams
        from simstring_rust.measures import Cosine
        from simstring_rust.searcher import Searcher
    except Exception:
        return None
    return HashDb, CharacterNgrams, Cosine, Searcher


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


def bench_insert(HashDb, CharacterNgrams, companies, seconds, iterations, out):
    for ngram in [2, 3, 4]:
        samples = []
        suite_start = time.perf_counter()
        while len(samples) < iterations and (time.perf_counter() - suite_start) < seconds:
            extractor = CharacterNgrams(n=ngram, endmarker=" ")
            db = HashDb(extractor)
            start = time.perf_counter()
            for c in companies:
                db.insert(c)
            samples.append((time.perf_counter() - start) * 1000)

        out.append(
            {
                "language": "python",
                "backend": "simstring-rust (python bindings)",
                "benchmark": "insert",
                "parameters": {"ngram_size": ngram, "threshold": None},
                "stats": compute_stats(samples),
            }
        )


def bench_search(HashDb, CharacterNgrams, Cosine, Searcher, companies, seconds, iterations, out):
    terms = companies[:100]

    for ngram in [2, 3, 4]:
        extractor = CharacterNgrams(n=ngram, endmarker=" ")
        db = HashDb(extractor)
        for c in companies:
            db.insert(c)
        searcher = Searcher(db, Cosine())

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
                    "backend": "simstring-rust (python bindings)",
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

    imported = maybe_import()
    if imported is None:
        print("[]")
        return

    HashDb, CharacterNgrams, Cosine, Searcher = imported
    companies = load_company_names(args.dataset)

    results = []
    bench_insert(HashDb, CharacterNgrams, companies, args.seconds, args.iterations, results)
    bench_search(HashDb, CharacterNgrams, Cosine, Searcher, companies, args.seconds, args.iterations, results)
    print(json.dumps(results))


if __name__ == "__main__":
    main()
