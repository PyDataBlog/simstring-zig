import ctypes
import json
import os
import platform
from pathlib import Path

from .errors import SearchError


_LIB = None


def _lib_name() -> str:
    system = platform.system().lower()
    if system == "windows":
        return "simstring_zig_native.dll"
    if system == "darwin":
        return "libsimstring_zig_native.dylib"
    return "libsimstring_zig_native.so"


def _candidate_paths() -> list[Path]:
    env = os.getenv("SIMSTRING_ZIG_LIB")
    if env:
        return [Path(env)]

    repo = Path(__file__).resolve().parents[2]
    return [
        repo / "zig-out" / "lib" / _lib_name(),
        Path(__file__).resolve().parent / _lib_name(),
    ]


def _load_lib():
    global _LIB
    if _LIB is not None:
        return _LIB

    errors: list[str] = []
    for path in _candidate_paths():
        if not path.exists():
            continue
        try:
            lib = ctypes.CDLL(str(path))
            _configure(lib)
            _LIB = lib
            return _LIB
        except OSError as exc:
            errors.append(f"{path}: {exc}")

    raise ImportError("Could not load simstring_zig native library. Build it with `zig build python-lib`.")


def _configure(lib):
    lib.sz_last_error.restype = ctypes.c_char_p

    lib.sz_free_cstring.argtypes = [ctypes.c_void_p]
    lib.sz_free_cstring.restype = None

    lib.sz_db_create_character.argtypes = [ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]
    lib.sz_db_create_character.restype = ctypes.c_void_p

    lib.sz_db_create_word.argtypes = [
        ctypes.c_size_t,
        ctypes.c_char_p,
        ctypes.c_size_t,
        ctypes.c_char_p,
        ctypes.c_size_t,
    ]
    lib.sz_db_create_word.restype = ctypes.c_void_p

    lib.sz_db_destroy.argtypes = [ctypes.c_void_p]
    lib.sz_db_destroy.restype = None

    lib.sz_db_insert.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    lib.sz_db_insert.restype = ctypes.c_bool

    lib.sz_db_clear.argtypes = [ctypes.c_void_p]
    lib.sz_db_clear.restype = ctypes.c_bool

    lib.sz_db_len.argtypes = [ctypes.c_void_p]
    lib.sz_db_len.restype = ctypes.c_size_t

    lib.sz_db_strings_json.argtypes = [ctypes.c_void_p]
    lib.sz_db_strings_json.restype = ctypes.c_void_p

    lib.sz_search_json.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_double]
    lib.sz_search_json.restype = ctypes.c_void_p

    lib.sz_ranked_search_json.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_double]
    lib.sz_ranked_search_json.restype = ctypes.c_void_p


def _last_error() -> str:
    lib = _load_lib()
    raw = lib.sz_last_error()
    if not raw:
        return "Unknown native error"
    return raw.decode("utf-8", errors="replace")


def _decode_json_ptr(ptr: int):
    if not ptr:
        raise SearchError(_last_error())

    lib = _load_lib()
    try:
        raw = ctypes.string_at(ptr)
        return json.loads(raw.decode("utf-8"))
    finally:
        lib.sz_free_cstring(ptr)


def _create_character_db(n: int, endmarker: str) -> int:
    lib = _load_lib()
    b = endmarker.encode("utf-8")
    handle = lib.sz_db_create_character(n, b, len(b))
    if not handle:
        raise SearchError(_last_error())
    return int(handle)


def _create_word_db(n: int, splitter: str, padder: str) -> int:
    lib = _load_lib()
    s = splitter.encode("utf-8")
    p = padder.encode("utf-8")
    handle = lib.sz_db_create_word(n, s, len(s), p, len(p))
    if not handle:
        raise SearchError(_last_error())
    return int(handle)


def _destroy_db(handle: int) -> None:
    lib = _load_lib()
    lib.sz_db_destroy(handle)


def _insert(handle: int, text: str) -> None:
    lib = _load_lib()
    b = text.encode("utf-8")
    ok = lib.sz_db_insert(handle, b, len(b))
    if not ok:
        raise SearchError(_last_error())


def _clear(handle: int) -> None:
    lib = _load_lib()
    ok = lib.sz_db_clear(handle)
    if not ok:
        raise SearchError(_last_error())


def _len(handle: int) -> int:
    lib = _load_lib()
    return int(lib.sz_db_len(handle))


def _strings(handle: int) -> list[str]:
    lib = _load_lib()
    return _decode_json_ptr(lib.sz_db_strings_json(handle))


def _search(handle: int, measure_id: int, query: str, alpha: float) -> list[str]:
    lib = _load_lib()
    q = query.encode("utf-8")
    return _decode_json_ptr(lib.sz_search_json(handle, measure_id, q, len(q), alpha))


def _ranked_search(handle: int, measure_id: int, query: str, alpha: float) -> list:
    lib = _load_lib()
    q = query.encode("utf-8")
    return _decode_json_ptr(lib.sz_ranked_search_json(handle, measure_id, q, len(q), alpha))
