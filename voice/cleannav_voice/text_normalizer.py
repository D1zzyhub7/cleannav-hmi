"""Conservative deterministic text normalization for V1 voice commands."""

from __future__ import annotations

import re
import unicodedata


_PUNCTUATION = re.compile(
    r'''[!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~，。！？；：、…“”‘’「」『』（）【】《》〈〉]'''
)
_WHITESPACE = re.compile(r'\s+')


class TextNormalizer:
    """Apply only normalization steps that preserve exact-match semantics."""

    def normalize(self, text: str) -> str:
        """Return a normalized phrase without semantic guessing."""
        if not isinstance(text, str):
            raise TypeError('text must be str')

        normalized = unicodedata.normalize('NFKC', text).strip().lower()
        normalized = _PUNCTUATION.sub('', normalized)
        return _WHITESPACE.sub(' ', normalized).strip()
