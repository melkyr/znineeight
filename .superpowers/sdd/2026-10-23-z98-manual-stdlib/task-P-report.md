# Task P report — companion stdlib reference pages

## Page 1 — Data and containers

Created `docs/sf/manuals/en/vol4-18-stdlib-data.html`.

- Modules covered: `std_map`, `std_sort`, `std_heap`, `std_rle`, `std_parse`, `std_bencode`.
- Signatures, error sets, ownership, and behavior checked against `sf/src/std_*.zig`.
- Temporary nav: prev `vol4-18-stdlib.html`, next `vol4-18-stdlib-codecs.html`.
- Structural check passed: ISO-8859-1, `lang="en"`, `rel` home/up/prev/next, one `h1`, no forbidden tags, no external links. Unresolved links are only the not-yet-created companion pages.
- Source discrepancies noted:
  - `std_hex` has no encoded/decoded length helper despite the brief wording; handled on the codecs page.
  - `std_file.readDir` does not filter `.`/`..` in source; handled on the I/O page.

## Page 2 — Codecs and crypto

Created `docs/sf/manuals/en/vol4-18-stdlib-codecs.html`.

- Modules covered: `std_base64`, `std_hex`, `std_utf8`, `std_crypto`, `std_lz4`, `std_zstd`.
- Signatures, error sets, ownership, and behavior checked against `sf/src/std_*.zig`; stale `bits_math.md` and `io.md` claims were not used.
- Temporary nav: prev data, next I/O.
- Structural check passed: ISO-8859-1, `lang="en"`, `rel` home/up/prev/next, one `h1`, no forbidden tags, no external links. Unresolved links are only the not-yet-created companion pages.
- Brief/source mismatch recorded: `std_hex` has no encoded/decoded length helpers; the page states the source's `src.len * 2` / `src.len / 2` sizing instead of inventing functions.

## Page 3 — I/O and HTTP

Created `docs/sf/manuals/en/vol4-18-stdlib-io.html`.

- Modules covered: `std_file`, `std_stdin`, `std_stream`, `std_http`.
- Signatures, error sets, ownership, and behavior checked against `sf/src/std_*.zig`; stale `io.md` claims were not used.
- Temporary nav: prev codecs, next algorithms.
- Structural check passed: ISO-8859-1, `lang="en"`, `rel` home/up/prev/next, one `h1`, no forbidden tags, no external links. Unresolved links are only the not-yet-created algorithms page.
- Brief/source mismatch recorded and resolved in source's favor: `std_file.readDir` does not filter `.`/`..` (source comments and body both return them). The page states that callers must skip them, instead of repeating the brief's claim that they are omitted.

## Page 4 — Algorithms

Created `docs/sf/manuals/en/vol4-18-stdlib-algorithms.html`.

- Modules covered: `std_rand`, `std_noise`, `std_num`, `std_pathfind`, `std_physics`, `std_hpa`.
- Signatures, error sets, ownership, and behavior checked against `sf/src/std_*.zig`; `std_rand` and `std_noise` were checked independently of each other.
- Temporary nav: prev I/O, next `vol4-19-pal.html`.
- Structural check passed: ISO-8859-1, `lang="en"`, `rel` home/up/prev/next, one `h1`, no forbidden tags, no external links, all local links resolve.

## Verification

- `bash docs/sf/manuals/check.sh` &rarr; `check.py: OK - 116 HTML pages, links, rel, lang, forbidden list, figures, no-CSS baseline`.
- `bash /tmp/taskP-manual/build.sh` in a throwaway copy &rarr; `build.sh: indexed 113 pages, copied 155 files`; all four new pages appear in the generated search index.
- Signature audit: all 123 `pub fn` signatures in the 22 covered `sf/src/std_*.zig` files appear verbatim in the corresponding page text.
- Worktree check: only the four new page files were added; no existing file was modified. `run.err` remains untracked and uncommitted.

## Concerns

1. The brief says directory iteration returns names without `.` and `..`; `sf/src/std_file.zig` explicitly says the opposite (`. ` and `..` are returned, not filtered). The page follows the source.
2. The brief asks for encoded/decoded length helpers for hex; `sf/src/std_hex.zig` has none. The page documents the source's direct `src.len * 2` / `src.len / 2` sizing.


