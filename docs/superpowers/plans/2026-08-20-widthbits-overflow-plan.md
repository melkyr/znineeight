# Self-Compile Width-Bits Overflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the self-compile `width_bits` u8-overflow PANIC (`c89_emit.zig:5002`) by widening the width type (gap-fill), and confirm no sibling `@intCast(u8, size*8)` site shares the defect.

**Architecture:** R (repro + re-verify sibling sites + whole-tree scan) → I (read-only analysis pinning the full width-typed surface + the shift-guard invariant) → STOP (operator ruling fills the F placeholder) → F (implement Option B gap-fill) → GATE (sweep + docs reconciliation) → M-FINAL (whole-branch review). Root cause (not symptom) decides the fix; default fix = Option B (widen `width_bits` u8→u32).

**Tech Stack:** Z98 dialect (no `anytype`/`@Type`), C89 emission, zig0 bootstrap.

## Global Constraints

- 4 MD5 gates byte-identical (single-file `--dump-c89 | md5sum`, lisp from repo root): gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `9720478c937409a29fe23ae0199821cf`.
- Corpus 286 dirs `OK=275/FAIL=7/ICE=0/CRASH=0/GG=4`; per-module corpus recipe (`--dump-c89 --output-dir DIR` then gcc each `.c`; stdout-concat falsely fails fn_ptr_struct_field).
- Matrix 21/21; test_analyzer_bin `5 passed, 4 failed`.
- Self-compile check: `timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig 2>/tmp/sc.err; grep -a "error[" /tmp/sc.err | grep -av 'error\[9999\]'`.
- Z98 dialect: no `anytype`/`@Type`; `@intCast` for width coercions only.
- edit/fastedit ONLY (no sed/python); edit DENIED for source — fastedit (re-read region before each edit; NEVER end_line=start_line-1; keep new_code single contiguous block).
- Never touch/ls `sf/build/out_release/` (WEDGED); all runs timeout-gated.
- I-task READ-ONLY mandate: ZERO committed source changes; /tmp-only instrumentation + revert; tree clean verified before finish. Fixes belong ONLY in F-tasks. Fallbacks NEVER allowed on prod compiler.
- Verification MUST scan the WHOLE tree/closure for the defect class, never stop at first error (M4 lesson).
- Repros are new fixture dirs only, using the EXISTING `/tmp/fx_subfolder/zig1` (NO rebuild during R/I). Fixture convention: bare `@import("std")` + `std.io.printInt`; RED = PANIC rc=134 / dump rc!=0; GREEN = dump/gcc/run rc=0; `main.zig` + `NOTES.md` committed; timeout-gated.
- Commit messages verbatim per task.

---

### Task R1: repro widthbits overflow + re-verify sibling sites

**Files:**
- Create: `repro/mi_matrix/widthbits_union_intconst_xmod/{main.zig,NOTES.md}`

**Consumes:** spec §Problem + §Blast radius. **Produces:** RED repro + sibling-site re-verification + whole-tree scan evidence for I.

- [ ] **Step 1: Write the failing fixture**

`repro/mi_matrix/widthbits_union_intconst_xmod/main.zig` — a tagged union with payloads large enough that the union type is >31 bytes (so `size*8` overflows u8), assigned a tag via `.int_const` (mirror the self-compile pattern; verify the emitted C path hits `c89_emit.zig:5002` with `is_tagged_union=1`). Minimal program that triggers the PANIC. Example shape (adjust to reproduce on the current binary):

```zig
const std = @import("std");

const Big = union(enum) {
    a: u32,
    b: [36]u8,
};

pub fn main() void {
    var u: Big = undefined;
    u = .b;
    var tag: u32 = @enumToInt(u);
    std.io.printInt(tag);
}
```

- [ ] **Step 2: Run to verify it fails**

