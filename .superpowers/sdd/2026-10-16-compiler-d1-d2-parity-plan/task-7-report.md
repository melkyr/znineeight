# Task T7 report — Next-milestone review → z9play M6

**Plan:** `docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md` (Task 7).
**Gate (verbatim):** re-read the amended `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md` and judge it against the fixed compiler: two separate platform modules selected via `@isWindows()` cross-build clean on both targets; `readKey_fn` may return `?Key` (D1 fixed) though z9play keeps `Key.none`; conditional `@import` available if M6 prefers it. If an amendment is required, **STOP-present** it; else record "no amendment needed".
**Mode:** READ-ONLY analysis. Zero source edits, zero plan edits. This report is the only artifact written. M6 plan + its workspace `.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/` read-only (verified untouched); untracked `examples/z98/z9play/platform/audio_win9x*.zig` + `run.err` and dirty `progress.md` left alone.

---

## VERDICT: **no amendment needed**

The amended M6 plan's compiler-behavior assumptions are all satisfiable on the **fixed compiler** (tree `sf/src` at T5/T6 HEAD, post T1–T4 fixes): the plan's original two-separate-platform-modules architecture selected via `@isWindows()` cross-builds clean on both targets (the old D2 blocker is root-fixed), `readKey_fn: fn (*void) ?Key` compiles (D1 root-fixed; z9play keeps `Key.none` per operator ruling), and conditional `@import` is available as an optional tool. The M6 Task-1 (A)/(B) ruling question is **resolved by the fix — no ruling needed** (the plan text never adopted (A) or (B); only the workspace `task-1-report.md` asked). One operational caveat is real but is **not plan text** (Advisory A1: the pre-built seed-era binary recorded in the M6 workspace still exhibits D2; M6 must rebuild zig1 from current `sf/src` per the plan's own build recipe). Five advisories below are bookkeeping/implementation guidance; none reshapes the plan.

---

## M6 plan re-read

Re-read `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md` (amended at `075e1bf1`, "docs(plan): z9play M5b console contract + M6/M7/M8 amendments"). Compiler-behavior assumption inventory (every claim in the plan touching compiler behavior):

| # | plan anchor | claim | status vs fixed compiler |
|---|---|---|---|
| 1 | `:5` Goal, `:7` Architecture | Win9x audio + console backends, "selected at compile time via `@isWindows()`", `main`/`cli` select "with an explicit `else`" | LIVE on the fixed compiler (judgment (a)) |
| 2 | `:17` Global Constraints | "Z98 rules (`@isWindows()` must have an explicit `else` so both arms emit valid C)" | Still valid (stricter than needed post-fix — else-less Variant B also works (`3583668b`, defects doc `:186`) — harmless) |
| 3 | `:17` | "the M6 base seed is **v98** (fixed point `f18b69ece1917bf970a036b276e5e403`)" | ACCURATE as seed-archive identity (`release/seed/CHANGELOG.md:25,27`); build closure has moved since (Advisory A2 — recorded moving point, see Evidence E8) |
| 4 | `:17` | "compiler defects **D1–D8 are all FIXED** in seed v98 (see `examples/torrent_example_defects.md`)" | TRUE for the **pre-renumbering** D1–D8 (emitter-sanitization era, genuinely in the archive); numbering restarted (`examples/torrent_example_defects.md:8`) so the phrase must not be read as pinning current-ledger D1/D2 into the archive (Advisory A3) |
| 5 | `:17` | "this class of cumulative compiler defects can still surface in new shapes — if one is hit, STOP-present, apply a minimal example-only workaround, and record it" | Still live guidance (D3 OPEN/deferred `:192`, D4 OPEN `:208`) |
| 6 | `:35` Task 1 | waveOut backend "wire through `@isWindows()`" | LIVE (judgment (a)); old BLOCKER root-fixed |
| 7 | `:39` Task 2 | `readKey`: `ReadConsoleInput`/`KEY_EVENT`, `VK_*` → "the shared `Key` variants", Ctrl-C → `.sigint`; `leaveRaw` explicit before every `std.os.exit` + crash backstop | Coherent with the retained `Key.none` contract (judgment (b)); leave-before-exit is example-side, compiler-independent (anchor 6) |
| 8 | `:45` Task 3 | Route audio + console through `@isWindows()` if/else; `Z9PLAY_WAV_OUT` precedence on all platforms; exit codes 0/1/2/3/4/5 preserved; build `-osl` and `-osw` clean | LIVE (judgment (a)); precedence/exit-codes example-side, compiler-independent (anchor 6) |

The plan contains **no** text claiming D1 blocks `?Key` fn-ptrs, **no** text claiming D2 blocks separate platform modules, **no** "seed v97" residue (already superseded to v98 at `075e1bf1`), and **no** "blocked on compiler milestone" language (that lives only in the workspace `task-1-report.md`, not in the plan). No plan text endorses workaround (A) or (B).

---

## Judgment per point

### (a) Two separate platform modules selected via `@isWindows()` — LIVE; old D2 blocker gone

The plan's shape (two per-platform modules, selection at the call site via `if (@isWindows()) … else …`) is exactly the `iswindows_deadarm_errunion_xmod` class that the old D2 broke. Post-fix, the wrong-platform module is **not emitted** on either target:

- Fixtures `iswindows_deadarm_{errunion,prune,cond_if}_xmod` + `comptime_if_noelse_deadarm_xmod`: 4/4 PASS (E1).
- Emission contract measured both directions (E2 linux, E3 `-osw`): live module only; the wrong-platform module (and its platform-only `@cInclude`) is absent → cross-build clean on both targets.
- Mechanism/fix: defects doc `:117` ("the per-platform `@isWindows()` backend selection the plan needed is unblocked"), fix commits `58c4cb1c`+`3583668b`+`a7828e5e`+`d568880c` (`:186`).

Caveat carried to Advisory A1 (not a plan defect): a **pre-fix binary** still exhibits D2 (E2/E3 left column). The plan's build recipe goes through `scripts/seed/build_from_seed.sh`, which "Rebuild[s] zig1 from the CURRENT sf/src using a bootstrap seed" (`scripts/seed/build_from_seed.sh:7`) — so a build run per the plan/NOTES recipe today produces the fixed compiler.

### (b) `readKey_fn` may return `?Key` — CONFIRMED; z9play keeps `Key.none` (deliberate)

- D1 root-fixed: fixtures `fnptr_opt_aggregate_{coerce,emit}_xmod` PASS (E1). `fnptr_opt_aggregate_coerce_xmod/main.zig` is literally the M5b console shape — `readKey_fn: fn (*void) ?Key` with a `?Key`-returning `readKey` (fixture source; D1 mechanism + fix commits `5a56b501`+`1c5247b9` at defects doc `:107`).
- z9play keeps the in-band workaround per operator ruling: defects doc `:17` ("the example-only `Key.none` workaround is RETAINED per operator ruling") + `:111` ("the compiler now accepts the original `fn (*void) ?Key` shape … belt-and-braces; no compiler dependency either way").
- Plan coherence: Task 2 (`:39`) maps `VK_*` to "the shared `Key` variants" — i.e. the M5b contract `readKey_fn: fn (*void) Key` returning `Key.none` when idle (`examples/z98/z9play/platform/console.zig:53`, `:18`). Nothing in the M6 plan requires `?Key`; if M6 ever prefers it, it now compiles (optional freedom, not a mandate).

### (c) Conditional `@import` — AVAILABLE (optional tool)

- Fixtures `conditional_import_{if,switch,lazy}_xmod` 3/3 PASS (E1); live module selected per target, dead-arm `@import` never loads its file (defects doc `:186`, T4 `a7828e5e`+`d568880c`).
- D3 caveat (defects doc `:192`, OPEN/deferred): evaluator-foldable-but-not-parse-foldable conditions still eagerly load the dead arm's `@import`. The `@isWindows()`/literal-bool family is parse-foldable → safe. If M6 prefers conditional `@import`, keep conditions in that family (Advisory A4). The plan as written uses plain `if (@isWindows()) … else …` module selection (`:7`, `:45`) which needs no conditional import at all.

### (d) Other stale assumptions vs current compiler/seed state — none blocking; 2 bookkeeping notes

- **Seed/fixed point** (`:17`): "seed v98 (fixed point `f18b69ece1917bf970a036b276e5e403`)" matches the seed-archive identity exactly (`release/seed/CHANGELOG.md:25` seed binary md5, `:27` fixed point, `:28` archive md5 `74acfdadbb48fb658e59cf8da6ad678a`; term-of-art used identically in this milestone's own plan Build reference "seed **v98**, fixed point `f18b69ece1917bf970a036b276e5e403` (will move — recorded)"). The archive was NOT rotated (last entry `release/seed/CHANGELOG.md:14` "2026-10-16 — seed v98 (HEAD `313372d3`)", and all six fix commits are **not** ancestors of `313372d3`, E5). The **build closure** has since moved: T5 recorded "three-hop closure OK (moving point): hop2 == hop3 == `b0e5f3b4e580f69eacdac7bd0e07dda1`" with "fixed point old `8a9ea90a…` → **new `b0e5f3b4…`**" (`.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-5-report.md:184`; moving-point semantics per `scripts/seed/build_from_seed.sh:159`). This is the operator-approved "pins MAY move" pattern of this milestone, not a plan-behavior claim → Advisory A2 (M6 Task 5 owns the NOTES/README build-recipe comment refresh anyway, m6 plan Task 5).
- **"D1–D8 all FIXED in seed v98"** (`:17`): true for the pre-renumbering D1–D8 (emitter-sanitization closeout = the seed era). The defects ledger restarted its numbering (`examples/torrent_example_defects.md:8`) and its current D1/D2 were fixed **in `sf/src` after `313372d3`** (E5) — i.e. in the tree the seed bootstraps, not in the archive's self-emission C → Advisory A3 (disambiguation; NOTES already carries the `ade87e7f` disambiguation pattern).
- **F1/F4** (brief mention): root-fixed in `3d1397b2` `fix(type_resolver): T4.1 — name-id-as-node-index root fix (F1) + fn-param child_buf clobber (F4)` (git log; `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-4.1-report.md`). The M6 plan never references F1/F4 shapes; parser robustness only — nothing stale.
- **Exit codes 0–5 + `Z9PLAY_WAV_OUT` precedence + leave-before-every-exit** (`:39`, `:45`; anchor 6): example-side, unaffected by the compiler fixes; plan text coherent and consistent with the M5b adjudication ("no amendment needed" for M6's contract mapping, `.superpowers/sdd/2026-10-16-z9play-m5b-console-contract-plan/task-6-report.md:9-11`, incl. `Key` incl. `.none` and the explicit-leave rule).

### (e) M6 Task-1 historical question (A) guards-inside-Linux-backends vs (B) target-neutral module — RESOLVED by the fix; no ruling needed

The workspace `task-1-report.md` (BLOCKED, 2026-10-16-era) asked the controller for (A)/(B)/(C) because seed-v98-era compilation emitted the wrong-platform module through an error-union reference in a comptime-dead `@isWindows()` arm. That is precisely D2, now root-fixed (E2/E3: the same fixture shape emits only the live module on both targets with the fixed compiler; defects doc `:117`). Consequences:

- The plan's **original separate-module shape is restored** — no (A) guard rewrite of the Linux backends (outside the plan's file structure `examples/z98/z9play/platform/{audio_win9x,console_win9x}.zig` + `main.zig`/`cli.zig` routing), no (B) target-neutral single-module restructure.
- The plan text never contained the (A)/(B) question, so **no plan amendment is required** to answer it; this report is the answer: neither (A) nor (B) — resume Task 1 wiring as planned (m6 plan `:35`, `:45`).
- The workspace report's uncommitted deliverables (`platform/audio_win9x.zig` + `audio_win9x_pal.zig`, left untouched) stand as-is; only the then-blocked `main.zig` wiring was reverted there, and that wiring is now unblocked.

---

## Evidence

Commands run from repo root on branch `zig1_improvements` (HEAD `951a53eb`); observed output verbatim.

**E1 — parity fixture battery, post-fix compiler (9 PASS / 0 FAIL):**

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/t5_work/post/zig1_5_clean \
    repro/mi_matrix/fnptr_opt_aggregate_coerce_xmod repro/mi_matrix/fnptr_opt_aggregate_emit_xmod \
    repro/mi_matrix/iswindows_deadarm_errunion_xmod repro/mi_matrix/iswindows_deadarm_prune_xmod \
    repro/mi_matrix/iswindows_deadarm_cond_if_xmod repro/mi_matrix/comptime_if_noelse_deadarm_xmod \
    repro/mi_matrix/conditional_import_if_xmod repro/mi_matrix/conditional_import_switch_xmod \
    repro/mi_matrix/conditional_import_lazy_xmod
PASS repro/mi_matrix/fnptr_opt_aggregate_coerce_xmod
PASS repro/mi_matrix/fnptr_opt_aggregate_emit_xmod
PASS repro/mi_matrix/iswindows_deadarm_errunion_xmod
PASS repro/mi_matrix/iswindows_deadarm_prune_xmod
PASS repro/mi_matrix/iswindows_deadarm_cond_if_xmod
PASS repro/mi_matrix/comptime_if_noelse_deadarm_xmod
PASS repro/mi_matrix/conditional_import_if_xmod
PASS repro/mi_matrix/conditional_import_switch_xmod
PASS repro/mi_matrix/conditional_import_lazy_xmod
----------------------------------------
run_fixtures: 9 PASS / 0 FAIL over 9 dirs
```

**E2 — D2 repro (plan architecture shape) on the LINUX target, dual compiler:**

```
$ /tmp/z9play_seed_v98/zig1_5_clean -ffast -o /tmp/t7_seedv98 \
    repro/mi_matrix/iswindows_deadarm_errunion_xmod/main.zig        # seed-era binary
$ ls /tmp/t7_seedv98 | grep -E 'windep|linuxdep'
linuxdep_6F2C77EB.c / .h        # live (linux)
windep_5A55131B.c / .h          # WRONG platform — D2 still present

$ /tmp/t5_work/post/zig1_5_clean -ffast -o /tmp/t7_postfix \
    repro/mi_matrix/iswindows_deadarm_errunion_xmod/main.zig        # post-fix binary
$ ls /tmp/t7_postfix | grep -E 'windep|linuxdep'
linuxdep_6F2C77EB.c / .h        # live only — wrong-platform module absent
```

**E3 — same repro on the `-osw` target, dual compiler (symmetric):**

```
$ /tmp/t5_work/post/zig1_5_clean -osw -ffast --dump-c89 --output-dir /tmp/t7_postfix_w \
    repro/mi_matrix/iswindows_deadarm_errunion_xmod/main.zig        # rc 0
$ ls /tmp/t7_postfix_w | grep -E 'windep|linuxdep'
windep_5A55131B.c / .h          # live only — linuxdep absent (no <sys/ioctl.h> leak into mingw)

$ /tmp/z9play_seed_v98/zig1_5_clean -osw -ffast --dump-c89 --output-dir /tmp/t7_seed_w …   # rc 0
$ ls /tmp/t7_seed_w | grep -E 'windep|linuxdep'
linuxdep_6F2C77EB.c / .h        # WRONG platform
windep_5A55131B.c / .h
```

**E4 — compiler identities:**

```
$ md5sum /tmp/z9play_seed_v98/zig1_5_clean /tmp/t5_work/post/zig1_5_clean
f18b69ece1917bf970a036b276e5e403  /tmp/z9play_seed_v98/zig1_5_clean   # = seed v98 archive fixed point
2c48fa702393032c2b711a8d982bd388  /tmp/t5_work/post/zig1_5_clean     # = T5 post-fix gate build (task-6-report.md:76-77)
```

**E5 — the seed archive predates every fix commit (fixes are in `sf/src`, not in the archive):**

```
$ git log -1 --oneline 313372d3        # seed v98 rotation HEAD (release/seed/CHANGELOG.md:14,24)
313372d3 docs(sdd): P7 complete — review ledger
$ for c in 5a56b501 1c5247b9 58c4cb1c 3583668b a7828e5e d568880c; do \
      git merge-base --is-ancestor $c 313372d3 && echo "$c IN seed v98" || echo "$c NOT in seed v98"; done
5a56b501 NOT in seed v98     # fix(type_registry): D1 identity
1c5247b9 NOT in seed v98     # fix(c89_emit): D1 typedef ordering
58c4cb1c NOT in seed v98     # fix(semantic_analyzer): D2 comptime-if fold
3583668b NOT in seed v98     # D2 else-less Variant B
a7828e5e NOT in seed v98     # feat: conditional @import
d568880c NOT in seed v98     # fix(parser): dead-arm @import laziness
```

(Fix-commit identities cross-checked at `examples/torrent_example_defects.md:107` and `:186`.)

**E6 — the plan's build recipe produces the FIXED compiler (seed is bootstrap only):**

```
$ sed -n '7p;159p' scripts/seed/build_from_seed.sh
# Rebuild zig1 from the CURRENT sf/src using a bootstrap seed (Task-1/2 recipe
    # Moving point: the committed seed's dump predates the current sf/src, so
```

**E7 — seed-archive identity (the plan's `:17` parenthetical source of truth):**

```
$ sed -n '25p;27p;28p' release/seed/CHANGELOG.md
| seed binary md5 | `f18b69ece1917bf970a036b276e5e403` |
| fixed point | `f18b69ece1917bf970a036b276e5e403` |
| archive md5 | `74acfdadbb48fb658e59cf8da6ad678a` |
```

**E8 — current tree closure (recorded moving point):**

```
$ sed -n '184p' .superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-5-report.md
| 6 | seed two-hop | `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t5_work/post` | `three-hop closure OK (moving point): hop2 == hop3 == b0e5f3b4e580f69eacdac7bd0e07dda1` | fixed point old `8a9ea90a4976165b2074279be7f7ab32` → **new `b0e5f3b4…`** (verdict (a) moving point) |
```

**E9 — workspace prebuilt binary (Advisory A1 anchor):**

```
$ sed -n '23p' .superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/progress.md
- Base seed v98 built: `/tmp/z9play_seed_v98/zig1_5_clean` (hop1==hop2 == `f18b69ece1917bf970a036b276e5e403`).
```

That binary is the E2/E3 left column — D2 still live in it. It predates `5a56b501`…`d568880c` (E5) and must not be reused for Task 1 wiring.

---

## Advisories (M6 implementation guidance — none is a plan amendment)

- **A1 — rebuild zig1 before Task 1 wiring.** Run `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` from current HEAD (`build_from_seed.sh:7` compiles **current `sf/src`**). Do **not** reuse the pre-fix `/tmp/z9play_seed_v98/zig1_5_clean` of `progress.md:23` — it still emits the wrong-platform module (E2/E3). Expected print: `three-hop closure OK (moving point): hop2 == hop3 == b0e5f3b4e580f69eacdac7bd0e07dda1` (E8), not `two-hop … f18b69e`.
- **A2 — build-recipe comment moves.** M6 Task 5 (docs) refreshes `NOTES.md`'s closure comment (v98-era `two-hop … f18b69e` → post-fix moving point `b0e5f3b4…`); the plan's `:17` "seed v98 (fixed point `f18b69e…`)" stays accurate as the **archive identity** (E7) and needs no edit.
- **A3 — defect-numbering disambiguation.** Read `:17` "D1–D8 are all FIXED in seed v98" as the **pre-renumbering** D1–D8; the ledger restarted at D1 (`examples/torrent_example_defects.md:8`). Current D1/D2 are fixed in `sf/src` post-`313372d3` (E5), delivered to M6 through the source rebuild (A1), not through the archive C.
- **A4 — D3 safe family.** If M6 adopts conditional `@import`, keep the condition in the `@isWindows()`/literal-bool (parse-foldable) family; exotic evaluator-foldable conditions still eager-load the dead arm (D3, `examples/torrent_example_defects.md:192`).
- **A5 — Task-1 (A)/(B)/(C) request answered.** None of the three: the fix restores the plan's original separate-module shape (judgment (e)). Resume Task 1 exactly as planned (m6 plan `:35`); the uncommitted `audio_win9x*.zig` deliverables stand.

---

## Verdict (return contract)

**Status: DONE — "no amendment needed" recorded.**

One-line: the amended z9play M6 plan is live against the fixed compiler — `@isWindows()` two-module selection cross-builds clean on both targets (E1–E3), `?Key` fn-ptrs compile (D1, E1) with `Key.none` retained by choice, conditional `@import` is available (E1) — and the Task-1 (A)/(B) question is void (fix restores the original shape); no plan text needs to change.

**Concerns:** (1) stale prebuilt-toolchain hazard — resuming M6 against `/tmp/z9play_seed_v98/zig1_5_clean` without an `sf/src` rebuild would re-surface D2 and could be misread as "fix incomplete" (Advisory A1); (2) the brief's parenthetical "(seed v98, fixed point `b0e5f3b4…`)" conflates the seed-archive identity (`f18b69e…`) with the current tree closure (`b0e5f3b4…`) — both are truth-upped with anchors above (E7/E8); non-blocking.
