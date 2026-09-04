# `_upgraded` Examples — Zig1-Feature Showcase + Zig0-Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `examples/z98/lisp_interpreter_upgraded` and `examples/z98/rogue_mud_upgraded` with first-use showcase of every language-wins F-area feature (silent thread-ins + observable demos), keeping canonical behavior byte-identical, and add the whole-program zig0-reject closeout gate.

**Architecture:** Example-only work. Each program gets silent rewrites onto the new constructs plus an observable demo surface reachable only through extended feeds (lisp REPL builtins; rogue `i` local command + network-variant `i`). A committed harness (`scripts/closeout/verify_upgraded.sh`) builds/runs each program under the reference compiler, compares canonical + demo stdout byte-exactly, checks export symbol gates, and proves `sf/build/zig0` cannot build the upgraded entrypoints.

**Tech Stack:** zig1 (reference compiler `/tmp/fx_subfolder/zig1`, md5 `7c08d2d5`, std lib installed at `/tmp/fx_subfolder/lib`), `gcc -m32 -std=c89`, feeds via stdin, `sf/build/zig0` (legacy compiler, closeout oracle).

Design spec: `docs/superpowers/specs/2026-09-04-upgraded-examples-closeout-design.md` (operator-approved).

## Global Constraints

- **Edits confined to** `examples/z98/{lisp_interpreter_upgraded,rogue_mud_upgraded}/`, new `scripts/closeout/`, and the two doc records (EXPECTED_FAIL.md, QUICK_REF.md) + plan/spec. **NEVER touch** the four gate programs' original dirs (`game_of_life`, `lisp_interpreter_curr`, `json_parser`, `mud_server`), `rogue_mud`/`lisp_interpreter_curr` originals, or `sf/src/`, `sf/build/`, `out_release/`. No compiler rebuild. No `_upgraded` source may be removed from the original copy other than the enumerated edits.
- 4-MD5 gates and self-compile fixed point are **not affected** (no `sf/src` change). No gate re-baseline in this plan.
- `examples/z98/json_parser_upgraded` (untracked) is **out of scope** — never staged.
- Every canonical feed run must remain **byte-identical between the original program and its `_upgraded`** counterpart. Demo goldens (new surface) are authored at GREEN time, determinism-verified 3×.
- Z98 dialect in all new code: no `anytype`/`@Type`/method syntax/pointer captures; `@intCast` on width changes; `else` prong on every non-exhaustive switch; case-range endpoints are int/char literals only; `@ptrFromInt` always on an **annotated** target var; `@offsetOf`/`@fieldParentPtr` on **plain structs** only; do not reintroduce the switch-expression payload-capture emission bug (statement switches for captures).
- Build/run recipe (authoritative): fresh output dir (`rm -rf` + `mkdir -p`), then `(cd /workspace/znineeight && <zig1> --dump-c89 --output-dir <W> <entry>)`; gcc `-m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include` each `.c` → `.o`; link `*.o` + `sf/src/include/zig_runtime.c` `sf/src/include/zig_pal.c` (repo-authoritative location — AMENDMENT 1, operator ruling); run under `timeout` with a feed file on stdin; capture stdout. Task 1 installs this as `scripts/closeout/run_upgraded.sh`; later tasks call it.
- Reports accumulate in `.superpowers/sdd/task-CLOSEOUT-report.md` (gitignored). Ledger: `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory`, agent `closeout-session`.
- Only plan-authorized actions; STOP-present on any divergence; commits only per-task; stage ONLY intended files; pre-existing dirty set (2026-08-26 plan doc, `mnemoria/*`, `.zig1_*.tmp`, `build/`, `json_parser_upgraded/`) never staged.
- A report/evidence contract per task: status, files changed, feed-byte-identity + golden evidence (md5s), symbol-gate evidence, zig0-reject evidence where applicable, concerns.

---

### Task 1: Baseline harness + canonical feeds/expected (no program edits)

**Files:**
- Create: `scripts/closeout/run_upgraded.sh`, `scripts/closeout/zig0_try.sh`
- Create: `examples/z98/lisp_interpreter_upgraded/demo/canonical_feed.txt` + `canonical_expected.txt`
- Create: `examples/z98/rogue_mud_upgraded/demo/canonical_feed.txt` + `canonical_expected.txt`
- Record: `.superpowers/sdd/task-CLOSEOUT-report.md` header

**Interfaces:**
- Produces: `scripts/closeout/run_upgraded.sh <zig1> <entry> <feed> <out_stdout>` (exit 0 + stdout file + echo `RUNRC`), reused by every later task and the gate; `scripts/closeout/zig0_try.sh <entry> <workdir>` (attempt `sf/build/zig0` build, prints rc + first diagnostic, never emits a binary into the repo).

- [ ] **Step 1: Write `scripts/closeout/run_upgraded.sh`**