Run from the fixture dir: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1 main.zig`
Expected: PANIC `integer cast overflow` (rc=134), 0-byte `.c`. If the fixture does NOT reproduce (union size <32 bytes or `.int_const` not hit), escalate the fixture (larger payloads / explicit tag assignment) until RED. Record the exact union byte-size and the PANIC locus.

- [ ] **Step 3: Re-verify the 2 sibling sites**

Confirm `c89_emit.zig:3190` (`emitSatBinary`) and `comptime_eval.zig:139` are reachable ONLY from integer-typed operands (size ≤ 8, width ≤ 64) — no overflow path. Spot-check the sat-math call sites (`emitSatBinary` callers) and the comptime int_cast fold callers. Record evidence (no RUN needed if static reachability is conclusive; note if a probe is warranted).

- [ ] **Step 4: Whole-tree scan for the defect class**

`grep -rn "@intCast(u8, .*size \* @intCast(u32, 8))" sf/src/` + `grep -rn "width_bits" sf/src/` — enumerate every width computation + every `width_bits` read. Confirm the spec's 3-site list is complete (or correct it with evidence). Also scan for any other `@intCast(u8, <expr with size>)` that could overflow on a >31-byte type.

- [ ] **Step 5: NOTES.md + commit**

NOTES.md: purpose, fixture verbatim, RED baseline (rc=134, PANIC text verbatim), sibling-site re-verification table, whole-tree scan results, post-fix expectation.
Commit: `repro: width_bits u8 overflow on tagged-union int_const (widthbits_union_intconst_xmod)`

### Task I-WIDTHBITS: analyze the width-typed surface + propose the fix (read-only)

**Files:** (none committed — report only)

**Consumes:** R1 evidence. **Produces:** the definitive fix design (Option B gap-fill) for the STOP/F placeholder.

- [ ] **Step 1: Trace the `.int_const` width path**

Trace `c89_emit.zig:4984-5055`: how `width_bits` is computed (`:4992/:5002`), where consumed (signed masking `:5018-5034`), and the tagged-union `.tag =` emission path (`:5009-5011`). Confirm `width_bits` is DEAD on the non-signed path (tagged unions never set `is_signed`). Record the exact shift-guard invariant: `1 << width_bits` (`:5021/:5025/:5029`) only reachable when `is_signed != 0`, and integer temps have size ≤ 8 → width ≤ 64, so widening introduces no shift-UB.

- [ ] **Step 2: Enumerate the full `width_bits`/`wb`-typed surface**

All sites that must widen if Option B is chosen (exact file:line + current type):
- `c89_emit.zig:4992` `var width_bits: u8` and `:5002` cast
- `c89_emit.zig:3190` `var width_bits: u8` (emitSatBinary)
- `c89_emit.zig:3160/3167/3174/3181` helper params `width_bits: u8` (satMaxLit/satMinLit/satMinMagLit/satMaxULit)
- `c89_emit.zig:3196/5020/5021/5024/5028/5029` consumers (itoa casts, comparisons, shifts)
- `comptime_eval.zig:16` `ComptimeVal.width_bits: u8`; `:56-57` width-max arithmetic; `:139` `var wb: u8`
Also flag any cross-file consumer of `ComptimeVal.width_bits` (lower/c89_emit reads).

- [ ] **Step 3: Propose the exact fix (default Option B)**

Recommend u32 (vs u16): both fit 40*8=320; u32 future-proofs and matches the u32 size conventions. Provide the exact widening for each site (type decl + cast + any `@intCast(u32, ...)` wrappers at the 3 compute sites; the 4 sat helpers' param types; comptime field + arithmetic). Confirm zero emission-byte change (widths only computed for int temps ≤64 in emitted output). State whether any sat-helper internals need guards (they only handle 8/16/32/64 — int-only callers, so no change beyond the param type). Note any Z98 dialect constraints on the widening (u32 comparisons `width_bits == @intCast(u8, 64)` become `@intCast(u32, 64)`).

- [ ] **Step 4: Blast radius + byte-identity reasoning**

Confirm no gate/corpus/example uses a tagged-union `.int_const` (>31-byte union) → 4 MD5s byte-identical by construction. Corpus classification unchanged. Record the discriminating post-fix check: R1 fixture RED→GREEN (PANIC → correct `.tag =` C emission, dump/gcc rc=0) + self-compile advances past `c89_emit.zig:5002`.

- [ ] **Step 5: Report + revert**

Write `.superpowers/sdd/task-I-WIDTHBITS-report.md`. Revert any /tmp instrumentation; `git status --porcelain -uall` empty before finishing.

### Task STOP: consolidated ruling

- [ ] Present R1 evidence + I-WIDTHBITS report to the operator. Operator fills the F placeholder (Option B endorsed, u16-vs-u32 adjudicated, any scope adjustments). Plan AMENDMENT committed documenting the ruling.

### Task F1: widen width_bits u8→u32 (per STOP ruling)

**Files:**
- Modify: `sf/src/c89_emit.zig` (`:4992/:5002`, `:3190`, `:3160/:3167/:3174/:3181` params, `:3196/:5020/:5021/:5024/:5028/:5029` consumers)
- Modify: `sf/src/comptime_eval.zig` (`:16`, `:56-57`, `:139`)
- Modify (if cross-file consumers found): any file reading `ComptimeVal.width_bits`

**Consumes:** I-WIDTHBITS §3 exact widening + STOP ruling. **Produces:** the gap-fill.

- [ ] **Step 1: Implement the widening (fastedit)**

Per I-WIDTHBITS §3 + STOP ruling: widen `width_bits`/`wb` u8→u32 at every enumerated site, add `@intCast(u32, ...)` wrappers, update comparisons/shifts (`@intCast(u64, width_bits)` shifts unchanged; `width_bits < @intCast(u8, 64)` → `@intCast(u32, 64)`). Single contiguous edits per region; re-read after each edit.

- [ ] **Step 2: Rebuild + gates**

Rebuild (`bash sf/scripts/build_release.sh`), reinstall std. Gates: 4 MD5s byte-identical; corpus 286 unchanged (classify); matrix 21/21; test_analyzer 5/4; R1 fixture RED→GREEN (dump/gcc rc=0, `.tag =` emitted); self-compile advances past `c89_emit.zig:5002` (PANIC gone — next frontier blocker recorded, NOT fixed); whole-tree scan confirms zero remaining `@intCast(u8, size*8)` width computations.

- [ ] **Step 3: Commit**

Commit message: `fix: widen width_bits to u32 (self-compile widthbits overflow)`

### Task GATE: final sweep + reconciliation

- [ ] **Step 1:** Corpus sweep (286 dirs), classify; verify OK=275/FAIL=7/ICE=0/CRASH=0/GG=4 (FAIL=7 unchanged; widthbits_union_intconst_xmod flips OK — corpus 287 if counted, reconcile).
- [ ] **Step 2:** 4 MD5s, matrix 21/21, test_analyzer 5/4.
- [ ] **Step 3:** EXPECTED_FAIL version bump + closeout (mechanism, F1, R1 fixture, new self-compile status incl. next frontier blocker). QUICK_REF baseline update.
- [ ] **Step 4:** Record next self-compile blocker (if any) — do NOT fix.
- [ ] Commit: `docs: widthbits-overflow GATE closeout + reconciliation`

### Task M-FINAL: final whole-branch review

- [ ] **Step 1:** `bash <skilldir>/scripts/review-package b093fb68 HEAD` → .diff.
- [ ] **Step 2:** Dispatch final reviewer (requesting-code-review/code-reviewer.md template).
- [ ] **Step 3:** Fix wave for Critical/Important findings (ONE fixer), re-review.
