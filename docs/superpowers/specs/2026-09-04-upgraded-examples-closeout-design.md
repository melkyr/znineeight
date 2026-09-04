# Z98 `_upgraded` Examples — Zig1-Feature Showcase + Zig0-Closeout Design

> **Status:** Approved design (operator, 2026-09-04). Companion implementation plan: `docs/superpowers/plans/2026-09-04-upgraded-examples-closeout-plan.md`.

**Goal:** Turn the two committed zig1-showcase example programs — `examples/z98/lisp_interpreter_upgraded` and `examples/z98/rogue_mud_upgraded` — into the living proof that zig1 supersedes zig0: each keeps compiling under zig1 with byte-identical canonical behavior, adds first-use showcase of every F-area feature implemented since the language-wins R/I gate (silent thread-ins **and** observable demos), and is **un-buildable by zig0** as a whole program (the closeout gate).

## Scope and Boundaries

- Edits are confined to `examples/z98/{lisp_interpreter_upgraded,rogue_mud_upgraded}/` plus:
  - new committed feed/golden files under `<prog>_upgraded/demo/`,
  - one gate script `scripts/closeout/verify_upgraded.sh`,
  - doc records (EXPECTED_FAIL.md note, QUICK_REF.md baseline bullet, this spec + plan).
- The four 4-MD5-gate programs and their `_upgraded`-free originals are **untouched**. `_upgraded` dirs are gate-exempt (established U-CLOSE record) — editing them moves no gate, requires no compiler rebuild, and leaves the self-compile fixed point (`85733145…`) untouched.
- No `sf/src` change anywhere in this work.
- `examples/z98/json_parser_upgraded` stays **out of scope** (untracked, deferred; may become a third vehicle later on a separate GO).
- Compiler-feature plans (PLAN-INTWIDTH, PLAN-PACK-CORE/AGG/B3) remain **on hold** until this closeout work completes (operator directive; recorded in the master R/I plan amendment).

## Feature Set (all six F-areas, from the language-wins F execution)

1. `@offsetOf` / `@bitSizeOf` / `@bitOffsetOf` (F-INTRO) — comptime folds, plain `struct_type` targets only.
2. `@intFromPtr` / `@ptrFromInt` / `@fieldParentPtr` (F-PTRBUILTIN) — `@ptrFromInt` requires an **annotated** target var; `@fieldParentPtr` plain-struct only, runtime 4-inst chain.
3. `@bitCast` (F-BITCAST) — equal-`.size` int-family reinterpretation only.
4. cross-module `pub var` scalar **store** (F-CROSSMOD-STORE) — importer-store → shared storage; previously ICE `error[3043]`.
5. `export fn/var` (F-EXPORT) — source-name C symbol (mangler exemption); never `export fn main`.
6. switch case-ranges (F-SWITCHRANGE) — literal int/char endpoints only; `else` still mandated in new code; ranges not overlapping scalars; expansion cap 16384.

## Mixed Policy (operator ruling)

- **Silent thread-ins:** replace old idioms with the new construct where behavior is provably identical (byte-identity of every existing/canonical feed preserved).
- **Observable demos:** each program gains a small observable surface reachable ONLY through an extended feed/command the original program never receives, so every canonical feed stays byte-identical to the original. Demo goldens are authored (new surface has no original counterpart).
- Per-program split of observability is defined below; both programs get both kinds (operator ruling: "Both get demos").

## Program A — `lisp_interpreter_upgraded` (REPL, stdin-driven)

### Silent thread-ins
- `token.zig:20-22` `is_digit` → `switch (c) { '0'...'9' => true, else => false }` (case-ranges).
- `util.zig:45` `parse_int` digit guard → statement range switch (case-ranges).
- `util.zig:53-57` `@ptrToInt` → `@intFromPtr` alias (F-PTRBUILTIN alias form).
- `export fn alloc_value` (`value.zig:13`) — export + symbol gate (no `zF_` in emitted C for it).
- `pub var alloc_count: i32 = 0` in `value.zig`, incremented in `alloc_value`; `main.zig` resets `value_mod.alloc_count = 0` at REPL top (cross-module scalar store).

### Observable demos — 8 new builtins (registered `main.zig:116-126`, bodies in `builtins.zig`)
- `(layout)` — prints comptime `@offsetOf(env_mod.EnvNode,"value")`, `@bitSizeOf(bool)`, `@bitSizeOf(i64)` as integers.
- `(address x)` — evaluates `x`, returns Int `@intCast(i64, @intFromPtr(<the *Value>))`.
- `(eq? a b)` — value equality for atoms (Int/Bool/Symbol by value), **physical identity** for composite (Cons/Builtin) — scheme-`eqv?`-like (operator ruling).
- `(ptr-check x)` — `var p: *Value = @ptrFromInt(@intCast(usize, @intFromPtr(<ptr>)))` round-trip, deref, verify tag → Bool.
- `(container-of)` — local plain struct `Outer { tag: u8, payload: u32 }`; `@fieldParentPtr(Outer, "payload", &o.payload) == &o` → Bool.
- `(bitcast)` — `@bitCast(i64, u64)` of `0xFFFF…` → Int `-1`.
- `(allocs)` — returns Int value of `value_mod.alloc_count` (cross-module read of the shared counter).
- `(classify "<str>")` — case-range scan of symbol bytes counting `'a'...'z'` / `'A'...'Z'` / `'0'...'9'`; returns an Int (packed counts or count; exact contract authored at GREEN).

Constraints: `Value` is a `union(enum)` → ineligible for `@offsetOf`/`@fieldParentPtr`; targets must be the plain structs (`EnvNode`, `Sand`, `Outer`). Ints print via `@intCast(i32, …)` — values must stay in range; absolute arena addresses are low and deterministic in the static m32 binary.

