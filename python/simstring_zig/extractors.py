from collections import Counter


class CharacterNgrams:
    def __init__(self, n: int = 2, endmarker: str = "$"):
        self.n = n
        self.endmarker = endmarker

    def apply(self, text: str) -> list[str]:
        if self.n <= 0:
            return []
        padding = self.endmarker * max(self.n - 1, 0)
        chars = list(padding + text + padding)
        if len(chars) < self.n:
            return []

        counter: Counter[str] = Counter()
        out: list[str] = []
        for i in range(len(chars) - self.n + 1):
            ngram = "".join(chars[i : i + self.n])
            counter[ngram] += 1
            out.append(f"{ngram}{counter[ngram]}")
        return out


class WordNgrams:
    def __init__(self, n: int = 2, splitter: str = " ", padder: str = " "):
        self.n = n
        self.splitter = splitter
        self.padder = padder

    def apply(self, text: str) -> list[str]:
        if self.n <= 0:
            return []

        tokens = [tok for tok in text.split(self.splitter) if tok] if self.splitter else list(text)
        padded = [self.padder, *tokens, self.padder]
        if len(padded) < self.n:
            return []

        counter: Counter[str] = Counter()
        out: list[str] = []
        for i in range(len(padded) - self.n + 1):
            ngram = " ".join(padded[i : i + self.n])
            counter[ngram] += 1
            out.append(f"{ngram}{counter[ngram]}")
        return out