```bash
#!/usr/bin/env bash
# run_upgraded.sh <zig1> <entry> <feed> <out_stdout>
# Builds <entry> with <zig1> into a fresh dir, runs it on <feed>, captures stdout.
set -u
ZIG1="$1"; ENTRY="$2"; FEED="$3"; OUT="$4"
ROOT=/workspace/znineeight
W=$(mktemp -d)
rm -rf "$W"; mkdir -p "$W"
(cd "$ROOT" && "$ZIG1" --dump-c89 --output-dir "$W" "$ENTRY") >"$W/dump.log" 2>&1
if [ $? -ne 0 ]; then echo "RUNRC=DUMPFAIL"; cat "$W/dump.log"; exit 1; fi
for f in "$W"/*.c; do
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I "$ROOT/sf/src/include" -c "$f" -o "${f%.c}.o" || { echo "RUNRC=GCCFAIL"; cat "$W"/gcc.err 2>/dev/null; exit 1; }
done
gcc -m32 -o "$W/prog" "$W"/*.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" || { echo "RUNRC=LINKFAIL"; exit 1; }
timeout 30 "$W/prog" < "$FEED" > "$OUT" 2>"$W/run.err"
echo "RUNRC=$?"
```

- [ ] **Step 2: Write `scripts/closeout/zig0_try.sh`**

```bash
#!/usr/bin/env bash
# zig0_try.sh <entry> — attempt a whole-program zig0 build of <entry>; prints rc + first diagnostic.
set -u
ENTRY="$1"
ROOT=/workspace/znineeight
W=$(mktemp -d)
rm -rf "$W"; mkdir -p "$W"
(cd "$ROOT" && timeout 120 "$ROOT/sf/build/zig0" --dump-c89 --output-dir "$W" "$ENTRY") >"$W/zig0.out" 2>&1
echo "ZIG0_RC=$?"
head -5 "$W/zig0.out"
```

- [ ] **Step 3: Author the lisp canonical feed** (`examples/z98/lisp_interpreter_upgraded/demo/canonical_feed.txt`). Lines — each must be a value-producing expression parseable by BOTH `lisp_interpreter_curr` and `lisp_interpreter_upgraded` (no new builtins):

```
(+ 1 2)
(* 3 4)
(- 10 3)
(cons 1 2)
(car (cons 1 2))
(cdr (cons 1 2))
(= 5 5)
(= 5 6)
(< 2 3)
(> 7 4)
(nil? (quote ()))
exit
```

Verify in the ORIGINAL `lisp_interpreter_curr` that every line prints a value (no `Parse error`/`Eval error`). If a specific expression errors, replace it with an equivalent value-producing expression of the same feature class (list/int/bool/compare/nil) and note the substitution in the report — the canonical set must keep at least one line per class and must reproduce identically in the upgraded program.

- [ ] **Step 4: Capture the lisp canonical expected.** `bash scripts/closeout/run_upgraded.sh /tmp/fx_subfolder/zig1 examples/z98/lisp_interpreter_curr/main.zig examples/z98/lisp_interpreter_upgraded/demo/canonical_feed.txt /tmp/lisp_canon_expected.txt`; run 3× → byte-identical (`md5sum`). Verify `RUNRC=0`. Write the bytes to `canonical_expected.txt`. Then run the SAME feed through `lisp_interpreter_upgraded` today → byte-identical to `canonical_expected.txt` (pre-edit identity proof).

- [ ] **Step 5: Author the rogue canonical feeds** (`examples/z98/rogue_mud_upgraded/demo/canonical_feed.txt`):

```
q
```

and a second short move/look feed `canonical_move_feed.txt`:

```
d
l
q
```

(The `q`-only feed ≈ 221 B boot text; the move/look feed exercises rendering + look + quit. Neither contains the reserved demo char `i`.)

- [ ] **Step 6: Capture the rogue canonical expecteds.** For EACH of the two feeds run the ORIGINAL `examples/z98/rogue_mud` entry with `run_upgraded.sh` 3× → byte-identical, `RUNRC=0`; write bytes to `demo/canonical_expected.txt` (q-feed) and `demo/canonical_move_expected.txt` (move feed). Re-run both through `rogue_mud_upgraded` → byte-identical (pre-edit identity proof). md5 both pairs.

- [ ] **Step 7: Record baseline zig0-reject evidence.** `bash scripts/closeout/zig0_try.sh examples/z98/lisp_interpreter_upgraded/main.zig` and the same for `rogue_mud_upgraded/main.zig`. Record rc + first diagnostic verbatim in the report (expected: nonzero reject already via the C1 tag-`==` rewrites; exact text recorded, not assumed).

- [ ] **Step 8: Commit.** Stage the 2 scripts + the lisp and rogue `demo/` feed/expected files only.

```bash
git add scripts/closeout/run_upgraded.sh scripts/closeout/zig0_try.sh \
        examples/z98/lisp_interpreter_upgraded/demo examples/z98/rogue_mud_upgraded/demo
git commit -m "test: closeout harness + canonical feeds/expected for upgraded examples (baseline)"
```

- [ ] **Step 9: Report.** Status, file list, all md5s (feed expecteds, original-vs-upgraded identity), zig0-reject diagnostics, concerns. Ledger line.

---

### Task 2: LISP silent thread-ins

