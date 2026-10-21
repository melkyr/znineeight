# Task T report — std/manual truth-ups

## vol2-17-stdlib.html

- Honest note now scopes the chapter to the whole `std` namespace, not the whole
  shipped library; removed the stale "no floating-point math beyond the printer"
  and "no hash map" claims (`std_map` noted as by-path).
- `std.math` prose and signature block now include f64 `sqrt`/`sin`/`cos`; states
  the integer helpers remain and no f32 surface exists. Domain/NaN notes added.
- "Beyond `std`" bridge table added after the re-export table with the four
  companion pages and their 22 modules (data, codecs, I/O, algorithms).
- Common-mistake wording now distinguishes the `std` namespace from by-path
  imports; "where to go next" links the companion pages.
- The 13-module `stdio.z98` example is unchanged and still touches all thirteen.

## sf/docs/std_lib/bits_math.md

- Removed the "no floating-point surface and no f64/f32 helpers" claim; layer
  and overview now say integer plus f64 scalar computation.
- Added concise `sqrt`, `sin`, `cos` API sections with exact signatures,
  behavior, domain/NaN notes, correctly-rounded/1-ULP facts, and no-f32 notes.
- Integer API left intact.

## sf/docs/std_lib/io.md

- Module overview now lists `mtime` and `openDir`/`readDir`/`closeDir`.
- `FileError` signature and error list updated to include `OpenDirFailed` and
  `ReadDirFailed` (noting `readDir` currently returns `null`/`OutOfMemory`).
- Added `DirEntry`, `Dir`, `openDir`, `readDir`, `closeDir`, and `mtime`
  sections from `sf/src/std_file.zig`: caller-arena names, no `.`/`..`
  filtering, `null` end, Linux `DT_UNKNOWN` fallback, Win9x Find* backend.
- `readAll` gotcha now says it holds the whole file and points large media at
  `open`/`read`/`seek` (z9play).

## vol5-09-files.html

- Added "Directory iteration, mtime, and bounded reads": exact signatures,
  caller-arena names, `.`/`..` not filtered, OS ordering, `DT_UNKNOWN` fallback,
  Win9x Find*, `null` end, `OpenDirFailed`.
- Added `mtime` and the z9torr resume use, plus the bounded-reading guidance
  against whole-file `readAll` for large media (z9play).

## Seed pages

- vol5-01: v91 → v111; 30 → 40 lib files in both places; all current fixed-point
  stamps → `21c957730d268f1e7883176fa5413b65`; meta keywords updated.
- vol5-22 and vol5-23: current fixed-point stamps updated to
  `21c957730d268f1e7883176fa5413b65`.
- Old stamps in `vol4-06`…`vol4-17` left untouched.

## Verification

- `bash docs/sf/manuals/build.sh` → `build.sh: indexed 113 pages, copied 155 files to /workspace/znineeight/docs/sf/manuals/dist`.
- `bash docs/sf/manuals/check.sh` → `check.py: OK - 116 HTML pages, links, rel, lang, forbidden list, figures, no-CSS baseline`.
- `git diff --check` → no output.
- Regenerated `docs/sf/manuals/en/search-data.js` included in the manual commit
  (build output; not hand-edited).

## Concerns

- None blocking. `readDir`'s `ReadDirFailed` is declared in the source error set
  but the current implementation never returns it; `io.md` states that rather
  than implying a live failure path.
