#!/usr/bin/env python3
"""Canonicalize mi_matrix corpus to idiomatic Zig.

Strips all `@`as(TYPE, EXPR) wrappers (balanced-paren aware, handles nesting).
Adds `const E = error{Bad};` where the file uses error-set type E
but doesn't declare it.

Idempotent: running twice produces no change.
"""

import re
import sys
import os


def find_top_level_comma(s: str) -> int:
    """Return index of first top-level comma in s, or -1.

    Tracks depth across () [] {}  — a comma at depth 0 is the one
    that separates TYPE from EXPR inside `@`as(TYPE, EXPR).
    """
    depth = 0
    for i, ch in enumerate(s):
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        elif ch == ',' and depth == 0:
            return i
    return -1


def strip_builtin(text: str, name: str) -> str:
    """Repeatedly strip `@name(TYPE, EXPR)` down to EXPR.

    Balanced-paren matching: walks from the '(' after @name to the
    matching ')', then splits the interior on the top-level comma and
    keeps only the second argument (trimmed).

    Loops until no `@`name(` remains to handle deeply-nested cases
    like  `@`as(E!i32, `@`as(i32, 42))  ->  42 .
    """
    prefix = '@' + name + '('
    plen = len(prefix)

    while prefix in text:
        out = []
        i = 0
        while i < len(text):
            if text[i:i + plen] == prefix:
                # position of the opening '('
                paren_pos = i + plen - 1
                depth = 1
                k = paren_pos + 1
                while k < len(text) and depth > 0:
                    ch = text[k]
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                    k += 1
                # interior is text[paren_pos+1 : k-1]
                interior = text[paren_pos + 1:k - 1]
                comma = find_top_level_comma(interior)
                if comma == -1:
                    # malformed — keep as-is
                    out.append(text[i:k])
                else:
                    out.append(interior[comma + 1:].strip())
                i = k
            else:
                out.append(text[i])
                i += 1
        text = ''.join(out)
    return text


def needs_error_set(text: str) -> bool:
    """True if text uses E but never declares it."""
    uses_e = bool(re.search(r'\bE!|\?E!|: E\b|error\.', text))
    has_decl = bool(re.search(r'const E |error\{|error \{', text))
    return uses_e and not has_decl


def canonicalize_one(filepath: str) -> bool:
    with open(filepath, 'r') as fh:
        original = fh.read().strip()

    text = strip_builtin(original, 'as')

    if needs_error_set(text):
        m = re.search(r'\b(pub fn |fn |const )', text)
        if m:
            text = text[:m.start()] + 'const E = error{Bad}; ' + text[m.start():]
        else:
            text = 'const E = error{Bad}; ' + text

    if text == original:
        return False

    with open(filepath, 'w') as fh:
        fh.write(text + '\n')
    return True


def main() -> None:
    changed = 0
    for fp in sys.argv[1:]:
        if not fp.endswith('.zig'):
            continue
        if canonicalize_one(fp):
            changed += 1
    print(f'Changed {changed} files')


if __name__ == '__main__':
    main()