**Files:**
- Modify: `examples/z98/lisp_interpreter_upgraded/token.zig:20-22`
- Modify: `examples/z98/lisp_interpreter_upgraded/util.zig:44-45`
- Modify: `examples/z98/lisp_interpreter_upgraded/util.zig:53-57`
- Modify: `examples/z98/lisp_interpreter_upgraded/value.zig` (top + `alloc_value`)
- Modify: `examples/z98/lisp_interpreter_upgraded/main.zig:128-129`

**Interfaces:**
- Consumes: Task 1 harness + canonical expecteds.
- Produces: silent rewrites (behavior-preserving) + `value_mod.alloc_count` counter + exported `alloc_value` symbol. Later task (`(allocs)`) reads `alloc_count`.

- [ ] **Step 1: token.zig — digit class as a case range** (`fastedit`, re-read first; lines 20-22)

```zig
fn is_digit(c: u8) bool {
    return switch (c) {
        '0'...'9' => true,
        else => false,
    };
}
```

- [ ] **Step 2: util.zig — parse guard as a statement range switch** (line 45 currently `if (s[i] < '0' or s[i] > '9') return error.InvalidDigit;`)

```zig
        switch (s[i]) {
            '0'...'9' => {},
            else => return error.InvalidDigit,
        }
```

- [ ] **Step 3: util.zig — `@ptrToInt` → `@intFromPtr` alias** (lines 54-55)

```zig
    const addr = @intFromPtr(ptr);
    const start = @intFromPtr(sand_start);
```

- [ ] **Step 4: value.zig — cross-module pub var counter + export + increment.** Add at file top (before `pub const Value`):

```zig
pub var alloc_count: i32 = 0;
```

Change the `alloc_value` signature line 13 from `pub fn alloc_value` to:

```zig
export fn alloc_value(arena: *sand_mod.Sand) util.LispError!*Value {
```

and immediately after `const mem = try sand_mod.sand_alloc(...)` insert:

```zig
    alloc_count += 1;
```

Verified ground truth: `alloc_value` is referenced only inside `value.zig` (its own `alloc_*` wrappers), so dropping `pub` breaks no cross-module access.

- [ ] **Step 5: main.zig — cross-module reset at REPL top.** Insert immediately before the `while (true) {` REPL loop (after line 128 `var input_buf: [4096]u8 = undefined;`):

```zig
    value_mod.alloc_count = 0;
```

- [ ] **Step 6: Build + canonical identity.** Rebuild `lisp_interpreter_upgraded`, run canonical feed 3× → byte-identical to `canonical_expected.txt` (Task 1), `RUNRC=0`. Also run a quick `(+ 1 2)` smoke → `3`.

- [ ] **Step 7: Export symbol gate.** Fresh dump; emitted `main_*.c`/module `.c` must contain a non-static `int alloc_value(...)`-style definition **by source name** and **zero** `zF_…_alloc_value`; the tokenizer/util module C must contain the range-switch emissions. Grep evidence recorded.

- [ ] **Step 8: Commit.**

```bash
git add examples/z98/lisp_interpreter_upgraded/token.zig examples/z98/lisp_interpreter_upgraded/util.zig \
        examples/z98/lisp_interpreter_upgraded/value.zig examples/z98/lisp_interpreter_upgraded/main.zig
git commit -m "feat: lisp upgraded — silent F-area thread-ins (case-ranges, @intFromPtr, export, cross-module pub var)"
```

- [ ] **Step 9: Report.** Diff summary, canonical md5 identity evidence, symbol-gate greps, smoke output, concerns. Ledger line.

---

### Task 3: LISP observable demo builtins + demo feed/golden

**Files:**
- Modify: `examples/z98/lisp_interpreter_upgraded/builtins.zig` (append 8 builtins)
- Modify: `examples/z98/lisp_interpreter_upgraded/main.zig:116-126` (register 8 builtins)
- Create: `examples/z98/lisp_interpreter_upgraded/demo/demo_feed.txt` + `demo_expected.txt`
- Modify: `examples/z98/lisp_interpreter_upgraded/demo/` (add `README.md` describing the new surface)

**Interfaces:**
- Consumes: `value_mod.alloc_count` (Task 2); canonical expecteds (Task 1).
- Produces: demo feed + golden; used by the gate (Task 8).

- [ ] **Step 1: Add two imports to the top of `builtins.zig`** (next to the existing imports at lines 1-3):

```zig
const std = @import("std");
const env_mod = @import("env.zig");
```

- [ ] **Step 2: Append the 8 builtins to `builtins.zig`** (after line 169; style matches the file: arity checks + `switch (arg.*)` + `value_mod.alloc_*`). Note: the existing `=` builtin keeps its name; the new atom-aware one is registered under the distinct name `"eq?"` as `builtin_phys_eq`:

