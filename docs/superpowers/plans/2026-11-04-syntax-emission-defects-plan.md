# Syntax-Emission Defects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find and fix the compiler defects behind two VM failures in which legal Z98 with unchanged meaning produced unsupported/illegal C: (A) a `switch` on a 64-bit integer emitted as a C `switch` that OpenWatcom rejects, and (B) a function emitted as a `pal_trap()` stub at runtime.

**Architecture:** First reproduce each defect with a **corpus** fixture and capture the emitted C/artifacts (TA, TB). Then STOP and present both confirmed defects. After approval, fix the emitter/lowering at the origin, add the regression gate, run the full compiler battery, and rotate the seed. No example workarounds.

**Tech Stack:** Z98 compiler (`sf/src/c89_emit.zig`, `sf/src/lower.zig`, `sf/src/main.zig`), corpus (`repro/mi_matrix/`), gates (`scripts/compiler/`), seed rotation.

**Spec:** `docs/reference/Language_Spec_Z98.md` §3.1 (`switch` condition may be a tagged union, integer, enum, or boolean) and §3.2–3.3. Defect A is the emitter violating that contract for 64-bit integers; defect B is a lowering/emission contract violation still to be localised.

## Global Constraints

- **This is a compiler milestone.** `sf/src/**` changes are expected. Example sources stay as the real-world triggers; do NOT work around a defect in an example.
- **Repros live in the corpus.** Every defect reproducer is a `repro/mi_matrix/` directory (picked up by `scripts/corpus/list_corpus_dirs.sh`) with `main.zig`, `expected.txt`, `expected.rc`, and — for the std gate — no entry in `scripts/stdlib/expected_dirs.txt` unless the task says so. No out-of-corpus throwaway fixtures for the defect itself.
- **Legal Z98 only.** A repro's source must be legal Z98 whose meaning is unchanged by any later fix. Cite the spec rule in the task report.
- **Zig parity (reference 0.17.1, downloaded in I0).** A negative literal or negative named constant is legal when the switch condition is a **signed** integer (the prong must match); on an **unsigned** condition it is a clean level-0 rejection (rc 2, zero `.c`), never a silent drop. The exact diagnostic is pinned from the I0 probes. Negative values are stored as the two's-complement bit pattern in `SwitchCase.value` and printed with the condition's signedness (32-bit `case -1:`; 64-bit `Z98_I64_C(-1)`).
- **Signed enum backings are in scope (operator ruling D3=b).** `enum(iN)` declarations with negative discriminants must be accepted and switch correctly; an unsigned backing with a negative discriminant rejects. The pre-existing `lower.zig:7259` `@intCast(u64, member.value)` must become a bit pattern (`@bitCast`) so the `-fsafe` self-build cannot trap. Function-local `const` case items remain the documented limitation (operator ruling D2) and are out of scope.
- **STOP after TA and TB.** Present the two confirmed defects (repro paths, emitted C, toolchain errors, root-cause hypothesis) and wait for the operator before dispatching any fix task.
- **All final-review minors are in scope (operator m2709).** The second investigation (I-B) covers Importants 2 and 3 plus **every** Minor from the final whole-milestone review: Minor 4 (wide enum member macros), Minor 5 (stale repro header), Minor 6 (bool + negative case), Minor 7 (workspace residue), Minor 8 (docs housekeeping). Minor 4 straddles the Critical carrier-width layer: I-A owns the shared literal helper, I-B consumes it.
- **Operator m2750 additions.** The adjacent `enum_value_table` u32 defect is in scope (Task 6a). Fix wave B is split into 6a (enum), 6b (case-item), 6c (minors). The `enum(u64)`-above-i64-max case gets a documented limitation **and** a clear diagnostic; no registry storage/layout change. Gates extend existing scripts; **no new gate script**.
- **Mandatory middle STOP before any fix (operator m2709).** After I-A and I-B are delivered, STOP: present the consolidated root causes, shared-layer verdict, fix shapes, repro/gate plan and any semantics rulings needed. No compiler edit, no diagnostic/rc change, and no seed rotation before explicit operator approval.
- **No pin re-baseline** unless a fix changes emitted C for an existing gate program. If it does, STOP and present the evidence before re-recording.
- **Build/test discipline.** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/<dir>`; sequential `zig1` runs in fresh dirs; `edit`/`fastedit` only (fastedit: re-read the region immediately before each call; edit bottom-to-top; to INSERT replace the anchor line with [new content + the original anchor line verbatim]); no sed/perl/python/awk; no `git checkout`; no push; `run.err` untouched; `git diff --check` clean.

## Review Focus

- **Both repros must be falsifiable:** each must fail today for the stated reason and pass after the corresponding fix, with the failure captured as compiler output or emitted C (not a hand-written claim).
- **64-bit switch coverage:** unsigned/signed, case values above `2^32`, negative `i64` cases, `else`, and the no-match path; the fix must not change 32-bit switch emission.
- **Trap-stub reproduction:** identify the exact host build/emission that turns the function body into `pal_trap()`; distinguish a compiler defect from stale artifacts and from the VM's GCC 3.4.5 by controlled comparison.
- **Battery integrity:** corpus movers, goldens, pins, markers, and stdlib are recorded before/after; any change is explained by the fix, not hidden.
- **Windows portability:** the emitted C must stay C89 and accepted by OpenWatcom and MSVC, not merely by GCC.
- **Signed enum coverage (F2):** `enum(i32)`/`enum(i64)` with negative discriminants (single member and range), `enum(u32)` + negative discriminant rejection, signedness of the emitted case labels, and no `-fsafe` trap in `lowerSwitchCaseItemMemberValue`.
- **Negative case semantics (I0–F):** negative literal / named const / range endpoints on signed conditions match; unsigned conditions reject with the I0-pinned diagnostic; negative enum discriminants and the 32-bit vs 64-bit C label forms are covered.

---

### Task TA: Repro defect A — 64-bit `switch` emits unsupported C

**Files:**
- Create: `repro/mi_matrix/switch_u64_ok_xmod/main.zig`, `expected.txt`, `expected.rc`
- Create: `repro/mi_matrix/switch_i64_ok_xmod/main.zig`, `expected.txt`, `expected.rc`
- Create: `scripts/compiler/gate_switch_width.sh` (detection gate; may be RED in this task)
- Test: the two repro dirs + the new gate

**Interfaces:**
- Consumes: nothing.
- Produces: two corpus reproducers and a gate that fails while the emitter writes a 64-bit C `switch`.

- [ ] **Step 1: Write the unsigned repro**

`switch_u64_ok_xmod/main.zig`: legal Z98, `var x: u64` set to `0x100000000` (2^32); `switch (x)` with prongs `0`, `0x100000000`, `0xFFFFFFFFFFFFFFFF`, `else`; each sets `r`; print `r` with `std.io.printInt`. Expected stdout `2\n`, `expected.rc` `0`. The case values above 32 bits are deliberate.

- [ ] **Step 2: Write the signed repro**

`switch_i64_ok_xmod/main.zig`: `var x: i64` set to `-4294967296`; `switch (x)` with prongs `0`, `-4294967296`, `4294967296`, `else`; expected stdout matches, `expected.rc` `0`.

- [ ] **Step 3: Build and confirm the repros run correctly under GCC**

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/def_a`; for each dir `mkdir -p out && /tmp/def_a/zig1_5_clean -o out main.zig && sh out/build_target.sh linux prog && ./prog`, compare to `expected.txt`/`expected.rc`.
Expected: both PASS under GCC — the defect is C portability, not Linux semantics.