## Program B — `rogue_mud_upgraded` (server game; local + network input loops)

### Silent thread-ins
- `lib/persistence.zig`: replace the magic `[2]u8{width,height}` file header with a named `FileHeader { w: u8, h: u8 }` written/read via `@sizeOf`/`@offsetOf` (byte-identical `save.dat` layout).
- `main.zig:458` `injectInt`: `var mag = @intCast(u32, if (n < 0) -n else n)` → `var mag = @bitCast(u32, @intCast(i32, if (n < 0) -n else n))`? No — silent site must keep exact semantics; see plan. Authoritative silent site: reinterpret the already-non-negative magnitude with `@bitCast(u32, mag_i32)` (identical for mag ≥ 0; INT_MIN identical to today's UB class). Exact edit form is in the plan.
- `export fn saveDungeon` / `export fn loadDungeon` (`lib/persistence.zig:21/:39`) + symbol gate (no mangled `zF_`).
- `pub var render_calls: u32 = 0` in `lib/ui.zig`, incremented in `draw`; `main.zig` resets `ui_mod.render_calls = 0` before `game_loop` (cross-module store).

### Observable demos — local command `i` (info) + network `i`
- New local-input prong (unused letter `i`) at `main.zig:234` printing a combined info block, each line demonstrating one feature:
  - layout table via `@offsetOf(entity_mod.Entity, "hp"/"x")`, `@sizeOf(Entity)`, `@bitSizeOf(bool)`, `@offsetOf(room_mod.Room_t, "h")`;
  - `@bitCast(i32, u32)` → `-1` and `@bitCast(u16, <hp>)` unsigned wrap;
  - `@ptrFromInt` round-trip self-test and a `@fieldParentPtr` container-of self-test (local `Outer`-style struct) → Bool line;
  - `render_calls` value (cross-module read);
  - a case-range classifier printing the fixture contract (`130 47`) for `1...5`/`6...9` int and `'a'...'z'` char ranges.
- Network variant (operator ruling): same `i` threaded into the per-client byte loop (`main.zig:197`); a second build with `MULTIPLAYER_ENABLED=true`; a committed small Zig TCP demo client under `<prog>_upgraded/demo/` (built with the reference compiler) that connects to the server, sends the demo byte sequence, and quits; the server stdout is the golden.
- Original programs never receive the `i` char → their byte-identity to the upgraded canonical runs is untouched.

## Feeds, Goldens, and the Closeout Gate

Committed per program under `<prog>_upgraded/demo/`:
- `canonical_feed.txt` + `canonical_expected.txt` — compact canonical feeds (rogue: q-quit ~221 B + a short move/look run; lisp: a small basic-expression battery), expected stdout **captured from the ORIGINAL program** run (operator ruling: compact feeds). Byte-identity of the upgraded run to `canonical_expected.txt` is the invariant.
- `demo_feed.txt` + `demo_expected.txt` — extended feed reaching only the new surface; expected stdout authored at GREEN time, determinism-verified 3×.
- rogue network: `net_demo_feed.txt`/expected + `net_demo_client.zig`.

Gate script `scripts/closeout/verify_upgraded.sh` (whole-program closeout gate, operator ruling): for each upgraded program —
1. build with the reference compiler (fresh `--dump-c89` dir + `gcc -m32`), 0 `error[`/0 PANIC;
2. canonical feed run → stdout byte-identical to `canonical_expected.txt`; rc 0;
3. demo feed run → stdout byte-identical to `demo_expected.txt`; rc 0;
4. export symbol gates (grep emitted C/`nm`) — source names present, no `zF_`/`zG_` for exported symbols;
5. **whole-program `sf/build/zig0` build attempt of each upgraded entrypoint FAILS/REJECTS** (rc ≠ 0, no binary) — the bye-bye-zig0 proof; record the failing diagnostic verbatim;
6. rogue network variant: build `MULTIPLAYER_ENABLED=true`, run with the committed net client against 127.0.0.1:4000, server stdout byte-identical to the net golden.

Doc records: EXPECTED_FAIL.md v-bump note (upgraded examples remain exempt; canonical identity is now a committed gate), QUICK_REF.md newest-first closeout baseline bullet, this spec + plan.

## Dialect / correctness constraints (binding for all new code)

- Z98 dialect: no `anytype`/`@Type`/method syntax/pointer captures; `@intCast` on width changes; `else` prong in every non-exhaustive switch; slice bounds precomputed into locals; no inline `@intCast`+math in slice bounds.
- `@offsetOf`/`@fieldParentPtr`/`@ptrFromInt`: plain-struct / annotated-var discipline only (loud-ICE targets avoided).
- Do NOT reintroduce the switch-expression payload-capture emission-bug class (statement switches only for captures); range switches in expression position without payload are proven safe.
- Every observable line must be deterministic (fixed world seed; REPL arena order deterministic) and reachable only via the new feed/char.
- Absolute `(address)` integers are implementation-coupled: goldens regenerate only if perm-arena allocation order changes; determinism must be re-verified 3× at authoring.

## Risks

- Golden bytes for `(address)`/`(ptr-check)` depend on arena layout — stable today, flagged as re-derivable.
- Network demo is the only genuinely new executable (a real TCP client) and the only timed/socket surface; timeout-guarded runs required.
- lisp REPL print formatting and prompt bytes must be captured, not assumed.
- Rogue `save.dat`/`load` path must be re-verified after the FileHeader edit (byte-identical to the pre-edit format).

## Out of Scope

- `sf/src` compiler changes; the packed/arbitrary-int F-plans; `json_parser_upgraded`; any edit to original (non-`_upgraded`) example dirs; QUICK_REF gate rows for the four gate programs.
