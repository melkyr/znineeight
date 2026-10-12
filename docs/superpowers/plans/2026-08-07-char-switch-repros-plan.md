# char_literal Switch-Case + opt_slice Null Payload Repro Battery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 15 defensive repros (12 char_literal switch-case + 3 opt_slice null-payload) under `repro/mi_matrix/`, each verified against the current zig1, documenting pre-fix symptoms in `NOTES.md`, and updating the corpus manifest and QUICK_REF baseline.

**Architecture:** Repros-only plan (NO compiler source changes). Two batteries: Battery A exercises the char_literal switch-case-label bug (both lowerer case-collection gaps: `lower.zig:3183` expr-switch, `:3920` stmt-switch — char_literal hits `else { continue; }` → case dropped). Battery B exercises the opt_slice null-payload temp-type bug (null payload temp emitted as `int`, valid for `?*T`, wrong for `?[]T`). Every pattern validated against the zig0 oracle (rc=0) before this plan was written.

**Tech Stack:** Z98 repros, zig1 (`sf/build/out_release/zig1`), gcc -m32 C89, zig0 oracle (`sf/build/zig0`).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET section is MANDATORY reading before any build/compile/run. It has the exact verified commands. Copy them; do not improvise flags.
- **Repro location:** `repro/mi_matrix/<name>/`. Same-module = `main.zig` only. Cross-module = `main.zig` + `lib.zig`.
- **Compiler under test:** `sf/build/out_release/zig1` (build with `bash sf/scripts/build_release.sh`; gate on `=== [release] Done: sf/build/out_release/zig1 ===`). Oracle: `sf/build/zig0`.
- **Compile+run recipe (VERIFIED):** `sf/build/out_release/zig1 --dump-c89 <FILE> > /tmp/x.c 2>/tmp/x.err; gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x; /tmp/x`. For multi-module: `--dump-c89 --output-dir DIR`, then `gcc -m32 ... -c *.c` inside DIR, link `.o` files.
- **Output:** repros print distinctive integers via `extern fn __bootstrap_print_int(n: i32) void;`. The runtime output IS the gate.
- **Pre-fix expected symptom (Battery A):** emitted C has `switch(c) { default: goto ...; }` with NO `case` labels (char cases dropped) → repro prints the WRONG value. Post-fix (future plan): `case 'a': ...` labels present → correct value.
- **Pre-fix expected symptom (Battery B):** gcc per-file `-c` rc=0 but 2 `-Wint-conversion` warnings on the null-payload temp. Gate = rc=0.
- **zig0 oracle validation:** every repro's source pattern must compile under `sf/build/zig0` (rc=0). Oracle is the reference for valid Z98.
- **Corpus accounting:** Battery A repros are classified FAIL (runtime gap: compiles, runs rc=0, prints wrong value). Battery B repros are OK-by-gate (gcc warning only) but latent/type-incorrect, tracked separately — mirroring the existing `opt_slice_null_return` convention.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; edit bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **Compiler source files (`sf/src/*.zig`) are UNTOUCHED by this plan.** If a repro reveals a compiler bug that needs a fix, that is a FOLLOW-UP plan — do not fix here.
- **The plan is the ONLY authority.** If the plan says do A, do A. If you believe X/Y is better, STOP and present to the operator. On any issue, STOP.

---

### Task 1: Battery A1-A4 — Basic stmt-switch repros (gap `lower.zig:3920`)

**Files:**
- Create: `repro/mi_matrix/switch_char_single/main.zig`, `repro/mi_matrix/switch_char_single/NOTES.md`
- Create: `repro/mi_matrix/switch_char_multi/main.zig`, `repro/mi_matrix/switch_char_multi/NOTES.md`
- Create: `repro/mi_matrix/switch_char_nodefault/main.zig`, `repro/mi_matrix/switch_char_nodefault/NOTES.md`
- Create: `repro/mi_matrix/switch_char_mixed_kinds/main.zig`, `repro/mi_matrix/switch_char_mixed_kinds/NOTES.md`

