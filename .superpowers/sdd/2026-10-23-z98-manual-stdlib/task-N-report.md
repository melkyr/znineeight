# Task N report — Volume IV navigation and ch.18 truth-ups

## vol4-18-stdlib.html

- Scope paragraph now points at the by-path index and the four companion pages.
- Sidebar lists the parent plus the four companion pages, parent bold.
- `std.math` prose replaced; added `sqrt`, `sin`, and `cos` rows; no `f32` surface stated.
- `std.async` `contextInit` row corrected: 8-alignment trap in both modes,
  `buf.len >= 16` caller precondition, subtraction traps only under `-fsafe`.
- "Modules shipped but not re-exported" replaced with a by-path index table and
  the `*_pal` internal-implementation note.
- `rel="next"` and footer next point at `vol4-18-stdlib-data.html`.

## Companion chain and contents

- `vol4-19-pal.html`: `rel="prev"` and footer previous point at
  `vol4-18-stdlib-algorithms.html`.
- `toc.html`: four companion entries added immediately after "The standard library".
- `vol4-00-title.html`: four companion entries added to the Volume IV chapter list
  and to the sidebar.

## Volume IV sidebars

- `vol4-00..24` (except `vol4-16-async.html`, a coroutine page the brief says not
  to touch) and the four companions now list:
  "The standard library", "Data and containers", "Codecs and crypto",
  "I/O and HTTP", and "Algorithms".
- Current page stays bold (`<b>…</b><br>`), all other entries are links, matching
  the existing convention.

## Commits

- `85418218 docs(manual): link by-path stdlib reference pages`

## Verification

- `bash docs/sf/manuals/build.sh` &rarr; `build.sh: indexed 113 pages, copied 155 files`.
- `bash docs/sf/manuals/check.sh` &rarr; `check.py: OK - 116 HTML pages, links, rel, lang, forbidden list, figures, no-CSS baseline`.
- `git diff --check` &rarr; no output.

## Concerns

- `vol4-16-async.html` was intentionally left untouched per the coroutine-page
  exclusion, so its sidebar still has the single standard-library link while the
  other Volume IV pages have the five-entry block.
