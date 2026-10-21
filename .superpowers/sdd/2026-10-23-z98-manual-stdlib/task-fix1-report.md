# Task fix1 report — final-review accuracy nits

Scope: only the six findings in `brief-fix1.md`. Sources checked before wording.

## 1. z9torr resume mtime is the output file

Verified `examples/z98/z9torr/resume.zig:15-18,194-204`: `mtime(t.name)` stats the
resumed output/download file, not the source file.

- `sf/docs/std_lib/io.md` — `mtime` "When to use" now says output/download file.
- `docs/sf/manuals/en/vol5-09-files.html` — `mtime` paragraph now says
  output/download file.

## 2. LZ4 match length needs the +4 MINMATCH step

Verified `sf/src/std_lz4.zig:54-71`: low nibble is read, extended on 15, then
`match_len += MINMATCH` (4).

- `docs/sf/manuals/en/vol4-18-stdlib-codecs.html` — token text now states the low
  nibble encodes `match_len - 4` and the mandatory `+4` (`MINMATCH`) follows the
  extension.

## 3. Arena use beyond readAll

Verified `sf/src/std_file.zig:458-524`: `openDir` copies the POSIX path and
`readDir` copies entry names into the caller arena.

- `sf/docs/std_lib/io.md` — `File` gotcha now names `readAll`, `openDir`, and
  `readDir`, so it no longer contradicts the directory sections.

## 4. std_*.zig module count

Verified 39 `std_*.zig` files: 13 re-exported, 4 internal `*_pal`, leaving 22
public by-path modules (26 more files than the re-exported thirteen).

- `docs/sf/manuals/en/vol2-17-stdlib.html` — now says twenty-six more files, of
  which twenty-two are public by-path modules and four are internal `*_pal`
  support files.

## 5. Exact-multiple guarantee needs buffer length > 1

Verified `sf/src/std_stdin.zig:64-67,172` and `sf/src/std_stream.zig:97-111`:
carry behavior requires `n > 1` / `buf.len > 1`; `sf/docs/std_lib/io.md:1036`
records the caveat.

- `docs/sf/manuals/en/vol4-18-stdlib-io.html` — both the `std_stdin` section and
  the line-reader summary now add the buffer-length > 1 caveat and note the
  1-byte plain-boundary behavior.

## 6. JPS+ bitmap allocation is not freed

Verified `sf/src/std_pathfind.zig:519-548`: the `N`-byte bitmap is arena
allocated and stays until arena reset; only the returned `JpsPlus` omits it.

- `docs/sf/manuals/en/vol4-18-stdlib-algorithms.html` — now says the returned
  table does not retain the bitmap but its arena allocation remains until reset.

## Verification

- `bash docs/sf/manuals/build.sh` — pass; indexed 113 pages, copied 155 files.
- `bash docs/sf/manuals/check.sh` — pass; 116 HTML pages OK.
- `git diff --check 53dad106..HEAD` — pass, exit 0.

Only the six targeted source/manual files changed. `run.err` left untouched.