**Interfaces:**
- Consumes: `extern fn __bootstrap_print_int(n: i32) void;` (declared at top of each `main.zig`).
- Produces: 4 repro dirs. Each compiles+links+runs with zig1 (gcc rc=0) but prints the WRONG value pre-fix.

**Context (from I-char-literal-gaps-report):** char_literal is ONLY broken for switch cases. Both case-collection loops check `int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` — char_literal (kind 13) is dropped. Stmt-switch site: `lower.zig:3907-3921` (the `else { continue; }` at `:3920`).

- [ ] **Step 1: Write `switch_char_single/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 0);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
        else => r = @intCast(u8, 0),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, classify('a')));
    __bootstrap_print_int(@intCast(i32, classify('b')));
    __bootstrap_print_int(@intCast(i32, classify('z')));
}
```

Expected runtime pre-fix: `000` (all char cases dropped → else always taken). Expected post-fix: `120`.

- [ ] **Step 2: Write `switch_char_multi/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 0);
    switch (c) {
        'a', 'b' => r = @intCast(u8, 1),
        'c' => r = @intCast(u8, 2),
        else => r = @intCast(u8, 0),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, classify('a')));
    __bootstrap_print_int(@intCast(i32, classify('b')));
    __bootstrap_print_int(@intCast(i32, classify('c')));
    __bootstrap_print_int(@intCast(i32, classify('q')));
}
```

Expected runtime pre-fix: `0000`. Expected post-fix: `1120`. Tests the multi-value prong `'a', 'b' =>`.

- [ ] **Step 3: Write `switch_char_nodefault/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 9);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, classify('a')));
    __bootstrap_print_int(@intCast(i32, classify('q')));
}
```

Expected runtime pre-fix: `99` (no default; char cases dropped → r stays 9). Expected post-fix: `19`. Tests no-else switch — unmatched char falls through, no crash.

- [ ] **Step 4: Write `switch_char_mixed_kinds/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 0);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        98 => r = @intCast(u8, 2),
        else => r = @intCast(u8, 0),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, classify('a')));
    __bootstrap_print_int(@intCast(i32, classify('b')));
    __bootstrap_print_int(@intCast(i32, classify('q')));
}
```

Expected runtime pre-fix: `020` (VERIFIED — the INT case `98` DOES work: `'b'`→2; the CHAR case `'a'` is dropped: `'a'`→else→0; `'q'`→0). Expected post-fix: `120`. Note: `'a'`==97 ≠ 98, so no duplicate C labels. This is the key discriminating repro — it proves the bug is char-specific (int cases work, char cases drop) within one switch.

- [ ] **Step 5: Verify each repro with the QUICK_REF recipe**

For each of the 4 repros (single, multi, nodefault, mixed_kinds):

```bash
mkdir -p /tmp/t1r && rm -rf /tmp/t1r/*
sf/build/out_release/zig1 --dump-c89 repro/mi_matrix/<name>/main.zig > /tmp/t1r/<name>.c 2>/tmp/t1r/<name>.err
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/t1r/<name>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/t1r/<name>
/tmp/t1r/<name>
```

Expected: dump rc=0, gcc rc=0, run rc=0. Capture the runtime output.
Assert: emitted C (grep `/tmp/t1r/<name>.c`) contains `switch (` and NO `case ` labels (pre-fix symptom).
Assert: run output matches the pre-fix expectation above (or the recorded actual for mixed_kinds).
Also verify oracle: `sf/build/zig0 -o /tmp/t1r/<name>_o.c repro/mi_matrix/<name>/main.zig` → rc=0.

- [ ] **Step 6: Write the 4 `NOTES.md` files**

Each `NOTES.md` documents: what it tests, the defect site (`lower.zig:3920` stmt-switch `else { continue; }` drops char_literal), the pre-fix emitted-C symptom (no `case` labels), the pre-fix runtime output, the expected post-fix output, oracle verification (zig0 rc=0), and classification (FAIL — runtime gap until fixed). Follow the format of `repro/mi_matrix/xmod_pub_const_global/NOTES.md`.

- [ ] **Step 7: Commit**

