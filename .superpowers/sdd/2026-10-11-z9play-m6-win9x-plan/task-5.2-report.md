# M6 Task T5.2 report — compiler plumbing: `-osw [9x|nt]` + profile emission + `--help`

**Status:** DONE_WITH_CONCERNS (all substantive gates green; concerns in §5 are stale
brief anchors and the `--help` parse addition).

**Scope:** `sf/src/main.zig`, `sf/src/c89_emit.zig`, tech docs covering them
(`08_c89_emission.md`, `09_pipeline_orchestration.md`, `INDEX.md`), this report.
No other source file changed. `run.err`/`run.out`/`progress.md` untouched. No push,
no seed rotation.

**Authority:** `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`
`### Amendment 2` → `#### Task T5.2` (operator-locked 2026-10-18), brief
`.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-5.2-brief.md`, inventory
T5.1 report §8–§9.

**Base:** `git rev-parse HEAD` → `87ac1964` (`docs(sdd): T5.1 complete — ledger`).
`git status --short` before work: only untracked `run.err`.

---

## 1. Investigate — current parsing/emission map

- `CompilerCli` (`sf/src/main.zig:68-95`, 26 fields before this task) had only
  `target_is_windows: bool`; no Windows profile field.
- `parseArgs` (`main.zig:1664-1824`) recognized `-osl`/`-osw` at `:1800-1803` and
  `--target` at `:1804-1808`. `-osw` set only `target_is_windows = true`;
  `--target windows` set only the same bool. No token was consumed after `-osw`.
- `phase_C89Emission` passed only `ctx.cli.target_is_windows` to
  `c89_mod.emitBuildScripts` (`main.zig:1645`).
- `emitBuildScripts` (`c89_emit.zig:8626`, before edit) wrote `build_target.sh`
  always and `.bat`/`build_owc.bat` only for Windows, forwarding only
  `net_emitted` to `emitBuildTargetSh`/`Bat`/`OwcBat` (`:8532-8624`). No profile
  define existed.
- `printUsage` (`main.zig:2015-2030`) documented only `-mm<N>`, `-s<N>`,
  `-osl`/`-osw`, `--target`. T5.1 §6 verified 21 parsed groups / 26 spellings
  were undocumented and `--dump-types`/`--dump-lir` (plus `-t`/`-a`/`-y`/`-l`)
  are dead constants never matched.
- There was no `--help` parse branch; only the no-input path called
  `printUsage()`. The T5.2 gate item "`--help` shows the documented set" therefore
  required adding the parse branch as part of the CLI truth-up (see §5 C2).

## 2. Implement — per-file edits

### `sf/src/c89_emit.zig`

- Added `pub const WinProfile = enum(u8) { win9x, nt };` (public type, no cycle:
  `main.zig` already imports `c89_emit.zig`).
- `emitBuildTargetSh` now takes `win_profile`. `.win9x` writes the exact original
  mingw `CFLAGS` string; `.nt` writes the same string with `-DZIG_WIN_NT` before
  `-I .`. Linux branch untouched.
- `emitBuildTargetBat` now takes `win_profile`. `.win9x` writes the exact
  original `set CFLAGS=...`; `.nt` adds `/DZIG_WIN_NT` before `/I .`.
- `emitBuildOwcBat` now takes `win_profile`. `.win9x` uses the exact original
  `wcc386 ... /i=. ` prefix for the module loop and all three runtime sources;
  `.nt` adds `/dZIG_WIN_NT` to every `wcc386` command.
- `emitBuildScripts` now takes `win_profile` and forwards it to all three
  writers. No no-CRT/`-nostdlib`/library changes (T5.3 owns them).

### `sf/src/main.zig`

- `CompilerCli` gained `target_win_profile: c89_mod.WinProfile`, default
  `.win9x`.
- `parseArgs`:
  - `-osw` sets Windows + profile `.win9x`, then consumes the next token only
    when it is a non-`-` token exactly equal to `9x` or `nt`.
  - `-osw <anything-else>` still leaves the token as the input file;
    `-osw app.zig` and `-osw nt app.zig` both work.
  - `--target windows` resets the profile to `.win9x` (bare-`-osw` semantics);
    `--target linux`, `-osl`, and last-target-flag-wins behavior are unchanged.
  - Added `--help`: prints the documented usage and exits 0.