```zig
pub fn builtin_layout(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    std.io.printInt(@intCast(i32, @offsetOf(env_mod.EnvNode, "value")));
    std.io.print(" ");
    std.io.printInt(@intCast(i32, @bitSizeOf(bool)));
    std.io.print(" ");
    std.io.printInt(@intCast(i32, @bitSizeOf(i64)));
    std.io.print("\n");
    return try value_mod.alloc_nil(arena);
}

pub fn builtin_address(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    const a = @intFromPtr(args[0]);
    return try value_mod.alloc_int(@intCast(i64, a), arena);
}

pub fn builtin_phys_eq(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    const a = args[0];
    const b = args[1];
    var res = false;
    switch (a.*) {
        .Int => |av| { switch (b.*) { .Int => |bv| res = av == bv, else => {} } },
        .Bool => |av| { switch (b.*) { .Bool => |bv| res = av == bv, else => {} } },
        .Symbol => |av| { switch (b.*) { .Symbol => |bv| res = util.mem_eql(av, bv), else => {} } },
        .Nil => { switch (b.*) { .Nil => res = true, else => {} } },
        else => { res = a == b; },
    }
    return try value_mod.alloc_bool(res, arena);
}

pub fn builtin_ptr_check(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    const a = @intFromPtr(args[0]);
    var p: *value_mod.Value = @ptrFromInt(a);
    const ok = p == args[0];
    return try value_mod.alloc_bool(ok, arena);
}

pub fn builtin_container_of(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    const Outer = struct {
        tag: u8,
        payload: u32,
    };
    var o = Outer{ .tag = @intCast(u8, 7), .payload = @intCast(u32, 99) };
    const parent = @fieldParentPtr(Outer, "payload", &o.payload);
    return try value_mod.alloc_bool(parent == &o, arena);
}

pub fn builtin_bitcast(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    const u: u64 = 0xFFFFFFFFFFFFFFFF;
    const s = @bitCast(i64, u);
    return try value_mod.alloc_int(s, arena);
}

pub fn builtin_allocs(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    return try value_mod.alloc_int(@intCast(i64, value_mod.alloc_count), arena);
}

pub fn builtin_classify(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    switch (args[0].*) {
        .Symbol => |s| {
            var lower: i32 = 0;
            var upper: i32 = 0;
            var digit: i32 = 0;
            var i: usize = 0;
            while (i < s.len) : (i += 1) {
                switch (s[i]) {
                    'a'...'z' => lower += 1,
                    'A'...'Z' => upper += 1,
                    '0'...'9' => digit += 1,
                    else => {},
                }
            }
            std.io.printInt(lower);
            std.io.print(" ");
            std.io.printInt(upper);
            std.io.print(" ");
            std.io.printInt(digit);
            std.io.print("\n");
            return try value_mod.alloc_nil(arena);
        },
        else => return error.NotAnInt,
    }
}
```

Note: `builtin_layout`/`builtin_classify` print a line then return `Nil` (REPL prints `nil` after). If the local `const Outer = struct {...}` with a captured address does not lower under zig1 (STOP condition), fall back to a module-level plain struct in the same file. `@fieldParentPtr(Outer, "payload", &o.payload)` returns `*Outer`; `parent == &o` is a valid pointer `==`. Verify the emitted C carries the offset-subtract chain.

- [ ] **Step 2: Register the 8 builtins** in `main.zig` after line 126 (same shape as existing registrations):

```zig
    global_env = (env_mod.env_extend("layout", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_layout), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("address", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_address), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("eq?", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_phys_eq), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("ptr-check", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_ptr_check), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("container-of", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_container_of), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("bitcast", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_bitcast), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("allocs", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_allocs), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("classify", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_classify), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
```

- [ ] **Step 3: Author the demo feed** (`demo/demo_feed.txt`) — new-surface only:

```
(eq? 1 1)
(eq? 1 2)
(eq? (quote hello) (quote hello))
(eq? (quote hello) (quote world))
(define l1 (quote (1 2)))
(eq? l1 l1)
(eq? (quote (1 2)) (quote (1 2)))
(layout)
(bitcast)
(container-of)
(allocs)
(classify "abc12XY")
(address (quote abc))
(ptr-check (quote abc))
exit
```

Verify each `(define …)`/quote form parses under the upgraded REPL (the interpreter supports define/quote per the error vocabulary; substitute an equivalent expression if any form errors, noting it in the report). Values that are large/absolute (address, allocs) must be deterministic across runs.

- [ ] **Step 4: Capture + verify the demo golden.** Build, run feed 3× → byte-identical stdout (`md5sum`). Cross-check the deterministic values against hand contracts: `layout` line prints `8 1 64` (`EnvNode.value` @ byte 8; `@bitSizeOf(bool)`=1; `@bitSizeOf(i64)`=64); `bitcast` prints `-1`; `container-of` prints `true`; `ptr-check` prints `true`; `classify` prints `2 2 2` (for `abc12XY`); `eq?` atom lines `true/false/true/false`. If any line contradicts its hand contract, STOP-present (do not silently re-baseline). Write the 3×-verified bytes to `demo_expected.txt` (the REPL prints `> ` prompts and `nil` for Nil-returning builtins — these bytes are part of the golden, captured, not assumed).

