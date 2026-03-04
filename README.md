# simstring-zig

High-performance SimString implementation in Zig with native benchmarking and Python bindings.

## Build and Test

```bash
zig build test -Doptimize=ReleaseFast
zig build run -Doptimize=ReleaseFast
```

## Native Benchmark

Run the Zig benchmark executable directly:

```bash
zig build bench -Doptimize=ReleaseFast -- --seconds 1 --iterations 5
```

## Benchmark Harness

```bash
python benches/run_benches.py --seconds 1 --iterations 5 --backends zig-native python-simstring-zig
```

Outputs:

- `benches/results.json` - merged raw rows
- `BENCHMARKS.md` - generated benchmark report

## Python Frontend

Build the native shared library:

```bash
zig build python-lib -Doptimize=ReleaseFast
```

Use bindings directly from repo:

```bash
export SIMSTRING_ZIG_LIB="$(pwd)/zig-out/lib/libsimstring_zig_native.so"
export PYTHONPATH="$(pwd)/python:${PYTHONPATH}"
python - <<'PY'
from simstring_zig import HashDb, CharacterNgrams, Searcher, Cosine

db = HashDb(CharacterNgrams(n=2, endmarker="$"))
db.insert("apple")
db.insert("apply")
print(Searcher(db, Cosine()).search("apple", 0.6))
PY
```