- `phase_C89Emission` forwards `ctx.cli.target_win_profile` to
  `emitBuildScripts`.
- `printUsage` truth-up: documents every actively parsed option
  (`--help`, `--dump-c89`, `-mm`, `-s`, `-osl`, `-osw [9x|nt]`, `--target`,
  `-o/--output-dir`, `-m/--max-mem`, `-e/--max-errors`, `-q/--quiet`,
  `--test`, `--sanity-test`, `-W/--warnings-as-errors`, `--warn-error`,
  `--warn-all`, `--color`, `--error-format`, `--track-memory`, the three
  `--no-*-check` flags, `--markers`, `-I/--lib-dir`, `-fsafe`, `-ffast`) and the
  9x default / `nt` opt-in. Dead constants (`--dump-types`, `--dump-lir`, `-t`,
  `-a`, `-y`, `-l`) are not listed.

### Tech docs

- `09_pipeline_orchestration.md`: `CompilerCli` 26→27 fields; new field row and
  profile semantics paragraph; parse-flow diagram includes `--help` and
  `-osw` profile-token consumption; `--target` note; `printUsage` section;
  data-flow count/allocation table.
- `08_c89_emission.md` §6.1: profile plumbing and the three defines; explicit
  note that T5.2 adds no no-CRT/link changes.
- `INDEX.md`: `CompilerCli` 27 fields and new `WinProfile` row.
- Changed sections stamped `[updated: 2026-10-18 — M6 T5.2 …]`.

## 3. Build under test (seed model)

```sh
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t52
[seed] hop1 binary md5: 983ff15c251ae37a1a6c7b7fe8b7212f
[seed] hop2 binary md5: 3a4454ea7dd1a92ebe6e313248ea96f8
[seed] hop3 binary md5: 3a4454ea7dd1a92ebe6e313248ea96f8
[seed] three-hop closure OK (moving point): hop2 == hop3 == 3a4454ea7dd1a92ebe6e313248ea96f8
=== [seed] Done: /tmp/t52 ===
```

Fixed point recorded old→new: hop1 `983ff15c…`, closure `3a4454ea…` (hop2 ==
hop3). No seed rotation.

## 4. Runtime battery (sequential; no parallel zig1 runs)

### 4.1 Corpus

```sh
$ bash scripts/corpus/classify /tmp/t52/zig1_5_clean /tmp/t52_corpus.txt
wrote /tmp/t52_corpus.txt: 1133 dirs
$ md5sum /tmp/t52_corpus.txt
f333dbb454119e47fe70160d27512216  /tmp/t52_corpus.txt
$ awk '{print $2}' /tmp/t52_corpus.txt | sort | uniq -c
    116 FAIL
     58 GREEN
    959 OK
```

Tree now contains the 9 designed D1/D2 fixtures added after the frozen-1124
snapshot. Removing exactly those 9 lines (the designed set recorded in
`.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-4-report.md` §2):

```sh
$ grep -vE 'repro/mi_matrix/(fnptr_opt_aggregate_(coerce|emit)_xmod|iswindows_deadarm_(errunion|prune|cond_if)_xmod|conditional_import_(if|switch|lazy)_xmod|comptime_if_noelse_deadarm_xmod) ' /tmp/t52_corpus.txt > /tmp/t52_corpus_frozen1124.txt
$ wc -l /tmp/t52_corpus_frozen1124.txt
1124 /tmp/t52_corpus_frozen1124.txt
$ md5sum /tmp/t52_corpus_frozen1124.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/t52_corpus_frozen1124.txt
$ awk '{print $2}' /tmp/t52_corpus_frozen1124.txt | sort | uniq -c
    116 FAIL
     58 GREEN
    950 OK
```

Frozen 1124 subset: **md5 `518eca1a9b5d3e1cc5a48abce214abd8`,
`1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`, 0 movers**. The 9
designed lines are all `OK`.

### 4.2 Goldens 5/5

Recipe per QUICK_REF: `zig1 -ffast --dump-c89 --output-dir <dir> <ENTRY>`,
`sh build_target.sh linux prog`, run with CWD = example dir.