- [ ] **Step 4: Capture the emitted C and the toolchain failure**

For each repro, emit with `--dump-c89` (single-file form) and record the `switch (<64-bit temp>)` line and the temp's declared type. Record the OpenWatcom 1.9 failure on the emitted module C (`wcc386` on the VM or the operator-provided log): `E1078: Invalid type for switch expression` at the `switch`. If no OWC log is available, record the emitted C and the documented OWC behavior; the gate below is the local check.

- [ ] **Step 5: Write the detection gate (RED)**

`scripts/compiler/gate_switch_width.sh <zig1>`: emit each repro with `--dump-c89` into a fresh dir; fail if any emitted `switch (` controlling temp is declared as a 64-bit C type (`zT_*_u64`/`i64`/`__int64`/`unsigned __int64`); pass otherwise. Run it now.
Expected: FAIL on both repros (64-bit C `switch` present).

- [ ] **Step 6: Commit (repro only; no fix)**

```bash
git add repro/mi_matrix/switch_u64_ok_xmod repro/mi_matrix/switch_i64_ok_xmod scripts/compiler/gate_switch_width.sh
git commit -m "test(repro): 64-bit switch emits unsupported C"
```

### Task TB: Repro defect B — function emitted as a `pal_trap()` stub

**Files:**
- Create (only if reproduced): `repro/mi_matrix/switch_trap_*_xmod` or the minimal corpus repro named by the evidence
- Create/modify: `.superpowers/sdd/<plan>/tb-artifacts/` (git-ignored notes; no repo source edits)
- Test: the repro + the reproduction protocol below

**Interfaces:**
- Consumes: Task TA's build/emit recipes.
- Produces: either a corpus repro and a root-cause report, or a definitive "not a compiler emission defect" report with the controlled evidence.

- [ ] **Step 1: Reproduce with controlled emitters**

Build/emit z9torr with three emitters into three fresh dirs: (a) the Linux-built `zig1_5_clean`, (b) a MinGW-hosted `zig1.exe` built from the same seed (`i686-w64-mingw32-gcc`, run under Wine), (c) the operator's OWC-built compiler if provided. Emit at current HEAD into each dir; keep every `console_*.c` produced.

- [ ] **Step 2: Diff the emitted `console_*.c`**

Compare the three emissions byte-for-byte. If any emitter writes `pal_trap();` where the source has the `GetStdHandle`/`GetFileType` body, that emitter is the defect; continue. If all three emit the correct body, record the diffs and go to Step 4.

- [ ] **Step 3: Minimise to a corpus repro**

From the failing emission, reduce the triggering construct to the smallest legal Z98 file that reproduces the trap stub under that emitter, and place it as `repro/mi_matrix/<name>_xmod/` with `expected.txt`/`expected.rc`. The repro must show the defect today (trap/illegal behaviour with that emitter) and is the regression case for the fix.

- [ ] **Step 4: If it does not reproduce**

Record: the three emitted `console_*.c` hashes, the `.o`/exe disassembly showing the VM binary's `pal_trap` stub versus the locally built object, and whether the VM's GCC 3.4.5 (not our compiler) miscompiles otherwise-correct C. Then STOP and present this evidence; do not invent a compiler fix.

- [ ] **Step 5: Commit (only if a repro was produced)**

```bash
git add repro/mi_matrix/<name>_xmod
git commit -m "test(repro): emitted pal_trap stub"
```

---

## STOP — present the defects

After TA and TB, present to the operator, in one message:
1. the two repro paths and their current RED evidence;
2. the emitted C snippets and the toolchain errors;
3. for defect B, the controlled-emitter comparison and whether it is our compiler, a stale artifact, or the VM toolchain;
4. the proposed fix location (defect A: `sf/src/c89_emit.zig` `.switch_br`; defect B: the localised path) and the expected battery impact.

Do not dispatch the fix tasks until the operator approves.

---

### Task 1: Fix defect A — portable 64-bit `switch` lowering

**Files:**
- Modify: `sf/src/c89_emit.zig` (`.switch_br`, around `:8370`; and the case-literal formatting for A2)
- Modify: `repro/mi_matrix/switch_u64_ok_xmod/main.zig`, `expected.txt` (A2 selected-case regression)
- Test: `scripts/compiler/gate_switch_width.sh`, the two TA repros

**Interfaces:**
- Consumes: `getTempTypeByIndex(emitter, temp_id)` (`c89_emit.zig:754`) to read the condition's type.
- Produces: for a 64-bit condition only, an `if / else if / else` chain with the same `goto` targets; 32-bit conditions keep the existing C `switch`; 64-bit case constants are emitted exactly.

- [ ] **Step 0: Pin defect A2 (wrong 64-bit case literal)**

Extend `repro/mi_matrix/switch_u64_ok_xmod` with a second `switch` whose selected prong is `0xFFFFFFFFFFFFFFFF` and which prints `3`; expected output becomes `2\n3\n`. Run the repro with the current compiler: expect RED (`2\n4\n`, because the emitted case constant is `8446744073709551615` instead of `18446744073709551615`). The repro is the A2 regression.

- [ ] **Step 1: Confirm the gate is RED**

Run `bash scripts/compiler/gate_switch_width.sh /tmp/def_a/zig1_5_clean`; expect FAIL.

- [ ] **Step 2: Implement the type-aware lowering**

In `.switch_br`: if the condition's C type is 64-bit, evaluate the condition temp once, then emit `if (cond == <case0>) goto z_bb_N;` / `else if ...` / `else goto z_bb_else;`. Format case literals with the existing 64-bit literal helper (unsigned/signed as the condition requires; values > 2^32 and negative `i64` cases must be exact). Keep the `-fsafe` behavior unchanged (no extra checks). 32-bit conditions keep the `switch` emission byte-identically.

- [ ] **Step 3: Rebuild and re-run the gate**

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/def_a_fix`; run the gate against the new compiler.
Expected: PASS for both repros; 32-bit switch output unchanged (spot-check an existing corpus dir that uses a 32-bit switch).

- [ ] **Step 4: Confirm the repros still behave correctly**

Build and run both repros under GCC and (operator-run) OWC. Expected: stdout/rc match; OWC compiles the module with no `E1078`.

- [ ] **Step 5: Commit**

```bash
git add sf/src/c89_emit.zig
git commit -m "fix(c89_emit): lower 64-bit switch to a portable if/else chain"
```

### Task 2: Fix defect B (SKIPPED — TB found no compiler emission defect)

TB proved all three emitters produce a correct `stdoutIsConsole`; the VM trap stub is a stale/mixed build artifact. No fix is applied. The evidence is carried into Task 4 docs.

**Files:** the exact files named by the TB report.
**Interfaces:** depends on the TB finding; no speculative changes.

- [ ] **Step 1:** SKIP. TB found no compiler emission defect (stale artifact). Carry the evidence into Task 4.

### Task I2: Repros — negative integer case items (corpus, RED; runs first)

**Files:**
- Create: `repro/mi_matrix/switch_neg_i32_ok_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `repro/mi_matrix/switch_neg_i64_ok_xmod/…`
- Create: `repro/mi_matrix/switch_neg_range_ok_xmod/…` (`x: i32 = -3`, range `-5...-1`)
- Create: `repro/mi_matrix/switch_neg_const_ok_xmod/…` (`const NEG: i32 = -1;` as a prong)
- Create: `repro/mi_matrix/switch_neg_unsigned_reject_xmod/…` (`x: u32 = 1`, prong `-1`; expected clean rejection)
- Modify: the two Task 1 repro headers (stale present-tense claim) and `scripts/compiler/gate_switch_width.sh` (zero-switch AWK edge)
- Test: the five repros + the gate

