from . import _native
from .extractors import CharacterNgrams, WordNgrams


class HashDb:
    def __init__(self, extractor: CharacterNgrams | WordNgrams):
        self._extractor = extractor
        self._handle: int | None = None

        if isinstance(extractor, CharacterNgrams):
            self._handle = _native._create_character_db(extractor.n, extractor.endmarker)
        elif isinstance(extractor, WordNgrams):
            self._handle = _native._create_word_db(extractor.n, extractor.splitter, extractor.padder)
        else:
            raise TypeError("Extractor must be CharacterNgrams or WordNgrams")

    def __del__(self):
        if getattr(self, "_handle", None):
            _native._destroy_db(self._handle)
            self._handle = None

    def insert(self, text: str) -> None:
        _native._insert(self._require_handle(), text)

    def clear(self) -> None:
        _native._clear(self._require_handle())

    def strings(self) -> list[str]:
        return _native._strings(self._require_handle())

    def __len__(self) -> int:
        return _native._len(self._require_handle())

    def _require_handle(self) -> int:
        if self._handle is None:
            raise RuntimeError("HashDb has been closed")
        return self._handle