```bash
git add repro/mi_matrix/switch_char_single repro/mi_matrix/switch_char_multi \
        repro/mi_matrix/switch_char_nodefault repro/mi_matrix/switch_char_mixed_kinds
git commit -m "repro: char_literal stmt-switch case labels dropped (single/multi/nodefault/mixed)"
```

**Gate:** all 4 dump rc=0, gcc rc=0, run rc=0, emitted C has no `case` labels, runtime output matches pre-fix expectation, zig0 oracle rc=0. All 4 dirs committed.

---

### Task 2: Battery A5-A8 — expr-switch + compound repros

**Files:**
- Create: `repro/mi_matrix/switch_char_expr/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/switch_char_while/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/switch_char_labeled/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/switch_char_nested/main.zig`, `NOTES.md`

**Interfaces:**
- Consumes: `extern fn __bootstrap_print_int(n: i32) void;`
- Produces: 4 repro dirs. A5 covers the expr-switch gap (`lower.zig:3183`). A6-A8 cover compound patterns (while-break, labeled-break, nested) through the stmt-switch gap (`:3920`).

**Context:** A5 `switch_char_expr` uses `return switch (c) { ... }` — the EXPR-switch path, gap at `lower.zig:3170-3184` (`else { continue; }` at `:3183`).

- [ ] **Step 1: Write `switch_char_expr/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn score(c: u8) i32 {
    return switch (c) {
        'a' => @intCast(i32, 1),
        'b' => @intCast(i32, 2),
        else => @intCast(i32, 0),
    };
}
pub fn main() void {
    __bootstrap_print_int(score('a'));
    __bootstrap_print_int(score('b'));
    __bootstrap_print_int(score('q'));
}
```

Expected runtime pre-fix: `000`. Expected post-fix: `120`.

- [ ] **Step 2: Write `switch_char_while/main.zig`**

Use an ITERATION-bounded loop (the loop condition must NOT depend on the switch result — pre-fix the char prong is dead so a count-dependent condition would loop forever). Validated against the zig0 oracle (rc=0; oracle output `1`; zig1 pre-fix output `0`):

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn run() i32 {
    var count: i32 = 0;
    var c: u8 = 'a';
    var i: i32 = 0;
    while (i < @intCast(i32, 3)) {
        switch (c) {
            'a' => count = count + @intCast(i32, 1),
            else => {},
        }
        c = c + @intCast(u8, 1);
        i = i + @intCast(i32, 1);
    }
    return count;
}
pub fn main() void {
    __bootstrap_print_int(run());
}
```

Expected runtime pre-fix: `0` (char case dropped → count stays 0 → prints 0). Expected post-fix: `1` (only c='a' at iteration 0 increments count → prints 1). Bounded by `i < 3` so it terminates pre-fix (no hang).

- [ ] **Step 3: Write `switch_char_labeled/main.zig`**

Validated against the zig0 oracle (rc=0; oracle output `1`; zig1 pre-fix output `0`):

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn run() i32 {
    var count: i32 = 0;
    var c: u8 = 'a';
    var guard: i32 = 0;
    game_loop: while (true) {
        guard = guard + @intCast(i32, 1);
        if (guard > @intCast(i32, 100)) {
            break :game_loop;
        }
        switch (c) {
            'q' => break :game_loop,
            'a' => count = count + @intCast(i32, 1),
            else => {},
        }
        c = c + @intCast(u8, 1);
    }
    return count;
}
pub fn main() void {
    __bootstrap_print_int(run());
}
```

Expected pre-fix: `0` (labeled break on 'q' never fires; guard-break at 100 terminates; count never increments → prints 0). Expected post-fix: `1` (c='a' at iteration 0 increments count to 1; c advances past 'a'; 'q' break fires at c='q' before guard-100 → count=1). Document both.

- [ ] **Step 4: Write `switch_char_nested/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
fn nested(outer: u8, inner: u8) i32 {
    var r: i32 = 0;
    switch (outer) {
        'a' => {
            switch (inner) {
                'x' => r = @intCast(i32, 1),
                else => r = @intCast(i32, 0),
            }
        },
        else => r = @intCast(i32, 9),
    }
    return r;
}
pub fn main() void {
    __bootstrap_print_int(nested('a', 'x'));
    __bootstrap_print_int(nested('a', 'y'));
    __bootstrap_print_int(nested('z', 'x'));
}
```