- [ ] **Step 5: Canonical regression.** Re-run the canonical feed → byte-identical to `canonical_expected.txt` (new builtins are inert until called; `(allocs)`/`address` reachable only from the demo feed).

- [ ] **Step 6: Demo README.** `demo/README.md`: the 8 builtins, the two feeds, and the note that `demo_expected.txt` includes absolute arena addresses (implementation-coupled; regenerate if perm-arena allocation order ever changes).

- [ ] **Step 7: Commit.**

```bash
git add examples/z98/lisp_interpreter_upgraded/builtins.zig examples/z98/lisp_interpreter_upgraded/main.zig \
        examples/z98/lisp_interpreter_upgraded/demo
git commit -m "feat: lisp upgraded — observable demo builtins (layout/address/eq?/ptr-check/container-of/bitcast/allocs/classify)"
```

- [ ] **Step 8: Report.** Builtin list + registration diff, demo stdout md5 3×, contract cross-check table, canonical-regression md5, concerns. Ledger line.

---

### Task 4: ROGUE silent thread-ins

**Files:**
- Modify: `examples/z98/rogue_mud_upgraded/lib/persistence.zig`
- Modify: `examples/z98/rogue_mud_upgraded/main.zig:453-458` (`injectInt`)
- Modify: `examples/z98/rogue_mud_upgraded/ui.zig` (top + `draw`)

**Interfaces:**
- Consumes: Task 1 rogue canonical expecteds (q-feed + move-feed).
- Produces: `FileHeader` persistence struct, exported `saveDungeon`/`loadDungeon`, `ui_mod.render_calls` counter. Later task prints them.

- [ ] **Step 1: persistence.zig — named header struct + export.** Add a module const/type near the top (after the imports, before `FileError`):

```zig
const FileHeader = struct {
    w: u8,
    h: u8,
};
```

Replace the `saveDungeon` header write (lines 26-27) with:

```zig
    var header = FileHeader{ .w = dungeon.width, .h = dungeon.height };
    if (fwrite(@ptrCast(*const void, &header), @sizeOf(FileHeader), 1, file) != 1) return error.WriteFailed;
```

Replace the `loadDungeon` header read (lines 44-48) with:

```zig
    var header = FileHeader{ .w = @intCast(u8, 0), .h = @intCast(u8, 0) };
    if (fread(@ptrCast(*void, &header), @sizeOf(FileHeader), 1, file) != 1) return error.ReadFailed;

    const width = header.w;
    const height = header.h;
```

Change both signatures to export form (lines 21 and 39), `pub fn saveDungeon(` → `export fn saveDungeon(` and `pub fn loadDungeon(` → `export fn loadDungeon(`. Add an exported status var near the top:

```zig
export var last_save_status: i32 = 0;
```

(optional silent export; set it in `saveDungeon` to 1 on success — keep `last_save_status` writes out of any stdout path). If `export var` alongside `pub export` conflicts, drop `last_save_status` and keep only the two exported fns.

