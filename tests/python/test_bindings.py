from simstring_zig import (
    CharacterNgrams,
    Cosine,
    Dice,
    HashDb,
    SearchError,
    Searcher,
    WordNgrams,
)


def test_db_insert_and_len():
    db = HashDb(CharacterNgrams(n=2, endmarker="$"))
    assert len(db) == 0
    db.insert("apple")
    db.insert("apply")
    assert len(db) == 2
    assert db.strings() == ["apple", "apply"]


def test_search_and_ranked_search():
    db = HashDb(CharacterNgrams(n=2, endmarker="$"))
    db.insert("apple")
    db.insert("apply")
    db.insert("banana")

    searcher = Searcher(db, Cosine())
    assert searcher.search("apple", 0.8) == ["apple"]

    ranked = searcher.ranked_search("apple", 0.6)
    assert ranked[0][0] == "apple"
    assert ranked[1][0] == "apply"


def test_search_error_on_invalid_threshold():
    db = HashDb(CharacterNgrams(n=2, endmarker="$"))
    db.insert("apple")
    searcher = Searcher(db, Dice())

    try:
        searcher.search("apple", 1.1)
        raise AssertionError("Expected SearchError")
    except SearchError:
        pass


def test_word_ngrams_path():
    db = HashDb(WordNgrams(n=2, splitter=" ", padder="#"))
    db.insert("foo bar")
    assert Searcher(db, Cosine()).search("foo bar", 1.0) == ["foo bar"]