Expected runtime pre-fix: `999` (outer switch 'a' case dropped → else r=9; inner never reached). Expected post-fix: `109`.

- [ ] **Step 5: Verify each repro (QUICK_REF recipe)**

Same recipe as Task 1 Step 5. For each: dump rc=0, gcc rc=0, run rc=0 (must NOT hang — verify with `timeout 5 /tmp/.../name`), emitted C has no `case` labels, zig0 oracle rc=0. Record actual pre-fix output.

- [ ] **Step 6: Write the 4 `NOTES.md` files**

Document the rework decision for `switch_char_while` and `switch_char_labeled` (iteration-bounded loops to avoid pre-fix infinite hang) in their NOTES.md. Include the exact pre-fix and expected post-fix outputs.

- [ ] **Step 7: Commit**

```bash
git add repro/mi_matrix/switch_char_expr repro/mi_matrix/switch_char_while \
        repro/mi_matrix/switch_char_labeled repro/mi_matrix/switch_char_nested
git commit -m "repro: char_literal expr-switch + compound switch patterns (expr/while/labeled/nested)"
```

**Gate:** all 4 dump rc=0, gcc rc=0, run rc=0 within timeout (no hang), emitted C no `case` labels, zig0 oracle rc=0, runtime output matches pre-fix expectation, NOTES.md documents the bounded-loop rework rationale. All 4 dirs committed.

---

### Task 3: Battery A9-A12 — Cross-module repros (both gaps)

**Files:**
- Create: `repro/mi_matrix/switch_char_xmod/main.zig`, `switch_char_xmod/lib.zig`, `NOTES.md`
- Create: `repro/mi_matrix/switch_char_xmod_expr/main.zig`, `switch_char_xmod_expr/lib.zig`, `NOTES.md`
- Create: `repro/mi_matrix/switch_char_xmod_while/main.zig`, `switch_char_xmod_while/lib.zig`, `NOTES.md`
- Create: `repro/mi_matrix/switch_char_xmod_nodefault/main.zig`, `switch_char_xmod_nodefault/lib.zig`, `NOTES.md`

**Interfaces:**
- Consumes: `extern fn __bootstrap_print_int(n: i32) void;`, multi-module build recipe (`--dump-c89 --output-dir DIR`, gcc inside DIR).
- Produces: 4 two-file repro dirs (module fn with char switch called from main). Covers BOTH gaps (`:3183` expr + `:3920` stmt) across a module boundary — verifies the switch works when the switch sits in a non-root module.

**Context:** Cross-module char switches: the bug is in the lowerer's per-function switch case collection, so it manifests identically in any module. The cross-module variants prove module boundary doesn't mask or worsen it, and validate the emitted C for both `.c` files is gcc-clean (only missing case labels).

- [ ] **Step 1: Write `switch_char_xmod/lib.zig` + `main.zig`**

```zig
// lib.zig
pub fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 0);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
        else => r = @intCast(u8, 0),
    }
    return r;
}
```

```zig
// main.zig
extern fn __bootstrap_print_int(n: i32) void;
const lib = @import("lib.zig");
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, lib.classify('a')));
    __bootstrap_print_int(@intCast(i32, lib.classify('b')));
    __bootstrap_print_int(@intCast(i32, lib.classify('z')));
}
```

Expected runtime pre-fix: `000`. Expected post-fix: `120`.

- [ ] **Step 2: Write `switch_char_xmod_expr/lib.zig` + `main.zig`**

```zig
// lib.zig
pub fn score(c: u8) i32 {
    return switch (c) {
        'a' => @intCast(i32, 1),
        'b' => @intCast(i32, 2),
        else => @intCast(i32, 0),
    };
}
```

```zig
// main.zig
extern fn __bootstrap_print_int(n: i32) void;
const lib = @import("lib.zig");
pub fn main() void {
    __bootstrap_print_int(lib.score('a'));
    __bootstrap_print_int(lib.score('b'));
    __bootstrap_print_int(lib.score('q'));
}
```