**Interfaces:** none new. Signed repros print `7` (prong matches) vs `9` (else); today they print `9` because the prong is dropped. The unsigned reject compiles today (rc 0, prints `9`) and must become rc 2 / 0 `.c` after F.

- [ ] **Step 1: Create the repros** per the names/semantics above; each `expected.rc` `0` except the unsigned reject (`2`).
- [ ] **Step 2: Confirm RED** — signed repros print `9`; the unsigned repro compiles rc 0. Record it.
- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/switch_neg_i32_ok_xmod repro/mi_matrix/switch_neg_i64_ok_xmod repro/mi_matrix/switch_neg_range_ok_xmod repro/mi_matrix/switch_neg_const_ok_xmod repro/mi_matrix/switch_neg_unsigned_reject_xmod repro/mi_matrix/switch_u64_ok_xmod repro/mi_matrix/switch_i64_ok_xmod scripts/compiler/gate_switch_width.sh
git commit -m "test(repro): negative integer case items"
```

### Task I0: Reference Zig 0.17.1 comparison (download + probes)

**Files:** none in the repo; artifacts in `/tmp`; report `.superpowers/sdd/2026-11-04-syntax-emission-defects-plan/i0-report.md`.

**Interfaces:** produces the exact Zig behavior/diagnostics that I1 pins.

- [ ] **Step 1: Download and verify**

`curl -fL -o /tmp/zig-0.17.1.tar.xz https://ziglang.org/download/0.17.1/zig-x86_64-linux-0.17.1.tar.xz`
Verify `sha256sum /tmp/zig-0.17.1.tar.xz` = `3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a`; extract to `/tmp/zig-ref-0171` (`tar -xJf … --strip-components=1`); record `/tmp/zig-ref-0171/zig version`.

- [ ] **Step 2: Probe the exact semantics**

Under `/tmp/zig-probes/`, compile and run: `neg_i32` (`var x: i32 = -1; switch (x) { -1 => …, else => … }`), `neg_i64`, `neg_range` (`-5...-1`), `neg_const` (`const NEG: i32 = -1;` prong), `neg_u32_reject` (`var x: u32 = 1; switch (x) { -1 => … }`), `u64_max` (`switch (x: u64) { 0xFFFFFFFFFFFFFFFF => … }`). Capture the exact stderr, exit code, and stdout for accepted cases.

- [ ] **Step 3: Report**

Record the verbatim diagnostics and the accept/reject table. Note: the repo's documented parity baseline is Zig 0.15.2; if 0.17.1 disagrees on a load-bearing point, STOP and present before I1/F.

### Task I1: Investigation — negative case items (read-only)

**Files:** none (report `.superpowers/sdd/2026-11-04-syntax-emission-defects-plan/i1-report.md`).

- [ ] **Step 1:** Trace the parser case-item AST for `-1` (negate/unary node), `lowerAppendSwitchCaseItem` + range expansion, `lowerSwitchCaseItemValue` (`lower.zig:7197`), `lowerSwitchCaseItemConstValue` (`:7284`, the `iv >= 0` rejection), `SwitchCase.value` signedness, the emitter `.switch_br` 32-bit label printing and the 64-bit chain (`891302bf`), and any sema case-item validation.
- [ ] **Step 2:** Decide the signedness representation (keep `SwitchCase.value: u64` bit pattern + condition type at emit, recommended; no LIR layout change) and enumerate edge cases: negative range endpoints, negative enum discriminants, typed vs comptime condition, `else`, duplicates.
- [ ] **Step 3:** Pin the unsigned-condition rejection from I0 (code, exact message, level, rc, emission site). Write the exact fix map (functions/lines).

### Task I3: Survey — enum discriminants and C legality (read-only)

**Files:** none (report `.superpowers/sdd/2026-11-04-syntax-emission-defects-plan/i3-report.md`).

- [ ] **Step 1:** Determine how enum-member values with negative discriminants are stored (`em_items`), whether `@intCast(u64, negative)` is a latent trap today, and what the emitter prints for such case labels.
- [ ] **Step 2:** Verify C legality of negative `case -1:` for OpenWatcom 1.9 and MSVC 6, and the `Z98_I64_C(-1)` / `Z98_U64_C(...)` expansion (`-1i64`/`-1LL`, the `##` paste).
- [ ] **Step 3:** Record `-fsafe` behavior of any new sign path.

### Task F1: Fix — negative integer case items

**Files:**
- Modify: `sf/src/lower.zig` (negate/negative-const resolution, range endpoints, bit pattern)
- Modify: `sf/src/semantic_analyzer.zig` (unsigned-condition negative prong → `error[3062]` `type '<T>' cannot represent integer value '<v>'`, level 0, rc 2, span on the case item)
- Modify: `sf/src/c89_emit.zig` (signed case labels for the 32-bit `switch`; signed/unsigned literal forms for the 64-bit chain)
- Modify: `docs/reference/Language_Spec_Z98.md` §3.1, `sf/docs/tech_docs/08_c89_emission.md`
- Test: the five I2 repros, the existing switch corpus dirs

**Interfaces:** consumes the I1 fix map and the I0-pinned diagnostic (`error[3062]`).

- [ ] **Step 1:** Apply the I1 fix map; keep unsigned conditions rejected with the pinned diagnostic.
- [ ] **Step 2:** All five I2 repros GREEN; signed negative literal/const/range match; unsigned reject is rc 2 / 0 `.c`.
- [ ] **Step 3:** 32-bit unsigned/signed existing switches byte-identical (spot-check corpus dirs); `-fsafe` self-build unaffected.
- [ ] **Step 4: Commit**

```bash
git add sf/src/lower.zig sf/src/semantic_analyzer.zig sf/src/c89_emit.zig
git commit -m "fix(lower): negative integer switch case items"
git add docs/reference/Language_Spec_Z98.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "docs(reference): negative case items"
```

### Task F2: Fix — signed enum backings + negative enum discriminants

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (accept `enum(iN)` signed backings; reject a negative discriminant whose value does not fit an unsigned backing)
- Modify: `sf/src/type_registry.zig` (backing signedness for enum case-label emission; member values already `i64`)
- Modify: `sf/src/lower.zig` (`lowerSwitchCaseItemMemberValue` `@intCast(u64, member.value)` → `@bitCast(u64, member.value)`; negative enum members and negative enum range endpoints)
- Modify: `sf/src/c89_emit.zig` (signed enum case labels for 32-bit; signed literal form for the 64-bit chain, using `typeRegistryIntIsSigned` on the enum backing)
- Modify: `docs/reference/Language_Spec_Z98.md` (enum backings), `sf/docs/tech_docs/08_c89_emission.md`
- Test: new corpus repros + existing enum-switch corpus dirs

