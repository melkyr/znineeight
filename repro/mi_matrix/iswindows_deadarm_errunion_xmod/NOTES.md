# iswindows_deadarm_errunion_xmod — D2 faithful repro (T0, RED before any fix)

## What it tests
Minimal reproducer of `examples/torrent_example_defects.md` D2, weaponized in
BOTH directions: each platform module (`windep.zig` = Windows-only
`@cInclude("<windows.h>")`, `linuxdep.zig` = Linux-only `@cInclude("<sys/ioctl.h>")`)
is referenced ONLY from the opposite-comptime arm of `if (@isWindows())`, and
the referenced fn returns an error union (`E!*void`) — the D2 trigger shape
(non-error-union references in a dead arm are already pruned).

## Mechanism (measured — report §1.2; supersedes the defect entry's hypothesis)
The statement-position `if (@isWindows())` fold path **fires** on this shape
(`sf/src/lower.zig:7770` `if_fold`): the untaken arm is never lowered and no
dead `call_direct`/`func_ref` survives into LIR or the emitted C (verified:
no `IF:c0=` marker; no dead call in `main_*.c`). The wrong-platform module is
kept by the **type-level value-reference channel**: `pruneTypeMarkByValue`
(`sf/src/main.zig:1149-1199`; the error-union branch recurses into
`p.error_set` at `:1199`) runs over every lowered fn's hoisted temps / return /
params (`main.zig:1311-1328`) and marks the **owner module of every
by-value-named type** reachable. The `E!*void` return type is a cross-module
type name — shared typedef `zT_D078880E_EU_46` + per-module `E` error-set
names = the EU name pins its owner module — plus the
`call_direct`/`tail_call`/`func_ref`/`load_global`/`store_global` scan over
ALL lowered functions (including the never-called module's own fns). T3 must
kill the type-level pin (or close the module over the live arm only); folding
the arm away alone does not unpin the module.

## Measured pre-fix (2026-10-16, seed-built `/tmp/d1d2_build/zig1_5_clean`, md5 `f18b69ece1917bf970a036b276e5e403`)
Linux build (`-ffast --dump-c89`):
- dump rc=0, 8 `.c` emitted — **BOTH** `windep_5A55131B.c` (wrong-platform,
  dead `@isWindows()` true arm) AND `linuxdep_6F2C77EB.c` (live) present.
- gcc `-c` of `windep_5A55131B.h` FAILS:
  `windep_5A55131B.h:6:10: fatal error: windows.h: No such file or directory`
  → whole build dies (class FAIL).

Windows build (`-osw --dump-c89`), symmetric:
- dump rc=0, 8 `.c` — **BOTH** `linuxdep_6F2C77EB.c` (wrong-platform, dead
  else arm) AND `windep_5A55131B.c` (live) present.
- mingw gcc `-c` of `linuxdep_6F2C77EB.h` FAILS:
  `linuxdep_6F2C77EB.h:6:10: fatal error: sys/ioctl.h: No such file or directory`
  (`windep_*.c` itself compiles clean on mingw).

## Expected classification
- RED pre-fix: **FAIL** on both targets (wrong-platform module emitted; gcc dies
  on its `@cInclude`). Recorded before any fix.
- After T3 (comptime-if fold: untaken arm not analyzed/not lowered): the
  wrong-platform module is not emitted; both targets cross-build; stdout
  `iswindows deadarm ok` / rc 0 → class **OK** (this NEW fixture's designed
  FAIL→OK flip; the pre-existing corpus class-file anchor is untouched). T3's
  verification also asserts the emission contract (`ls <out>/windep_*.c` empty
  on linux, `ls <out>/linuxdep_*.c` empty on `-osw`).

## Why no expected.txt/expected.rc
No runtime golden is measurable pre-fix (host gcc dies on the wrong-platform
include). zT_missing_fwd_xmod defect-repro shape (NOTES + sources). T3 captures
goldens at fix time (GREEN contract in main.zig header). The host-neutral twin
`iswindows_deadarm_prune_xmod` carries the pre-fix-measurable runtime golden.

## Post-fix measured (2026-10-16, T3 gate compiler `/tmp/d1d2_t3/zig1_5_clean`)
**Mechanism correction (supersedes the "Mechanism" section above):** T3's
probe matrix (`task-3-report.md` §Investigate) shows the operative pin was
the **runtime-init root seed** in `sf/src/main.zig` (a module with a
runtime-initialized global — this fixture's `var g: u32 = 0` — was
force-reached regardless of call/type reachability), not the
`pruneTypeMarkByValue` type-owner channel. The all-fn LIR scan and the
type-owner edges are load-bearing (modules are emitted atomically with all
their lowered fns) and are unchanged; the fix makes the runtime-init root
edge reachability-consistent. The spec §3 "Consequence" attribution is
likewise falsified (T6 owns the truth-up).

**Flip evidence:** linux `-ffast --dump-c89`: rc 0, `windep_*.c`/`.h`
ABSENT (only `linuxdep_6F2C77EB.*` + std), gcc clean, run
`iswindows deadarm ok` rc 0. `-osw`: `linuxdep_*` ABSENT, only
`windep_5A55131B.*`, mingw (`build_target.sh mingw`) clean, wine run
`iswindows deadarm ok` rc 0 (win arm live — `@isWindows()` polarity follows
the CLI target). Golden captured at flip (`expected.txt`/`expected.rc`).
Class flip: **FAIL → OK** (designed NEW-fixture flip).
