"""Source-span helpers for the two standard-library GDScript literal checks.

This is not a parser: gdparse still owns syntax validation. The checks need the
original line and column for a match, but should never match examples in comments,
quoted strings, StringNames, NodePaths or multiline string literals.
"""

from __future__ import annotations

import re
from collections.abc import Iterator

# Order matters: a triple quote is not a pair of empty, single-line strings.
# A backslash can escape the delimiter itself or continue a quoted line.
_NON_CODE = re.compile(
    r'''\# [^\r\n]*
      | """ (?: \\[\s\S] | (?!""") [^\\] )* """
      | \'\'\' (?: \\[\s\S] | (?!\'\'\') [^\\] )* \'\'\'
      | " (?: \\[\s\S] | [^"\\\r\n] )* "
      | ' (?: \\[\s\S] | [^'\\\r\n] )* '
    ''',
    re.VERBOSE,
)
_NON_NEWLINE = re.compile(r"[^\r\n]")
_DIGITS = r"[0-9](?:_?[0-9])*"
DECIMAL = (
    rf"[+-]?(?:{_DIGITS}(?:\.(?:{_DIGITS})?)?|\.{_DIGITS})"
    rf"(?:[eE][+-]?{_DIGITS})?"
)


def mask_non_code(source: str) -> str:
    """Mask non-code spans without changing line boundaries or offsets.

    Comment text becomes space. Strings stay opaque (not whitespace), so a
    quoted argument cannot be mistaken for a trailing comma and no argument.
    Escaped quotes and '#' inside a literal stay part of that literal; a comment
    can contain arbitrary quotes without masking the next line.
    """
    return _NON_CODE.sub(
        lambda match: _NON_NEWLINE.sub(" " if match[0].startswith("#") else "\0", match[0]),
        source,
    )


def numbered_matches(pattern: re.Pattern[str], source: str) -> Iterator[tuple[int, re.Match[str]]]:
    """Yield (line, match) in source order, including multiple matches on one line."""
    line = 1
    previous = 0
    for match in pattern.finditer(source):
        line += source.count("\n", previous, match.start())
        previous = match.start()
        yield line, match