Expected runtime pre-fix: `000`. Expected post-fix: `120`.

- [ ] **Step 3: Write `switch_char_xmod_while/lib.zig` + `main.zig`**

```zig
// lib.zig
pub fn run() i32 {
    var count: i32 = 0;
    var c: u8 = 'a';
    var i: i32 = 0;
    while (i < @intCast(i32, 3)) {
        switch (c) {
            'a' => count = count + @intCast(i32, 1),
            else => {},
        }
        c = c + @intCast(u8, 1);
        i = i + @intCast(i32, 1);
    }
    return count;
}
```

```zig
// main.zig
extern fn __bootstrap_print_int(n: i32) void;
const lib = @import("lib.zig");
pub fn main() void {
    __bootstrap_print_int(lib.run());
}
```

Expected runtime pre-fix: `0`. Expected post-fix: `1` (only c='a' at iteration 0 increments count; bounded by `i < 3` so it terminates pre-fix — the loop condition must NOT depend on the switch result, which would hang pre-fix). Validated against zig0 oracle (rc=0, output `1`).

- [ ] **Step 4: Write `switch_char_xmod_nodefault/lib.zig` + `main.zig`**

```zig
// lib.zig
pub fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 9);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
    }
    return r;
}
```

```zig
// main.zig
extern fn __bootstrap_print_int(n: i32) void;
const lib = @import("lib.zig");
pub fn main() void {
    __bootstrap_print_int(@intCast(i32, lib.classify('a')));
    __bootstrap_print_int(@intCast(i32, lib.classify('q')));
}
```

Expected runtime pre-fix: `99`. Expected post-fix: `19`.

- [ ] **Step 5: Verify each cross-module repro (multi-module QUICK_REF recipe)**

```bash
mkdir -p /tmp/t3r/<name> && rm -rf /tmp/t3r/<name>/*
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/t3r/<name> repro/mi_matrix/<name>/main.zig
cd /tmp/t3r/<name>
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
timeout 5 ./prog
```

Expected: dump rc=0, per-file gcc rc=0 (both `.c` files), link rc=0, run rc=0 (no hang). Assert: emitted C (grep `*.c`) has NO `case ` labels. Assert run output matches pre-fix expectation. Oracle: `sf/build/zig0 -o /tmp/t3r/<name>/main_o.c repro/mi_matrix/<name>/main.zig` → rc=0 (zig0 supports multi-module emit).

- [ ] **Step 6: Write the 4 `NOTES.md` files**