```text
gol (100 gens, </dev/null)   rc=0  fcbf7e7cead5082f0a8caadd5a8f0ff9  MATCH
lisp `(+ 1 2)`               rc=0  b3d9f8974da24ddbf9d389f3d7d97322  MATCH
json_parser                  rc=0  8bda3d5a1ec07d14a301bc343df32bf8  MATCH
mud server                   rc=0  66c8f0abb926cca7baf9a0d1692ab318  MATCH
mud client                   (same session) 93147d0f0bbd983a9d844fea8b7a6fa7  MATCH
```

**5/5 MATCH.**

### 4.3 mi_matrix frozen 25 + oob

```sh
$ bash scripts/stdlib/run_fixtures.sh /tmp/t52/zig1_5_clean repro/mi_matrix/<each of the 25>
PASS repro/mi_matrix/<name>        (each)
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
MI_TALLY pass=25 fail=0
```

OOB manual `-fsafe` recipe:

```text
DUMP_RC=0  BUILD_RC=0  RUN_RC=133  STDOUT_BYTES=0
stderr: timeout: the monitored command dumped core
```

**25 PASS / 0 FAIL + oob rc 133 / empty stdout — MATCH.**

### 4.4 Examples 26/26 build + 26/26 run

Build: `zig1 -ffast --dump-c89 --output-dir <out> <entry>` + `sh
build_target.sh linux prog` (entry = `main.zig` or `<dir>.zig`).
**BUILD_TALLY ok=26 fail=0** (after correcting the 4 dirs whose entry is
`<dir>.zig`: func_ptr_return, mandelbrot, quicksort, sort_strings).

Run (CWD = each example dir; timeout 25, mud 8, rogue* `q\n`, stdin
`/dev/null`):

```text
days_in_month 8c0d394c  fibonacci b53b3a3d  func_ptr_return f6a54779
game_of_life fcbf7e7c  heapsort 8cf0a784  hello 74630882
json_parser 8bda3d5a  json_parser_upgraded 8bda3d5a  json_parser_workaround dc22fa47
lisp_interpreter* 1c1f0a41 (x4)  lzw c3c7765e  mandelbrot d5966775
mud_server rc=124 9545fe1d  prime d095a94d  quicksort 45d2f0fb
rogue_mud* 3fb6709e (x2)  sort_strings c6c047cb
tco_defer 264ea6b1  tco_factorial 3d70c50b  tco_return_try 7421137a
z9play rc=1 f35b7ef7  z9torr rc=1 f666af15
```

**26/26 build, 26/26 run — all md5 prefixes match the frozen prior-milestone
table.**

### 4.5 Stdlib

