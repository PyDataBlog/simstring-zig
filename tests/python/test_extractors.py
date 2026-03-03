from simstring_zig import CharacterNgrams, WordNgrams


def test_character_ngrams_apply():
    features = CharacterNgrams(n=2, endmarker="$").apply("apple")
    assert features == ["$a1", "ap1", "pp1", "pl1", "le1", "e$1"]


def test_word_ngrams_apply():
    features = WordNgrams(n=2, splitter=" ", padder="#").apply("foo bar baz")
    assert features == ["# foo1", "foo bar1", "bar baz1", "baz #1"]