Document: what it tests, both defect sites (`lower.zig:3183`/`:3920`), pre-fix symptom (no `case` labels in the lib module's `.c`), pre-fix runtime output, expected post-fix output, oracle verification, classification (FAIL — runtime gap until fixed).

- [ ] **Step 7: Commit**

```bash
git add repro/mi_matrix/switch_char_xmod repro/mi_matrix/switch_char_xmod_expr \
        repro/mi_matrix/switch_char_xmod_while repro/mi_matrix/switch_char_xmod_nodefault
git commit -m "repro: cross-module char_literal switch cases (simple/expr/while/nodefault)"
```

**Gate:** all 4 dump rc=0, per-file gcc rc=0, link rc=0, run rc=0 (no hang), emitted C no `case` labels, runtime matches pre-fix expectation, zig0 oracle rc=0. All 4 dirs committed.

---

### Task 4: Battery B1-B3 — opt_slice null-payload repros

**Files:**
- Create: `repro/mi_matrix/opt_slice_null/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/opt_slice_null_xmod/main.zig`, `opt_slice_null_xmod/lib.zig`, `NOTES.md`
- Create: `repro/mi_matrix/opt_slice_null_multi/main.zig`, `NOTES.md`

**Interfaces:**
- Consumes: `extern fn __bootstrap_print_int(n: i32) void;`
- Produces: 3 repro dirs. OK-by-gate (gcc rc=0, `-Wint-conversion` warnings on null-payload temp), latent/type-incorrect. NOT counted as FAIL — tracked separately like the existing `opt_slice_null_return` guard.

**Context:** `catch return null` in a `?[]T` function. The null-construction lower emits a scalar `int` temp for the payload (`zT_3 = NULL; zT_4.has_value = 0;`) regardless of payload type — valid for `?*T`, wrong for `?[]T` (payload is a slice struct). gcc `-Wint-conversion` warning only.

- [ ] **Step 1: Write `opt_slice_null/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
const Point = struct { x: i32, y: i32 };
fn fail() !void {
    return error.Fail;
}
fn findPath() ?[]Point {
    _ = fail() catch return null;
    return null;
}
pub fn main() void {
    var p = findPath();
    if (p == null) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
```

Expected runtime: `1` (pre-fix AND post-fix — the null payload is never read when has_value=0). Gate is gcc rc=0 + warnings present.

- [ ] **Step 2: Write `opt_slice_null_xmod/lib.zig` + `main.zig`**

```zig
// lib.zig
const Path = struct { x: i32, y: i32 };
fn fail() !void {
    return error.Fail;
}
pub fn findPath() ?[]Path {
    _ = fail() catch return null;
    return null;
}
```

```zig
// main.zig
extern fn __bootstrap_print_int(n: i32) void;
const lib = @import("lib.zig");
pub fn main() void {
    var p = lib.findPath();
    if (p == null) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
```

Expected runtime: `1`. Same gate.

- [ ] **Step 3: Write `opt_slice_null_multi/main.zig`**

```zig
extern fn __bootstrap_print_int(n: i32) void;
const Point = struct { x: i32, y: i32 };
fn failA() !void { return error.A; }
fn failB() !void { return error.B; }
fn findPath(flag: i32) ?[]Point {
    if (flag == @intCast(i32, 1)) {
        _ = failA() catch return null;
    }
    if (flag == @intCast(i32, 2)) {
        _ = failB() catch return null;
    }
    return null;
}
pub fn main() void {
    var p1 = findPath(@intCast(i32, 1));
    var p2 = findPath(@intCast(i32, 2));
    var p3 = findPath(@intCast(i32, 0));
    if (p1 == null and p2 == null and p3 == null) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
```

Expected runtime: `1`. Tests multiple `catch return null` paths in one fn.

- [ ] **Step 4: Verify each repro (QUICK_REF recipe)**

```bash
mkdir -p /tmp/t4r && rm -rf /tmp/t4r/*
sf/build/out_release/zig1 --dump-c89 repro/mi_matrix/<name>/main.zig > /tmp/t4r/<name>.c 2>/tmp/t4r/<name>.err
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/t4r/<name>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/t4r/<name>
/tmp/t4r/<name>
```

For `opt_slice_null_xmod` use the multi-module recipe (Task 3 Step 5). Expected: dump rc=0, gcc rc=0, run rc=0 printing `1`. Assert: gcc emits `-Wint-conversion` warnings (capture with `2>&1 | grep warning`), specifically on the null-payload temp assign (`= NULL`). Oracle: zig0 rc=0.

- [ ] **Step 5: Write the 3 `NOTES.md` files**

Document: what it tests, the defect (null-payload temp typed `int` instead of slice struct), pre-fix emitted-C symptom (`zT_3 = NULL;` with `int` payload temp), gcc warning text, runtime output, classification (OK-by-gate, latent/type-incorrect, tracked separately — mirror `opt_slice_null_return` NOTES.md).

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/opt_slice_null repro/mi_matrix/opt_slice_null_xmod repro/mi_matrix/opt_slice_null_multi
git commit -m "repro: optional-of-slice null payload temp type (same-module/xmod/multi-path)"
```

**Gate:** all 3 dump rc=0, gcc rc=0, run rc=0 printing `1`, gcc `-Wint-conversion` warnings present, zig0 oracle rc=0. All 3 dirs committed.

---

### Task 5: Gate sweep + manifest + QUICK_REF updates

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (totals + per-repro sections)
- Modify: `docs/sf/QUICK_REF.md` (corpus baseline + follow-up notes)

**Interfaces:**
- Consumes: all 12 Battery A + 3 Battery B repro dirs from Tasks 1-4.
- Produces: updated manifest accounting + QUICK_REF baseline row.

**Context:** The corpus grew by 15 dirs (12 FAIL-classified runtime-gap + 3 OK-by-gate latent). The manifest `EXPECTED_FAIL.md` v25 (2026-08-07, "215 repros OK=208/FAIL=3/gg=4") must be extended. QUICK_REF's corpus-gate section gets a new baseline row.

- [ ] **Step 1: Run the full corpus sweep (classify by gcc exit code, QUICK_REF)**

```bash
sf/build/out_release/zig1 --version  # sanity
# Full 216+15 dir sweep (classify by gcc EXIT CODE; dump rc>=128=CRASH; error[48|3042|9001|3043]|ASAN=ICE; gcc rc==0=OK; else FAIL)
```

Record: total dirs, OK, FAIL, ICE, CRASH, green-guards. The 12 new Battery A dirs must classify FAIL (runtime-gap: dump rc=0, gcc rc=0 — BUT the classifier's gcc-exit rule returns OK for them since they compile!).

**STOP — classification conflict:** The QUICK_REF classifier labels a repro OK if gcc rc==0. Battery A repros compile clean (gcc rc=0) but print wrong output at runtime — they are RUNTIME-gap, like `comptime_neg_int` was (tracked separately, "the gcc-exit classifier reports it OK"). So Battery A repros classify **OK** under the corpus gate, but are tracked as runtime-gap FAIL. This matches the spec's "battery A repros are FAIL until fixed" only in the RUNTIME sense. Record them as: **OK-by-compile / runtime-gap-tracked** in the manifest, mirroring the `comptime_neg_int` and `opt_slice_null_return` precedent — NOT added to the FAIL count.

- [ ] **Step 2: Verify the existing 3 FAILs + 4 green-guards unchanged**

Confirm `field_store_drop`, `test_stub_0`, `self_embed_optional_cycle` still FAIL and the 4 green-guards still green. No regression.

- [ ] **Step 3: Verify 4 MD5 gates byte-identical**

```bash
for e in mud_server game_of_life lisp_interpreter_curr json_parser; do
  sf/build/out_release/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum
done
```

Expected: mud `906fa59c8676bb1054d3fcc13704fce5`, gol `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json `b5f56ebd51d2f0fcd379a1e083594462` — all byte-identical (no compiler source changed).

- [ ] **Step 4: Update `repro/mi_matrix/EXPECTED_FAIL.md`**

Append a new CURRENT row: 215+15=230 dirs (or the measured total), noting the 12 Battery A dirs as OK-by-compile/runtime-gap-tracked and the 3 Battery B dirs as OK-by-gate/latent. Add a new "char_literal switch-case repro battery" section documenting: the defect (both lower.zig sites), the 12 repros with their pre-fix outputs, and the follow-up fix note. Add an "opt_slice null payload repro battery" section for the 3 Battery B repros. Keep existing FAIL counts (3) and green-guard counts (4) UNCHANGED.

- [ ] **Step 5: Update `docs/sf/QUICK_REF.md`**

Add a new corpus-gate baseline line: `[updated: 2026-08-07 — char_literal switch + opt_slice repro battery]: effective OK=… / FAIL=3 / green-guards=4 over … repros` (fill with measured numbers), noting the 12 runtime-gap-tracked char-switch repros and 3 latent opt-slice repros. Update the "Out-of-scope follow-up" note to point at the new repro dirs.

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: corpus manifest + QUICK_REF for char_literal switch + opt_slice repro battery"
```

**Gate:** corpus sweep numbers recorded, existing 3 FAIL + 4 green-guards unchanged, 4 MD5s byte-identical, manifest and QUICK_REF updated consistently with measured values. Commit created.

---

## Post-Plan (NOT this plan)

- **char_literal switch-case fix:** add `AstKind.char_literal` branch to both case-collection loops (`lower.zig:3183`/`:3920`), reading `store.int_values` like `int_literal` does. Verify all 12 Battery A repros flip to correct runtime output.
- **opt_slice null-payload temp typing fix:** emit the null payload temp at the optional's payload type, not `int`. Verify gcc warnings disappear for Battery B. Assess mud/gol/lisp/json re-baseline blast radius.