- [ ] **Step 2: main.zig `injectInt` — `@bitCast` reinterpretation.** Lines 453-458 currently compute `var val = @intCast(u32, if (n < 0) -n else n);`. Replace with a two-step that uses `@bitCast` on the magnitude (identical for `n >= 0`; for `n < 0` with `n != INT_MIN` magnitude fits; `INT_MIN` preserves today's wrapping class):

```zig
fn injectInt(cells: [*]ui_mod.Cell, n: i32) void {
    if (n == 0) {
        cells[0].ch = '0';
        return;
    }
    var mag: i32 = if (n < 0) -n else n;
    var val = @bitCast(u32, mag);
```

Verify the emitted C contains the reinterpretation and that byte-identity feeds (which never hit a negative magnitude in a status cell) are unchanged.

- [ ] **Step 3: ui.zig — cross-module render counter.** Add near the module globals (after line 28 `var dirty: bool = true;`):

```zig
pub var render_calls: u32 = 0;
```

and at the top of `pub fn draw(...)` (line 30, before the `if (dirty)` block):

```zig
    render_calls += 1;
```

- [ ] **Step 4: main.zig — cross-module reset.** Insert before the `game_loop: while (true) {` label (after line 88 boot print):

```zig
    ui_mod.render_calls = 0;
```

- [ ] **Step 5: Build + canonical identity.** Rebuild `rogue_mud_upgraded`; run both canonical feeds 3× each → byte-identical to `canonical_expected.txt` + `canonical_move_expected.txt`; `RUNRC=0`. Also run a save/load round trip in a scratch feed (`v\nb\nq\n`) inside a scratch CWD and confirm `save.dat` byte-layout unchanged vs a save written by the pre-edit build (diff the two `save.dat` files byte-for-byte after a `v` in each; must be identical), confirming the FileHeader edit is layout-neutral.

- [ ] **Step 6: Symbol gates.** Fresh dump: emitted `.c` contains non-static `saveDungeon`/`loadDungeon` by source name; **zero** `zF_…saveDungeon`/`zF_…loadDungeon`; `render_calls` referenced by source name across the module boundary. Grep evidence recorded.

- [ ] **Step 7: Commit.**

```bash
git add examples/z98/rogue_mud_upgraded/lib/persistence.zig examples/z98/rogue_mud_upgraded/lib/ui.zig \
        examples/z98/rogue_mud_upgraded/main.zig
git commit -m "feat: rogue upgraded — silent F-area thread-ins (FileHeader @sizeOf/@offsetOf, @bitCast, export save/load, cross-module render_calls)"
```

- [ ] **Step 8: Report.** Diff summary, canonical md5 identity, save.dat byte-equality, symbol-gate greps, concerns. Ledger line.

---

### Task 5: ROGUE local `i` info command + demo feed/golden

**Files:**
- Modify: `examples/z98/rogue_mud_upgraded/main.zig` (add `demoInfo` fn + `i` prong in the local switch)
- Create: `examples/z98/rogue_mud_upgraded/demo/demo_feed.txt` + `demo_expected.txt` + `README.md`

**Interfaces:**
- Consumes: Task 4 exports/counters; Task 1 canonical expecteds.
- Produces: local `i` demo (same info routine reused by Task 6's net path via the per-client loop calling the same helper).

- [ ] **Step 1: Add `demoInfo` helper** near the other top-level fns in `main.zig` (e.g. after `injectInt`). Deterministic, layout-only output (no position/timing dependence):

```zig
fn demoInfo() void {
    std.io.print("--- zig1 demo ---\n");
    std.io.print("off Entity.hp=");
    std.io.printInt(@intCast(i32, @offsetOf(entity_mod.Entity, "hp")));
    std.io.print(" off Entity.x=");
    std.io.printInt(@intCast(i32, @offsetOf(entity_mod.Entity, "x")));
    std.io.print(" size Entity=");
    std.io.printInt(@intCast(i32, @sizeOf(entity_mod.Entity)));
    std.io.print(" bits bool=");
    std.io.printInt(@intCast(i32, @bitSizeOf(bool)));
    std.io.print(" off Room_t.h=");
    std.io.printInt(@intCast(i32, @offsetOf(room_mod.Room_t, "h")));
    std.io.print("\n");
    var u: u32 = 0xFFFFFFFF;
    const s = @bitCast(i32, u);
    std.io.print("bitcast(i32,0xFFFFFFFF)=");
    std.io.printInt(s);
    std.io.print("\n");
    const Local = struct {
        tag: u8,
        payload: u32,
    };
    var lo = Local{ .tag = @intCast(u8, 1), .payload = @intCast(u32, 5) };
    const parent = @fieldParentPtr(Local, "payload", &lo.payload);
    std.io.print("container-of=");
    if (parent == &lo) std.io.print("true\n") else std.io.print("false\n");
    std.io.print("render_calls=");
    std.io.printInt(@intCast(i32, ui_mod.render_calls));
    std.io.print("\n");
    var rn: u32 = 0;
    while (rn <= 9) : (rn += 1) {
        std.io.printInt(@intCast(i32, rn));
        std.io.print(" ");
    }
    std.io.print("\n");
    std.io.print("--- end demo ---\n");
}
```

Add a **case-range classifier** as a separate module-level helper in `main.zig`:

```zig
fn demoRangeClassifier(n: i32, ch: u8) void {
    var acc: i32 = 0;
    switch (n) {
        1...5 => acc += 10,
        6...9 => acc += 20,
        else => acc += 0,
    }
    switch (ch) {
        'a'...'z' => acc += 100,
        else => acc += 0,
    }
    std.io.printInt(acc);
    std.io.print("\n");
}
```

and call `demoRangeClassifier(3, 'x');` and `demoRangeClassifier(7, '!');` from `demoInfo()` after the classifier line (contracts `110` and `20`). Reorder so `demoInfo()` output is: header, layout line, bitcast line, container-of line, render_calls line, range-classifier lines, footer. The exact line set is the contract; adjust ordering in the code so the golden is stable.

- [ ] **Step 2: Local `i` prong.** In the local-input switch (`main.zig:234`), add before `else => {}`:

```zig
            'i', 'I' => demoInfo(),
```

- [ ] **Step 3: Author the local demo feed** (`demo/demo_feed.txt`):

```
i
q
```

(The `i` prints the info block; `q` quits. The canonical feeds never contain `i`.)

- [ ] **Step 4: Capture + verify golden.** Build (single-player), run the demo feed 3× → byte-identical stdout, `RUNRC=0`. Cross-check the deterministic values: layout line matches `off Entity.hp=4 off Entity.x=8 size Entity=12 bits bool=1 off Room_t.h=3` (record actuals; if the actual offsets differ from these hand-computed values, record-actual is acceptable ONLY if the values are stable 3× and equal to the compile-time constants of the program — the compiler is the source of truth; if values contradict obvious expectations STOP-present); `bitcast` → `-1`; `container-of` → `true`; range classifier → `110` then `20`. Write the 3×-verified bytes to `demo_expected.txt`. The demo feed's stdout is: boot lines + `i` info block + quit (captured, not assumed — the boot/quit bytes must equal the original program's for the same feed except the new `i` block).

- [ ] **Step 5: Canonical regression.** Both canonical rogue feeds → byte-identical to their expecteds (Task 1).

- [ ] **Step 6: Demo README.** Document the `i` command, feeds, golden, and note the demo-feed stdout = original boot/quit bytes + the `i` block.

- [ ] **Step 7: Commit.**

```bash
git add examples/z98/rogue_mud_upgraded/main.zig examples/z98/rogue_mud_upgraded/demo
git commit -m "feat: rogue upgraded — local 'i' info command demo (layout/bitcast/container-of/ranges)"
```

- [ ] **Step 8: Report.** Helper diff, demo stdout md5 3×, contract cross-check, canonical regression, concerns. Ledger line.

---

### Task 6: ROGUE network-variant demo

**Files:**
- Create: `examples/z98/rogue_mud_upgraded/demo/net_main.zig` (copy of `main.zig` with ONE delta: `const MULTIPLAYER_ENABLED: bool = true;` at line 15)
- Create: `examples/z98/rogue_mud_upgraded/demo/net_demo_client.zig`
- Create: `examples/z98/rogue_mud_upgraded/demo/net_demo_expected.txt` + `net_demo_feed_bytes.txt` (binary bytes if the client embeds the sequence; see below) + `README.md` notes
- Modify: `examples/z98/rogue_mud_upgraded/main.zig` — net-loop `i` prong (shared `demoInfo`)

**Interfaces:**
- Consumes: `demoInfo()` (Task 5) — callable from both input loops.
- Produces: committed net-demo client + expected; consumed by the gate (Task 8).

- [ ] **Step 1: Thread `i` into the network byte loop.** In the per-client byte loop (`main.zig:197` switch over `cc`), add before `else => {}`:

```zig
                            'i', 'I' => demoInfo(),
```

so a networked client's `i` prints the info block on the **server's stdout**.

- [ ] **Step 2: Create `demo/net_main.zig`.** Copy `main.zig` verbatim into `demo/net_main.zig`, then change the single line 15 `const MULTIPLAYER_ENABLED: bool = false;` to `true`. No other change. (Duplicating one file is intentional: the net variant must be a deterministically-buildable committed entry; the delta is exactly one line, documented in `demo/README.md`.)

- [ ] **Step 3: Create the client** `demo/net_demo_client.zig` (pattern from `repro/mi_matrix/net_builtin_test/main.zig:29-32`):

```zig
const std = @import("std");
const std_net = @import("std_net");

pub fn main() void {
    const PORT: u16 = 4000;
    const client = @socketCreate(0);
    if (client < 0) @exit(@intCast(u8, 1));
    if (@socketConnect(client, PORT) < 0) @exit(@intCast(u8, 2));
    const msg: []const u8 = "i";
    _ = @socketSend(client, msg.ptr, @intCast(i32, msg.len));
    // Read whatever the server streams until it closes or a short timeout elapses.
    var buf: [4096]u8 = undefined;
    var i: i32 = 0;
    while (i < 2000) : (i += 1) {
        const n = @socketRecv(client, &buf[0], 4096);
        if (n <= 0) break;
    }
    @socketClose(client);
    @exit(@intCast(u8, 0));
}
```

Verify against the net_builtin_test precedent that `@socketCreate(0)` + `@socketConnect(fd, PORT)` connects to `127.0.0.1`. If `@socketCreate(0)` fails to yield a connectable client on this platform, STOP-present with the alternative (a raw POSIX socket via extern `socket`/`connect`).

- [ ] **Step 4: Author the net golden.** Build the variant: `run_upgraded.sh /tmp/fx_subfolder/zig1 examples/z98/rogue_mud_upgraded/demo/net_main.zig /dev/null /tmp/net_stdout.txt`? — no: the server must run in the background while the client connects. Procedure (documented in `demo/README.md` and encoded in the gate):
  1. Build `net_main.zig` into `/tmp/netdemo/server/` (dump + gcc) and the client into `/tmp/netdemo/client/`.
  2. `cd /tmp/netdemo/server && (timeout 10 ./prog < /dev/null > server.out 2> server.err &)` — stdin `/dev/null` (EOF ⇒ fd0 always select-ready ⇒ the periodic-render path stays quiet; stdout is deterministic).
  3. Sleep ~0.2 s (let the server bind 4000), then run the client (its socket lifecycle is self-terminating).
  4. `wait`/allow the server to reach its timeout; the server stdout at kill is stable (nothing further prints after the client disconnects).
  5. Verify 3× byte-identical `server.out`; expected content = the single-player boot lines (`Welcome to Rogue MUD!`, `Generating dungeon...`, `Game started! ...`) + the `i` info block (identical bytes to the Task-5 info block) — no move renders. If extra nondeterministic bytes appear (renders, welcome-to-client echoes on stdout), STOP-present with captured samples rather than trimming.
  Write the verified bytes to `demo/net_demo_expected.txt`.
- Confirm the port 4000 is free during the test (prior mud gate uses 4000; run in a clean /tmp CWD, timeout-guarded).

- [ ] **Step 5: Canonical regression** — single-player build unchanged by the net `i` addition (canonical feeds never send `i`): both rogue canonical feeds byte-identical.

- [ ] **Step 6: Commit.**

```bash
git add examples/z98/rogue_mud_upgraded/main.zig examples/z98/rogue_mud_upgraded/demo
git commit -m "feat: rogue upgraded — network 'i' demo variant (net_main + demo client + golden)"
```

- [ ] **Step 7: Report.** net-loop diff, net_main delta proof (1 line), client source, server.out md5 3×, determinism notes, concerns. Ledger line.

---

### Task 7: GATE script + docs reconciliation

**Files:**
- Create: `scripts/closeout/verify_upgraded.sh`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (header bump + closeout note)
- Modify: `docs/sf/QUICK_REF.md` (newest-first closeout baseline bullet)

**Interfaces:**
- Consumes: everything from Tasks 1-6 (feeds, expecteds, client, helpers).
- Produces: the single reproducible whole-program closeout gate (operator ruling: no per-construct zig0 attribution).

- [ ] **Step 1: Write `scripts/closeout/verify_upgraded.sh`** — self-contained, calls the Task 1 helpers, exits nonzero on the first failure, prints a verdict table. Sequence:

```
phase A lisp:
  A1 build lisp_interpreter_upgraded (0 error[/0 PANIC)
  A2 canonical feed  == demo/canonical_expected.txt   (md5)
  A3 demo feed       == demo/demo_expected.txt        (md5)
  A4 export symbol gate: emitted C has source-name alloc_value, no zF_…alloc_value
  A5 whole-program zig0 build attempt must be nonzero (rc != 0, no binary) — print first diagnostic
phase B rogue:
  B1 build rogue_mud_upgraded (single player)
  B2 canonical q feed    == demo/canonical_expected.txt
  B3 canonical move feed == demo/canonical_move_expected.txt
  B4 demo feed           == demo/demo_expected.txt
  B5 export symbol gates: saveDungeon/loadDungeon source-named, no zF_; render_calls cross-module
  B6 net variant: build demo/net_main.zig + demo/net_demo_client.zig; background server on :4000 with </dev/null; run client; capture server stdout == demo/net_demo_expected.txt; kill server
  B7 whole-program zig0 build attempt of rogue_mud_upgraded/main.zig must be nonzero — print first diagnostic
verdict: print "CLOSEOUT OK" / "CLOSEOUT FAILED:<phase>"
```

All feeds/expecteds are resolved relative to the repo root. Runs are `timeout`-guarded; fresh dirs (`rm -rf` + `mkdir -p`) before every dump.

- [ ] **Step 2: Run the gate end-to-end** on the current tree. It must pass all of A1-A4, B1-B5, B5-variant handling, A5/B7 nonzero. If any phase fails, fix within this task's scope (the gate script) or STOP-present if the failure is a program/compiler issue.

- [ ] **Step 3: EXPECTED_FAIL.md.** Bump the header version and add a short closeout note (the `_upgraded` example dirs remain gate-exempt; canonical byte-identity + demo goldens + zig0 whole-program reject are now committed gate artifacts under `scripts/closeout/`). Preserve all historical sections verbatim.

- [ ] **Step 4: QUICK_REF.md.** Insert a newest-first baseline bullet (dense dated style, above the current-newest Post-F-CLEANDIAG bullet) recording: this closeout work (spec/plan shas), the two upgraded programs' committed canonical/demo goldens, the harness path, the zig0 whole-program-reject property, no `sf/src` change / no gate movement (4-MD5 unchanged, fixed point untouched).

- [ ] **Step 5: Commit.**

```bash
git add scripts/closeout/verify_upgraded.sh repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: closeout gate + upgraded-examples feature-showcase reconciliation (verify_upgraded.sh)"
```

- [ ] **Step 6: Report + STOP-present.** Full verdict table, each md5, zig0 diagnostics, tree state. STOP-present the close (operator review); no further F-plan authoring resumes until the operator directs.

---

## Plan Self-Review

1. **Spec coverage:** silent thread-ins + observable demos per program (Tasks 2-6) cover all six F-areas (introspection Task 2/3/4/5, pointer builtins Task 2/3/5, `@bitCast` Task 2/4/5, cross-module pub-var store Task 2/4, export Task 2/4, case-ranges Task 2/3/5); mixed policy honored; compact canonical feeds + authored demo goldens; whole-program zig0 gate (Task 7) matches the operator's build-gate ruling; `json_parser_upgraded` and the F-hold recorded out of scope.
2. **Placeholder scan:** no TBD; every code step complete; goldens are captured-verbatim artifacts with explicit determinism + hand-contract checks.
3. **Type/name consistency:** builtins named `<prefix>_<name>` matching the file's `builtin_*` convention; new REPL names (`layout`, `address`, `eq?`, `ptr-check`, `container-of`, `bitcast`, `allocs`, `classify`) distinct from all 11 existing; rogue helpers `demoInfo`/`demoRangeClassifier` unique.
