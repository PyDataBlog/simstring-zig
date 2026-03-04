import os
import platform
from pathlib import Path


def _lib_name() -> str:
    system = platform.system().lower()
    if system == "windows":
        return "simstring_zig_native.dll"
    if system == "darwin":
        return "libsimstring_zig_native.dylib"
    return "libsimstring_zig_native.so"


def pytest_configure(config):
    repo = Path(__file__).resolve().parents[2]
    default_lib = repo / "zig-out" / "lib" / _lib_name()
    if "SIMSTRING_ZIG_LIB" not in os.environ and default_lib.exists():
        os.environ["SIMSTRING_ZIG_LIB"] = str(default_lib)

    py_path = str(repo / "python")
    existing = os.environ.get("PYTHONPATH", "")
    os.environ["PYTHONPATH"] = py_path if not existing else py_path + os.pathsep + existing