**Interfaces:** consumes I3's survey (negative enum storage, C legality, latent trap). Function-local `const` case items stay out of scope (documented limitation).

- [ ] **Step 0: Create the enum repros and confirm RED**

Create `repro/mi_matrix/switch_neg_enum_ok_xmod` (`enum(i32) { A = -1, B = 2 }`, `x = .A`, prong `.A` → `7`), `switch_neg_enum_range_ok_xmod` (negative members used as range endpoints; follow the form of `stdlib_switch_enum_range_xmod`), and `switch_neg_enum_unsigned_backing_reject_xmod` (`enum(u32) { A = -1 }` → rc 2). Today `enum(i32)` is rejected by sema, so the accepted repros are RED and the reject repro is GREEN-for-the-wrong-reason; record it.

- [ ] **Step 1: Sema backing support**

Allow signed integer backings and validate every discriminant against the backing; an unsigned backing with a negative discriminant rejects with the F1-pinned diagnostic family.

- [ ] **Step 2: Lowering**

`@bitCast` the member value (no `-fsafe` trap); resolve negative enum members and negative enum range endpoints.

- [ ] **Step 3: Emitter**

Print signed case labels when the enum backing is signed (`case -1:` 32-bit; `Z98_I64_C(-1)`/signed form in the 64-bit chain); unsigned backings keep the current form.

- [ ] **Step 4: Verify**

All enum repros GREEN; existing enum-switch corpus dirs byte-identical; `-fsafe` self-build has no `zig_cast_checked_u` trap on the enum path; docs updated.

- [ ] **Step 5: Commit**

```bash
git add repro/mi_matrix/switch_neg_enum_ok_xmod repro/mi_matrix/switch_neg_enum_range_ok_xmod repro/mi_matrix/switch_neg_enum_unsigned_backing_reject_xmod
git commit -m "test(repro): negative enum discriminants"
git add sf/src/semantic_analyzer.zig sf/src/type_registry.zig sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "feat(sema): signed enum backings and negative discriminants"
git add docs/reference/Language_Spec_Z98.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "docs(reference): signed enum backings"
```

### Task TC: Initialize all `undefined` locals (Policy 2 — examples only)

Operator ruling: no unsafe Z98. Keep `-fsafe`; explicitly initialize every `var x = undefined` so no poison is emitted and nothing is read before write. No compiler/std/seed change.

**Files:**
- Modify: every `.zig` file under `examples/z98/z9play/` and `examples/z98/z9torr/` containing `= undefined` (471 sites across the top-level modules, `tests/`, and `platform/` — operator ruling m2674 accepted the broader scope), plus a one-line note in each example README.
- Test: both examples' full tier sets (no compiler battery).

**Interfaces:** none new; no signature or behavior change.

- [ ] **Step 1: Inventory**

List every `= undefined` site with its type and whether it is a scalar, a fixed array, or a struct. Group by file. Record the count (must reach 0 at the end).

- [ ] **Step 2: Initialize**

Replace each with an explicit value of the same type: scalars to `0`/`false`; fixed arrays via an explicit fill loop (`for (buf) |*b| b.* = 0;` — the new `|*item|` syntax) or element-by-element; structs by initializing every field explicitly (a helper per struct is acceptable). Do not introduce `@memset`-style builtins if they are not supported; do not use `undefined` anywhere. Do not change any function's behavior: buffers that were fully written before read get a harmless zero fill; anything else is initialized to a value that preserves the existing semantics.

- [ ] **Step 3: Tiers**

