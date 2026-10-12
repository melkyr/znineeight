# Strict-Zig Brace Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the 3 invalid `if (cond) stmt; else …` sites in `sf/src` to braced form so self-compile unblocks, with zig1 already strict and zig0 untouched.

**Architecture:** The defect is in `sf/src` source (which uses the invalid `;`-before-`else` form that zig0's lenient parser accepts but zig1 correctly rejects). Migrate exactly 3 sites to braced form — valid in both compilers, byte-identical emitted C (empirically verified). Add M8: a clear zig1 diagnostic for the invalid form.

**Tech Stack:** Z98 self-hosted compiler `zig1` (Z98 source, emits C89); zig0 C++98 bootstrap (immutable); gcc C89 link. No external deps.

## Global Constraints

- Z98 dialect: NO `anytype`, NO `@Type`. Use `fastedit`/`edit` tools only (no sed/python/awk).
- `sf/build/out_release/` WEDGED — NEVER touch/ls/build into it; always use `timeout`.
- Compiler under test = `/tmp/fx_subfolder/zig1`. Build via `bash sf/scripts/build_release.sh`, gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===` (wipes /tmp/fx_subfolder; reinstall std after every rebuild: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`).
- Byte-identity is the hard gate. Baselines (single-file `--dump-c89 | md5sum`, lisp from repo root): gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`.
- Corpus (263 dirs, per-module recipe `--dump-c89 --output-dir DIR` then gcc each .c): OK=254/FAIL=5/ICE=0/CRASH=0/GG=4 expected; FAIL=5 = field_store_drop, self_embed_optional_cycle, parsergap_selfblok_xmod, parsergap_specifier_xmod, parsergap_strict_comma_xmod.
- 21-example matrix 21/21; test_analyzer_bin "5 passed, 4 failed".
- `zig0` bootstrap is immutable — NOT to be changed, NOT to be "demoted".
- The `*%` operator gap at `util/hash.zig:18` is a separate pre-existing blocker — out of scope (record, do not fix).
- NO scope creep beyond the 3 migration sites + the M8 diagnostic.

## AMENDMENT (2026-08-18, operator ruling, M4-fix round)

M4 final review found a 4th unmigrated `;`-before-`else` site in the self-compile closure:
`sf/src/c89_emit.zig:410-412` (kind_char dispatch). It was missed because M2/M3 Step-1
verification grepped only `type_resolver.zig:98x` + first error (`head -10` stops at the first
error, so c89_emit was never reached). Operator ruling: **FIX c89_emit.zig:410-412 to braced form
AND expand the self-compile verification to a tree-wide `;\s*else` scan** so no same-class site
is missed. This is plan-scope-consistent: the plan's goal is "self-compile unblocks," and the
4th site is the same defect class with the same byte-identical braced fix.

---

### Task M0: Revert F5 leftovers — DONE (controller, 2026-08-18)

- [x] Reverted the uncommitted `sf/src/parser.zig` F5 changes (`git checkout -- sf/src/parser.zig`). Tree clean at HEAD `c7757251`.

---

### Task M1: Migration gate fixture + byte-identity proof

**Files:**
- Create: `repro/mi_matrix/strictzig_brace_if_xmod/{main.zig, NOTES.md}`

**Interfaces:**
- Consumes: spec D1/D2 (braces are byte-identical).
- Produces: committed evidence that `if (c) { stmt; } else { stmt; }` emits byte-identical C to the (previously invalid) `if (c) stmt; else stmt;` — locking the "no re-baseline" guarantee for the migration.

- [ ] **Step 1: Create the fixture**

`repro/mi_matrix/strictzig_brace_if_xmod/main.zig`:
```zig
const std = @import("std");
pub fn main() void {
    var x: u32 = 2;
    var kind: u32 = 0;
    if (kind == 0) x = x + 1;
    else x = x - 1;
    std.io.printInt(@intCast(i32, x));
}
```
NOTE: this fixture uses the CURRENTLY-INVALID form (`;` before `else`) as the RED baseline. NOTES.md documents: (a) RED — `zig1 --dump-c89 main.zig` → rc=2 error[2000] (the invalid form is rejected), (b) the braced variant `if (kind == 0) { x = x + 1; } else { x = x - 1; }` → rc=0, and its emitted C is what the migration produces.

- [ ] **Step 2: Run RED baseline** — `cd repro/mi_matrix/strictzig_brace_if_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?` → record rc=2 + error[2000] + 0-byte x.c.
- [ ] **Step 3: Run braced control** — temporary braced variant (in /tmp, not committed): dump rc=0, gcc rc=0, run prints `3`. Record byte-count.
- [ ] **Step 4: Commit** — `git add repro/mi_matrix/strictzig_brace_if_xmod && git commit -m "repro: brace-if migration gate + byte-identity evidence (strictzig_brace_if_xmod)"`. Report to `.superpowers/sdd/task-M1-report.md`.

---

### Task M2: Migrate the 3 invalid sites to braced form

**Files:**
- Modify: `sf/src/type_resolver.zig:980-981` and `:987-990`, `sf/src/diagnostics.zig:295-296`

**Interfaces:**
- Consumes: spec D1; M1 evidence.
- Produces: the 3 invalid `;`-before-`else` constructs become braced; self-compile passes `type_resolver.zig:981`.

- [ ] **Step 1: Reproduce the blocker (baseline)**

`timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig 2>/tmp/sc.err >/dev/null; grep -v "error\[9999\]" /tmp/sc.err | head -10` → first error = `type_resolver.zig:981:24: error[2000]`.

- [ ] **Step 2: Migrate the 3 sites** (re-read each region before editing; use fastedit)

1. `type_resolver.zig:980-981`:
```zig
if (sz_node.kind == AstKind.add) { arr_len = lhs + rhs; }
else { arr_len = lhs - rhs; }
```
2. `type_resolver.zig:987-990`:
```zig
if (sz_node.kind == AstKind.mul) { arr_len = lhs * rhs; }
else if (sz_node.kind == AstKind.div) { arr_len = lhs / rhs; }
else { arr_len = lhs % rhs; }
```
3. `diagnostics.zig:295-296`:
```zig
if (level == 0) { self.error_count += 1; }
else if (level == 1) { self.warning_count += 1; }
```
No other change. No `sf/src/parser.zig` change.

- [ ] **Step 3: Build + verify**

`bash sf/scripts/build_release.sh` → gate; reinstall std. Self-compile re-run: `type_resolver.zig:981` construct PASSES (no `type_resolver.zig:981` in filtered stderr); next gap = `*%` at `util/hash.zig:18` (record, don't fix). M1 fixture braced control still GREEN.

- [ ] **Step 4: Byte-identity gates**

4 MD5s byte-identical (baselines above). This must hold because braces around single-statement bodies are byte-identical (M1 proof) — but MEASURE, don't assume.

- [ ] **Step 5: Commit**

```bash
git add sf/src/type_resolver.zig sf/src/diagnostics.zig
git commit -m "fix: migrate invalid ;-before-else if/else to braced form (strict-zig if)"
```
Report to `.superpowers/sdd/task-M2-report.md`.

---

### Task M3: GATE — sweep + reconciliation

**Files:**
- Read: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Modify: both (numbers if moved)

**Interfaces:**
- Consumes: M2.
- Produces: verified gates + reconciled docs.

- [ ] **Step 1:** Rebuild + reinstall std (if not current).
- [ ] **Step 2:** 4 MD5 gates byte-identical (baselines above; lisp from repo root).
- [ ] **Step 3:** Corpus (per-module recipe). Record exact OK/FAIL/GG counts (expect OK=254/FAIL=5/GG=4@263 unchanged — the migration is byte-identical; M1 fixture becomes an OK dir, so expect 264 dirs with OK=255 if the fixture is in the corpus).
- [ ] **Step 4:** 21-example matrix + test_analyzer + self-compile re-check (type_resolver:981 passes; `*%` at hash.zig:18 recorded as the next blocker).
- [ ] **Step 5:** Reconcile EXPECTED_FAIL (version bump + closeout record) + QUICK_REF (corpus/MD5 lines, only if moved). Commit summary message listing the tasks included.
- [ ] Report `.superpowers/sdd/task-M3-report.md`.

---

### Task M8: Clear zig1 diagnostic for the invalid `;`-before-`else` form

**Files:**
- Modify: `sf/src/parser.zig` (`parserParseIfStmt`, then-body/else-dispatch region) — exact locus TBD by implementer investigation

**Interfaces:**
- Consumes: operator ruling (M8 = zig1 diagnostic, NOT bootstrap demotion); spec D3.
- Produces: when `zig1` parses `if (cond) stmt; else …`, it emits a clear, actionable diagnostic (e.g. `error[NNNN]: ';' not allowed before 'else' — use braces: if (cond) { … } else { … }`) instead of the current generic `error[2000]: expected expression`.

- [ ] **Step 1: Investigate the locus** — trace where `parserParseIfStmt` leaves the `;` unconsumed and the orphaned `else` triggers `error[2000]` (the statement loop / `parserParseModuleRoot` catch). Read-only; report exact file:line + the error-emission site.
- [ ] **Step 2: Implement the diagnostic** — when the if-statement's brace-less then-body is followed by `;` then `else`, emit the clear diagnostic at the else token's span (new ErrorCode or a targeted message on the existing path). Keep the parser's ACCEPT-set unchanged (valid forms unchanged; the invalid form still errors — just with a better message).
- [ ] **Step 3: Build + verify** — `bash sf/scripts/build_release.sh` → gate; reinstall std. M1 RED fixture now shows the CLEAR diagnostic (not generic error[2000]). Valid controls (`if (c) stmt;`, `if (c) stmt else stmt;`, braced) unchanged GREEN. `parsergap_selfblok_xmod` fixture (which uses the invalid form) still RED but with the clear message.
- [ ] **Step 4: Byte-identity gates** — 4 MD5s byte-identical (no valid input changed).
- [ ] **Step 5: Commit** — `git commit -m "fix: clear diagnostic for ';' before 'else' (strict-zig if M8)"`. Report to `.superpowers/sdd/task-M8-report.md`.

---

### Task M4: Final whole-branch review

- [ ] Dispatch the whole-branch review on the range (`c7757251`..HEAD) using the requesting-code-review template.
- [ ] Fix findings per the review loop; present completion to the operator.
