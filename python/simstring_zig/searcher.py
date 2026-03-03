from . import _native
from .database import HashDb
from .measures import _Measure


class Searcher:
    def __init__(self, db: HashDb, measure: _Measure):
        self._db = db
        self._measure = measure

    def search(self, query: str, alpha: float) -> list[str]:
        return _native._search(self._db._require_handle(), self._measure._id, query, alpha)

    def ranked_search(self, query: str, alpha: float) -> list[tuple[str, float]]:
        raw = _native._ranked_search(self._db._require_handle(), self._measure._id, query, alpha)
        # Native JSON contains objects: {"text": ..., "score": ...}
        out = []
        for item in raw:
            if isinstance(item, dict):
                out.append((item["text"], float(item["score"])))
            else:
                out.append((item[0], float(item[1])))
        return out