Build `/tmp/opt_tc`; run z9play `dsp_test` + `tier_decode`, `tier_audio`, `tier_win9x`, `tier_flac`, `tier_cli`, `tier_tui`; z9torr `tier1_unit`, `tier1`, `tier2`, `tier3_encrypted`, `tier_dht`, `tier_pex`. Expected: all PASS, outputs unchanged (the seed-md5 pin failures are resolved by Task TP before this task's closeout).

- [ ] **Step 4: Verify the emitted C poison**

Emit both examples with the default (`-fsafe`) compiler and grep the emitted example module `.c` files for `zig_poison_fill`. Expected: **0 for source `undefined`**; the remaining fills are compiler-generated call-result temporaries (measured 603 z9play / 789 z9torr, down from 632/868). Operator ruling m2674 (A): those are a separate known item, recorded in the report and Task 4 docs, **not** fixed here (would need an `sf/src` emitter change).

- [ ] **Step 5: Commit**

```bash
git add examples/z98/z9play
git commit -m "refactor(z9play): initialize all locals (no undefined)"
git add examples/z98/z9torr
git commit -m "refactor(z9torr): initialize all locals (no undefined)"
git add examples/z98/z9play/README.md examples/z98/z9torr/README.md
git commit -m "docs(z9play,z9torr): no-undefined policy note"
```

### Task TP: remove rotating seed-md5 pins from the example tests (test infra)

Operator ruling m2674: tests must not depend on a rotating seed md5. Today `tier_flac.sh`, `tier_stream.sh`, and `tier_tui.sh` assert the compiler's md5 against a fixed literal; every seed rotation breaks them for no functional reason.

**Files:**
- Modify: `examples/z98/z9play/tests/tier_flac.sh`, `tier_stream.sh`, `tier_tui.sh` (the `SEED_MD5` assertions and the "seed vXXX" comments/echoes)
- Modify: any other example test found by `grep -rn 'md5sum "\$ZIG"' examples/z98/*/tests/*.sh` with a fixed comparison
- Test: the three scripts + `bash -n`

**Interfaces:** none. No compiler/std/seed change.

- [ ] **Step 1: Survey**

`grep -rn 'SEED_MD5\|md5sum "\$ZIG"' examples/z98/*/tests/*.sh`. Record every fixed compiler-md5 assertion (the three files above; 6 literals).

- [ ] **Step 2: Replace the policy**

When `ZIG` is explicitly provided: print `compiler md5: <md5>` for information and continue; do not assert a fixed value. When the script auto-rebuilds the seed: likewise no fixed-point assertion; assert only that the compiler is executable and the functional tier cases pass. Remove the hard-coded md5 literals and the "seed vXXX / fixed point" wording.

- [ ] **Step 3: Verify non-fragility**

Run the three scripts with a compiler whose md5 differs from the old pin (e.g. `/tmp/def_f2/zig1_5_clean`, the post-F2 build) and confirm each exits 0 on functional results (no md5 failure line). `bash -n` each. `grep` confirms no fixed compiler-md5 literal remains in the example tests.

- [ ] **Step 4: Commit**

```bash
git add examples/z98/z9play/tests/tier_flac.sh examples/z98/z9play/tests/tier_stream.sh examples/z98/z9play/tests/tier_tui.sh
git commit -m "test(examples): stop pinning a rotating seed md5"
```

### Task 3: Gates, full battery, seed v134

**Files:**
- Modify: `scripts/seed/archive_seed.sh` (only if a new std file is added — not expected)
- Modify: `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`, `release/seed/CHANGELOG.md`
- Modify: `docs/sf/QUICK_REF.md` (current seed)
- Test: the full gate set

- [ ] **Step 1: Full battery**

Build from the committed seed and run: corpus (live tally/md5; expect only the new repro dirs to be additive), frozen-1124 `518eca1a…` 0 movers, goldens 5/5, 8 pins (record; if any moved, STOP and present), markers, examples 26/26, `verify_stdlib` + crosscheck, `check_emit_support` 8/8, all compiler gates (including the new `gate_switch_width.sh`).

- [ ] **Step 2: Rotate v134**

`bash scripts/seed/archive_seed.sh /tmp/<dir>/zig1_5_clean /tmp/<dir>/gen release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`; verify lib/manifest/archive/zip/gen counts and the rebuild-from-archive fixed point; truth-up QUICK_REF and the CHANGELOG (each claim verified).

- [ ] **Step 3: Commit**

```bash
git add release/seed/zig1-seed.tgz release/seed/zig1_seed_w9.zip release/seed/CHANGELOG.md docs/sf/QUICK_REF.md
git commit -m "chore(seed): rotate v134 (switch emission fixes)"
```

### Task 4: Docs

**Files:** `sf/docs/tech_docs/08_c89_emission.md`, `docs/sf/QUICK_REF.md` (notes), `examples/torrent_example_defects.md` only if TB produced a real open defect.

- [ ] **Step 1:** Document the emitter rule (no C `switch` on a 64-bit controlling expression; 64-bit conditions lower to an if/else chain) and the TB outcome (fixed defect → defects doc; toolchain-only → a note with the evidence).
- [ ] **Step 2:** Commit:

```bash
git add sf/docs/tech_docs/08_c89_emission.md docs/sf/QUICK_REF.md examples/torrent_example_defects.md
git commit -m "docs(tech): 64-bit switch emission rule and defect-B outcome"
```

---

### Task I-A: Investigation — C carrier width vs declared Z98 width (Critical; read-only)

Final whole-milestone review finding 1: `tempIs64BitInt` tests the declared Z98 width, not the C carrier width, so `u33..u63`/`i33..i63` (8-byte carrier) still emit a 64-bit C `switch` (OpenWatcom `E1078`).

**Files:**
- Read: `sf/src/c89_emit.zig`, `sf/src/type_registry.zig`, `sf/src/emit_support.zig`, `scripts/compiler/gate_switch_width.sh`, `repro/mi_matrix/switch_u64_ok_xmod/`, `repro/mi_matrix/switch_i64_ok_xmod/`
- Write: `.superpowers/sdd/2026-11-04-syntax-emission-defects-plan/i-a-report.md` (report only)
- No repo edits, no commits.

**Interfaces:** none (investigation). The report's helper proposal and call-site table are the input to the post-STOP fix wave.

- [ ] **Step 1: Inventory every width decision in the switch path**

Trace and tabulate every consumer of `typeRegistryIntWidthBits` / `typeKindIntWidthBytes` / `types_items[..].size` that decides "64-bit" or a literal form. Mandatory anchors: `tempIs64BitInt` (`sf/src/c89_emit.zig:765`), `switchCondWidthBits` (`:791`), `nestConsumerWired` (`:4408`), the `.switch_br` dispatch (`~:8535`), `writeSwitchCaseLabel` (`:4835`), `writeIntConstRvalue` (`:4759`, width read at `:4772`), `writeMinSignedIntLiteral` (`:5148`), `satMinMagLitBound`/`satMaxULitBound` (`:5164`/`:5176`). For each: does it need the **declared** width (Z98 semantics, masks/sign bits) or the **C carrier** width (C type/`switch`/literal suffixes)? Record the verdict per site.

- [ ] **Step 2: Pin the canonical carrier model**

`sf/src/type_registry.zig:1210-1234` (arb carrier: 1/2/4/8 bytes), `:1237` `typeRegistryEnumBackingType`, `:1629` `typeKindIntWidthBytes` (returns 0 for arb kinds). Confirm whether `types_items[enum_tid].size` is the backing carrier or must be derived by recursion; do the same for `arb_int_type`/`arb_uint_type`. Propose the exact helper API (e.g. `typeRegistryIntCarrierBytes(reg, tid) u32` and `typeRegistryIntCarrierIs64(reg, tid) bool`), its home file, and whether it must be enum-backing aware.

- [ ] **Step 3: C89 literal legality for 33–63-bit values**

Determine what a 33–63-bit case label / constant must look like on OpenWatcom 1.9 and MSVC 6 (plain decimal vs `Z98_U64_C` / `Z98_I64_C` / `Z98_I64_MIN`); check the macro definitions in `sf/src/emit_support.zig`. State the exact required forms per signedness and width. This is the shared edge with Minor 4 — the fix must use one literal renderer, not a second copy.

- [ ] **Step 4: Repro and gate plan**

Specify the new corpus repros (`u40`, `i40`, `i63`, `enum(u40)`, `enum(i40)`; plus a case value above `2^31`/`2^32` where relevant) and the extension to `scripts/compiler/gate_switch_width.sh`. Confirm its AWK resolves `zT_*_u64` declarations (it should; the current gap is the missing repro, not the matcher). Note that the gate today covers only `u64`/`i64`.

- [ ] **Step 5: Output-stability and shared-root verdict**

State which output bytes can move under the proposed fix: expect none for 32-bit and existing 64-bit switches; only 33–63-bit carriers. Check the 8 pins, frozen-1124 and `-fsafe` self-build implications. Explicitly answer: is this one missing carrier layer (Critical + Minor 4), and are there any other declared-vs-carrier sites outside the switch path that the fix must not silently change?

**Mandatory report contents:** per-site declared-vs-carrier table, exact helper signature/home, required C literal forms, repro+gate list, fix-shape recommendation, byte-stability assessment, and a STOP list.

**STOP and present if:** the helper would require touching files outside the emitter/type registry, any 32-bit or existing 64-bit emission would move, or the carrier model cannot be expressed without a new `Type` field.

---

### Task I-B: Investigation — enum value machinery, case items, and all minors (read-only)

Final whole-milestone review findings 2–8. Operator ruling m2709: **all minors are in scope.** Priority: Important 3 (silent wrong code) and Minor 4 (wide enum macros).

**Files:**
- Read: `sf/src/type_resolver.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/type_registry.zig`, `repro/mi_matrix/switch_neg_*/`, `repro/mi_matrix/switch_i64_ok_xmod/main.zig`, `/tmp/zig-ref-0171` (Zig 0.17.1)
- Write: `.superpowers/sdd/2026-11-04-syntax-emission-defects-plan/i-b-report.md` (report only)
- No repo edits, no commits. Consume `i-a-report.md` for Minor 4; do not duplicate the carrier helper.

**Interfaces:** none (investigation). Report feeds the post-STOP fix wave B.

- [ ] **Step 1: Enum implicit-value overflow (Important 2)**

Prove `enum(i64) { A = 9223372036854775807 }` traps the `-fsafe` compiler via `auto_val = mval + @intCast(i64, 1)` at `sf/src/type_resolver.zig:1512`. Compare with the local guard at `:1760-1764` (`is_signed and mval == max_s`). Probe Zig 0.17.1 for `enum(i64){A=max, B}` and for a signed backing whose implicit successor overflows. Enumerate every other implicit-value/overflow/diagnostic site (including the signed-vs-unsigned overflow message at `:1753`). Recommend the exact guard/diagnostic (mirror the local validator vs a new code) and state the resulting rc/`.c` behavior.

- [ ] **Step 2: Parenthesized negative case item (Important 3)**

Prove `switch (x: i32) { (-1) => ... }` drops the prong via `lowerSwitchCaseItemValue` (`sf/src/lower.zig:7206`). Note that `evalConstI64Full` (`:7323`) and the enum-const walker (`:7343`) already unwrap `paren_expr`. Test `(-1)`, `(- 1)`, `((1))`, parens in range endpoints (`(-1)...(-1)`), bool and unsigned conditions. Decide the minimal fix: a `paren_expr` recursion arm at `:7206` vs routing unrecognized kinds through `evalConstI64Full`. Confirm no change for currently-resolving shapes.

- [ ] **Step 3: Wide enum member macros (Minor 4)**

Confirm `emitEnumType` (`sf/src/c89_emit.zig:1826`) emits unsuffixed decimal macros for both negative (`emitDefineMacroWideNeg`, `:1440`) and positive >32-bit members (`emitDefineMacroWide`, `:1422`). Using I-A's helper/literal forms, list the exact required macro bodies and confirm OWC 1.9/MSVC 6 legality. State that I-A owns the helper and I-B only routes the enum macro emitters through it.

- [ ] **Step 4: Stale repro header (Minor 5)**

`repro/mi_matrix/switch_i64_ok_xmod/main.zig` still says negative case literals are not resolved. Specify the correction (and check the sibling `switch_u64_ok_xmod` header too).

- [ ] **Step 5: Bool + negative (Minor 6)**

`switch (b: bool) { -1 => ... }` is invalid Z98 but is now lowered to `case 18446744073709551615` instead of dropping. Decide: reject cleanly (which code/level/rc) or restore the drop; state the minimal site and whether the spec must document it.

- [ ] **Step 6: Workspace residue (Minor 7)**

List the ignored repo-root `.zig1_*.tmp` files and confirm `lin_bin/` remains untracked by design. Specify the cleanup (delete the tmp files only; no repo edit) and the check that commits contain no scratch files.

- [ ] **Step 7: Docs housekeeping (Minor 8)**

Enumerate and scope: `README.md:494` (`v133` label on the stdlib section), the TC “explicitly initialized” wording, and historical counts in `examples/z98/z9play/NOTES.md`/`README.md`. Decide what is corrected in the fix wave vs left labelled historical.

- [ ] **Step 8: Shared-root verdict**

Answer which of 2/3/4 share a layer, whether the Critical's carrier/literal layer also fixes Minor 4 entirely, and whether anything else in the enum pipeline (sema gates, `enum_value_table` u32, local validation) needs the same treatment.

**Mandatory report contents:** per-finding root cause, intended semantics needing an operator ruling, fix options ranked, repro list, gate additions, and a STOP list.

**STOP and present if:** a fix needs a new diagnostic code, changes intended enum semantics, or cannot be expressed without touching `type_registry.zig` layout.

---

## STOP — mandatory middle review (operator m2709) — COMPLETED (operator m2750)

The STOP was presented and the operator approved the fix-wave scope. Rulings m2750:

- **I3:** iterative; try the shared `ast.zig` helper, but check feasibility inside the same task — if the blast radius widens, use a lowering-local iterative copy instead.
- **I2:** option **(a)** (guard the shared walk, existing validators own the message) plus a code comment documenting the clean option (b) for future adoption.
- **`enum_value_table`:** the adjacent defect is **in scope** (Task 6a).
- **`enum(u64)` above i64 max:** documented limitation **plus a clear diagnostic**.
- **Wide-macro spelling:** untyped for enum macros, typed for arbitrary-width switch labels.
- **Gates:** extend existing gate scripts; do **not** add a new gate script.
- **Fix wave B is split** into 6a (enum), 6b (case-item), 6c (minors).
- **Docs:** rewrite labels/policy only after verification; historical counts stay historical.
- Earlier ruling stands: bool + negative case items reject with `error[3062]`.

### Task 5: Fix wave A — carrier-width switch emission

**Files:**
- Modify: `sf/src/type_registry.zig` (carrier helpers), `sf/src/c89_emit.zig` (`tempIs64BitInt`, `writeSwitchCaseLabel`), `scripts/compiler/gate_switch_width.sh` (repro list + typedef-chain AWK)
- Create: `repro/mi_matrix/switch_u40_ok_xmod/`, `switch_i40_ok_xmod/`, `switch_i63_ok_xmod/`, `switch_enum_u40_ok_xmod/`, `switch_enum_i40_ok_xmod/` (`main.zig`, `expected.txt`, `expected.rc`)
- Test: `gate_switch_width.sh` RED→GREEN; 32-bit and existing 64-bit emitted C unchanged; 8 pins; frozen-1124; `-fsafe` self-build

**Interfaces:**
- Produces `typeRegistryIntCarrierBytes(reg, tid) u32` and `typeRegistryIntCarrierIs64(reg, tid) bool` in `type_registry.zig`: enum-backing aware (recurse through `typeRegistryEnumBackingType`), arbitrary ints use `Type.size`, fixed kinds use `typeKindIntWidthBytes`. `typeRegistryIntWidthBits` remains the **declared** width for masks/sign bits.
- Consumed by `c89_emit.zig` only in this task.

- [ ] **Step 1: Repros + gate RED**

Create the five corpus dirs per I-A §6.1 (`3000000000` for the enum repros isolates the carrier defect from the `enum_value_table` fix in 6a). Extend `gate_switch_width.sh`'s `REPROS` and add the typedef-chain AWK patch from I-A §6.2. Run the gate on the current v134-seed compiler: the five new dirs must be RED (`SW64`), the existing two GREEN.

- [ ] **Step 2: Carrier helpers**

Add `typeRegistryIntCarrierBytes`/`typeRegistryIntCarrierIs64` near `typeRegistryIntByteWidth` (`sf/src/type_registry.zig:1660`), exactly as I-A §4. Do not change `typeRegistryIntWidthBits`, `typeKindIntWidthBytes`, or `Type.size`.

- [ ] **Step 3: Switch predicate**

In `tempIs64BitInt` (`sf/src/c89_emit.zig:765`) replace the declared-width test with `typeRegistryIntCarrierIs64`. This also fixes `nestConsumerWired` (`:4408`) and the `.switch_br` dispatch (`~:8535`).

- [ ] **Step 4: Label routing**

In `writeSwitchCaseLabel` (`:4835`) keep `switchCondWidthBits` as the **declared** width. Add `carrier64 = typeRegistryIntCarrierIs64(...)`. Unsigned with `carrier64` → `writeIntConstRvalue(..., "")`. Signed with `carrier64 and width == 64` → keep the existing width-64 block **verbatim**. Signed with `carrier64 and width < 64` → `writeIntConstRvalue(..., "")`. Leave the declared `width < 64` masking path for carrier ≤ 4 unchanged. Do not change `writeIntConstRvalue`, `writeMinSignedIntLiteral`, or the `sat*` helpers.

- [ ] **Step 5: Verify**

Gate GREEN (all seven repros lower to if/else). 32-bit and existing `u64`/`i64` switch dumps byte-identical to the v134-seed compiler. 8 pins 8/8; frozen-1124 `518eca1a…` 0 movers; `-fsafe` self-build clean. Record the commands/outputs in the task report.

- [ ] **Step 6: Commit**

```bash
git add sf/src/type_registry.zig sf/src/c89_emit.zig scripts/compiler/gate_switch_width.sh repro/mi_matrix/switch_u40_ok_xmod repro/mi_matrix/switch_i40_ok_xmod repro/mi_matrix/switch_i63_ok_xmod repro/mi_matrix/switch_enum_u40_ok_xmod repro/mi_matrix/switch_enum_i40_ok_xmod
git commit -m "fix(c89_emit): carrier-width switch lowering for 33-63-bit integers"
```

### Task 6a: Fix wave B1 — enum value machinery

**Files:**
- Modify: `sf/src/type_resolver.zig` (shared-walk guard + clear diagnostic), `sf/src/lower.zig` (four enum-literal sites), `sf/src/semantic_analyzer.zig` (clear diagnostic as needed), `scripts/compiler/gate_lower_depth.sh` (extend with the safe enum-max and runtime cases)
- Create: `repro/mi_matrix/enum_i64_max_ok_xmod/`, `enum_u63_max_ok_xmod/`, `enum_i64_max_implicit_reject_xmod/`, `enum_u63_max_implicit_reject_xmod/`, `enum_u64_max_reject_xmod/`, `switch_enum_u40_wide_ok_xmod/`, `switch_enum_u40_wide_qualified_ok_xmod/`

**Interfaces:**
- Consumes Task 5's carrier helper only indirectly (no change to the literal policy).
- Produces the observed semantics: single `enum(i64)`/`enum(u63)` max is valid; an implicit successor after max is a clean `error[3000]`; unsigned enum literals above u32 resolve exactly.

- [ ] **Step 1: Repros RED**

Create the seven dirs per I-B §10 (expected `.txt`/`.rc`; the two reject dirs also assert no secondary `error[3062]`). Include a `-fsafe` compiler run (I-B §1 recipe) for the two valid-max dirs. Confirm RED on the v134-seed compiler: the safe compiler traps on the valid-max dirs; the wide unsigned enum prints/returns the truncated value.

- [ ] **Step 2: I2 option (a) + comment**

At `sf/src/type_resolver.zig:1512`, guard the increment at `i64` max (`auto_val = mval`). In the strict duplicate loop (`:1493`), skip the duplicate report when the current member is **implicit** (`mnode.child_1 == 0`) and `mval == i64 max`, so the existing validators report the implicit-successor overflow. Add a comment above the guard stating the clean future option: the shared walk returns `fail_kind = 3` and reports the overflow itself (single owner, no duplicate special case; would need backing info plumbed in). Do not add a new diagnostic code.

- [ ] **Step 3: Clear `enum(u64)` > i64 max diagnostic**

For an unsigned backing whose stored member value is negative because the source value exceeded i64 max, report `error[3000]` with an explicit message instead of `type 'u64' cannot represent integer value '-1'` (e.g. `enum member value exceeds the supported enum value range (values above 9223372036854775807 require u64 enum storage, not supported yet)`). Distinguish a genuine negative initializer (`negate`/negative literal → keep `error[3062]`) from a positive expression that wrapped the i64 store (→ the clear message). Apply consistently at the module gate (`semantic_analyzer.zig:2395-2427`) and the local validator (`type_resolver.zig:1721-1755`). If the source value cannot be classified without a larger u64 evaluator change, STOP and report rather than improvise.

- [ ] **Step 4: `enum_value_table` exact values**

At `sf/src/lower.zig:5248` and `:8718`, and in `lowerSwitchCaseItemValue`'s `enum_literal` (`:7218-7238`) and `field_access` (`:7246-7269`) arms, drop the `typeRegistryIntIsSigned(...)` condition: resolve the member by name whenever the expected/condition type is an enum. Keep the u32 table for tagged-union tag ordinals and non-enum contexts. `const_init_eval.zig:335` is already signedness-agnostic; do not change it.

- [ ] **Step 5: Gates (extend existing scripts)**

In `gate_lower_depth.sh`, add a case that builds a `-fsafe` compiler from the same emission (I-B §1 recipe) and runs the two valid-max repros (rc 0) plus the two reject repros (rc 2, exact `error[3000]`, no secondary `3062`); add runtime cases for the two wide unsigned enum dirs (exact stdout). Do **not** touch `gate_warn_clean.sh` here: the wide-macro compile gate belongs to Task 6c together with the macro fix. No new gate script.

- [ ] **Step 6: Verify + commit**

Existing enum/switch output stable (spot-check plus the 66-run set where feasible); 8 pins 8/8; `-fsafe` self-build clean; `git diff --check`. Commit:

```bash
git add sf/src/type_resolver.zig sf/src/lower.zig sf/src/semantic_analyzer.zig scripts/compiler/gate_lower_depth.sh repro/mi_matrix/enum_i64_max_ok_xmod repro/mi_matrix/enum_u63_max_ok_xmod repro/mi_matrix/enum_i64_max_implicit_reject_xmod repro/mi_matrix/enum_u63_max_implicit_reject_xmod repro/mi_matrix/enum_u64_max_reject_xmod repro/mi_matrix/switch_enum_u40_wide_ok_xmod repro/mi_matrix/switch_enum_u40_wide_qualified_ok_xmod
git commit -m "fix(enum): guard implicit overflow, exact wide enum values, clearer u64 limit"
```

### Task 6b: Fix wave B2 — parenthesized case items and bool-negative

**Files:**
- Modify: `sf/src/ast.zig` (shared iterative helper, preferred), `sf/src/semantic_analyzer.zig` (delegation + bool-negative gate), `sf/src/lower.zig` (case-item resolver + range endpoints), `scripts/compiler/gate_lower_depth.sh` (runtime cases)
- Create: `repro/mi_matrix/switch_neg_paren_i32_ok_xmod/`, `switch_neg_paren_space_ok_xmod/`, `switch_paren_double_ok_xmod/`, `switch_neg_paren_range_ok_xmod/`, `switch_paren_named_const_ok_xmod/`, `switch_bool_paren_ok_xmod/`, `switch_u32_paren_ok_xmod/`, `switch_u32_paren_neg_reject_xmod/`, `switch_bool_neg_reject_xmod/`, `switch_bool_paren_neg_reject_xmod/`

- [ ] **Step 1: Repros RED**

Create the ten dirs per I-B §10. Confirm the parenthesized cases currently drop (only `default:`) and the bool-negative case emits the invalid label.

- [ ] **Step 2: Iterative paren helper**

Preferred: add `astUnwrapParensBounded(store, idx, max_depth)` to `sf/src/ast.zig` (the iterative loop from `semaUnwrapParensBounded`, `semantic_analyzer.zig:3954`), make `semaUnwrapParensBounded` delegate, and call it from `lowerSwitchCaseItemValue` (top) and `lowerAppendSwitchCaseItem`'s range endpoints. **Feasibility check in the same step:** if the sema delegation or `ast.zig` placement has a wider blast radius than expected (build/import churn, call-site changes), use a lowering-local iterative helper instead and record the decision. No recursion.

- [ ] **Step 3: Bool + negative reject**

Extend the sema case-item negative check (`semantic_analyzer.zig:4999` gate / `semanticAnalyzerReportUnsignedNegativeCaseItem`) to `bool_type`. Keep `true`/`false` and integer `0`/`1` accepted. Reject only negative values with `error[3062]`, level 0, message `type 'bool' cannot represent integer value '-1'`, rc 2, 0 `.c`, span on the case item. Parenthesized bool-negatives are covered by Step 2.

- [ ] **Step 4: Gates + verify**

Extend `gate_lower_depth.sh` with the new runtime cases (exact stdout/rc). Existing switch output stable; 8 pins 8/8; `-fsafe` self-build clean; `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add sf/src/ast.zig sf/src/semantic_analyzer.zig sf/src/lower.zig scripts/compiler/gate_lower_depth.sh repro/mi_matrix/switch_neg_paren_i32_ok_xmod repro/mi_matrix/switch_neg_paren_space_ok_xmod repro/mi_matrix/switch_paren_double_ok_xmod repro/mi_matrix/switch_neg_paren_range_ok_xmod repro/mi_matrix/switch_paren_named_const_ok_xmod repro/mi_matrix/switch_bool_paren_ok_xmod repro/mi_matrix/switch_u32_paren_ok_xmod repro/mi_matrix/switch_u32_paren_neg_reject_xmod repro/mi_matrix/switch_bool_neg_reject_xmod repro/mi_matrix/switch_bool_paren_neg_reject_xmod
git commit -m "fix(lower): iterative paren unwrap; reject negative bool case items"
```

### Task 6c: Fix wave B3 — enum macro literals and minors

**Files:**
- Modify: `sf/src/c89_emit.zig` (wide enum macros through the untyped literal renderer), `scripts/compiler/gate_warn_clean.sh` (wide-macro compile gate), `repro/mi_matrix/switch_i64_ok_xmod/main.zig` (stale header), `README.md`, `examples/z98/z9play/README.md`, `examples/z98/z9torr/README.md`, `docs/reference/Language_Spec_Z98.md`, `sf/docs/tech_docs/08_c89_emission.md`, `docs/sf/QUICK_REF.md`, `examples/torrent_example_defects.md` (new open entry)
- Create: `repro/mi_matrix/enum_wide_macro_i64_ok_xmod/`, `enum_wide_macro_i40_ok_xmod/`, `enum_wide_macro_u40_ok_xmod/`, `enum_wide_macro_i63_ok_xmod/`, `enum_wide_macro_i64_min_ok_xmod/`

**Interfaces:** consumes the Task 5 literal policy; adds an untyped mode (shared thresholds, no cast wrapper) for enum macro bodies; the typed form stays for arbitrary-width switch labels.

- [ ] **Step 1: Wide enum macros**

Create the five wide-macro fixtures per I-B §10 items 13–17; each must *use* the members (print/compare) so the macros expand in the emitted C. Add them to `gate_warn_clean.sh` scope (c) and confirm the gate is **RED** on the current unsuffixed macros. Then give the literal renderer an untyped mode (or a small wrapper sharing the thresholds) and route `emitDefineMacroWide`/`emitDefineMacroWideNeg` (`sf/src/c89_emit.zig:1422/1440`) through it. Preserve the existing small/i32-min/i64-min forms. Required bodies per I-B §4.2 (`(-Z98_I64_C(n))`, `Z98_U64_C(n)`, `u` suffix, `Z98_I64_MIN`). Confirm `gate_warn_clean.sh` **GREEN** after the fix.

- [ ] **Step 2: Minor 5**

Correct `repro/mi_matrix/switch_i64_ok_xmod/main.zig:7` (negative case literals now resolve, including parenthesized forms); sibling header needs no change.

- [ ] **Step 3: Minor 7**

Delete the eight ignored repo-root `.zig1_*.tmp` files; confirm `lin_bin/` stays untracked and no scratch file is tracked or in history. No repo edit/commit for this step.

- [ ] **Step 4: Minor 8 docs (verified-only)**

`README.md:494` v133 label → v134. Correct the TC “explicitly initialized” wording in both example READMEs (locals explicit; module statics BSS). Relabel only stale “current” references; leave measured historical counts. Document: bool case items (accept `true`/`false`/0/1, reject negatives with `error[3062]`), the `enum(u64)` > i64 max limitation, and the switch/negative rules in the spec/tech doc. Add an open defects entry (next slot D13) for the `enum(u64)` storage limitation. Do not rewrite the example-matrix 26/26 count until a verified run.

- [ ] **Step 5: Commit**

```bash
git add sf/src/c89_emit.zig scripts/compiler/gate_warn_clean.sh repro/mi_matrix/enum_wide_macro_i64_ok_xmod repro/mi_matrix/enum_wide_macro_i40_ok_xmod repro/mi_matrix/enum_wide_macro_u40_ok_xmod repro/mi_matrix/enum_wide_macro_i63_ok_xmod repro/mi_matrix/enum_wide_macro_i64_min_ok_xmod
git commit -m "fix(c89_emit): portable wide enum macros"
git add README.md examples/z98/z9play/README.md examples/z98/z9torr/README.md docs/reference/Language_Spec_Z98.md sf/docs/tech_docs/08_c89_emission.md docs/sf/QUICK_REF.md examples/torrent_example_defects.md repro/mi_matrix/switch_i64_ok_xmod/main.zig
git commit -m "docs: enum limits, bool case items, and minor truth-ups"
```

### Task 7: Gates, full battery, seed v135

**Files:** `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`, `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md`, `README.md` (current seed/measurements)

- [ ] **Step 1: Full battery**

Build from the v134 seed (expect a new F_new), then: corpus live (expect only the new repro dirs additive), frozen-1124 `518eca1a…` 0 movers, goldens 5/5, 8 pins (record; STOP if any moved), markers (record; if moved, STOP and present with the cause), examples 26/26, `verify_stdlib` + crosscheck, `check_emit_support` 8/8, and all compiler gates (including the extended `gate_switch_width.sh`, `gate_lower_depth.sh`, `gate_warn_clean.sh`).

- [ ] **Step 2: Rotate v135**

`bash scripts/seed/archive_seed.sh <bin> <gen> release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`; verify lib/manifest/archive/zip/gen counts and the rebuild-from-archive fixed point; truth-up QUICK_REF/README/CHANGELOG (each claim verified).

- [ ] **Step 3: Commit**

```bash
git add release/seed/zig1-seed.tgz release/seed/zig1_seed_w9.zip release/seed/CHANGELOG.md docs/sf/QUICK_REF.md README.md
git commit -m "chore(seed): rotate v135 (syntax-emission defect fixes)"
```

---

## Explicit non-goals

- No example-side workaround for either defect (e.g. casting the z9torr seconds value) — the compiler must accept legal Z98 and emit portable C.
- No speculative fix for defect B before TB localises it.
- No changes to the examples' syntax modernization work.