```sh
$ bash scripts/stdlib/verify_stdlib.sh /tmp/t52/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

**285/0 MATCH.**

### 4.6 Pins 8/8 (`--dump-c89` md5, repo root)

| Entry | `-fsafe` old→new | `-ffast` old→new |
|:--|:--|:--|
| mud_server | `48f188df6b5f09cb1614c532ae7e825a` → same | `243369f4a942ad27f75b3c391581bd29` → same |
| game_of_life | `93c5e3fdc5b80b2f3db020d995abbe3f` → same | `01a4e2265b33c97a8ca6ff3dfa551231` → same |
| lisp_interpreter_curr | `6da05d070acd414674b1b1ec947baa5c` → same | `e3970e33ac09c8dfaa316d2d69bf61ec` → same |
| json_parser | `af3823fae0b29fa4d4ca58932538d631` → same | `24e0e812e7dffa5a43750135405ffe3f` → same |

**0/8 movers.**

### 4.7 Markers telemetry

```sh
$ /tmp/t52/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > /tmp/t52_mk.c 2> /tmp/t52_mk.bin
$ wc -l -c /tmp/t52_mk.bin
3436 38371 /tmp/t52_mk.bin
```

Top prefixes: `2005 INT` / `422 DC` / `310 FE` / `195 P0` / `195 FWD` /
`122 RaD12` / `86 MT` / `51 IRP`. Current prior-milestone baseline is
3436 lines / 38371 B (T3 T5.2 brief anchor 3437/38384 is stale; see §5 C1).

### 4.8 `check_emit_support.sh`

```sh
$ bash scripts/check_emit_support.sh /tmp/t52/zig1_5_clean
[check] emitted zig_compat.h == .../zig_compat.h
[check] emitted zig_runtime.h == .../zig_runtime.h
[check] emitted zig_runtime.c == .../zig_runtime.c
[check] emitted zig_pal.c == .../zig_pal.c
[check] emitted c_exit.c == .../c_exit.c
[check] net_prelude.h correctly absent (std_net not reachable)
[check] std_os_prelude.h correctly absent (std_os not used)
[check] emitted std_os_prelude.h == .../std_os_prelude.h
[check] std_time_prelude.h correctly absent (std_time not used)
[check] emitted std_time_prelude.h == .../std_time_prelude.h
[check] OK: 7/7 support files byte-identical to canonical (5 core + 2 conditional preludes)
```

**7/7 identical.**

### 4.9 CLI smoke

```text
-osw --dump-c89 (z9play)          rc=0  ZIG_WIN_NT in sh=0 bat=0 owc=0
-osw 9x --dump-c89                rc=0  sh=0 bat=0 owc=0; build scripts cmp-identical to bare -osw
--target windows --dump-c89       rc=0  sh=0 bat=0 owc=0; cmp-identical to bare -osw
-osl --dump-c89                   rc=0  no bat/owc
-osw nt --dump-c89                rc=0  sh=1 bat=1 owc=32 (all wcc386 lines)
-osw examples/z98/hello/main.zig -o <dir>        rc=0  (token not consumed; unchanged)
-osw nt examples/z98/hello/main.zig -o <dir>     rc=0  (nt consumed; input parsed)
-osw nt --target windows          rc=0  sh define=0  (last target flag wins)
--target windows -osw nt          rc=0  sh define=1
--help                            rc=0  stdout 0 B; stderr 1737 B, all documented flags + 9x default
```

`nt` sh CFLAGS observed:
`... -Wno-implicit-function-declaration -DZIG_WIN_NT -I .`
`nt` bat: `set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /DZIG_WIN_NT /I .`
`nt` owc: `wcc386 /za /we /dZIG_WIN32 /dZIG_WIN_NT /i=. <file>.c`

### 4.10 No seed rotation

`release/seed/zig1-seed.tgz` untouched; no archive/QUICK_REF/CHANGELOG seed
changes. `git status` showed only the five intended files plus untracked
`run.err`.

## 5. Concerns

- **C1 — brief anchors are stale, not failed.** The brief's literal corpus
  command expects md5 `518eca…` over 1124 dirs, but the tree now has
  1133 dirs (frozen 1124 + 9 designed D1/D2 fixtures, all OK). Removing exactly
  those 9 designed lines reproduces `518eca…` and `950/58/116/0/0` with diff
  empty; 0 frozen-corpus movers. Likewise the markers anchor in the brief
  (3437/38384) predates the D1/D2 T3 marker change; the current T4 baseline is
  3436/38371, which this run matches exactly. No mover is attributable to T5.2.
- **C2 — `--help` parse added.** T5.2 requirement 4 and gate item 9 require
  `--help` to show the documented set, but `main.zig` had no `--help` branch
  (only the no-arg path printed usage). I added `--help` (print usage, exit 0)
  within the allowed `main.zig` CLI touch set and listed it in the help text.
  No `-h` alias was added (not required; dead `-t`/`-a`/`-y`/`-l` stay dead).
- **C3 — `-osw nt` consumes a file literally named `nt`.** This is the
  operator-specified semantics (bare/explicit profile token consumption); a
  single-file program named exactly `nt` invoked as `zig1 -osw nt` would need
  the `--`-less workaround of a different path. No ambiguity beyond the brief.
- **C4 — `-m/--max-mem` help wording.** The help text groups it with `-mm<N>`
  as a pool budget; both set `max_mem`, while `parseSize` and
  `parseMMBytes` differ in unit handling. This is pre-existing behavior; no
  behavior was changed here, only its help line added.

## 6. Commits

- `feat(main): -osw [9x|nt] target win profile` — `sf/src/main.zig`,
  `sf/src/c89_emit.zig`, tech docs.
- `docs(sdd): T5.2 report` — `git add -f
  .superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-5.2-report.md` only.
