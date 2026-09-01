# widthbits_union_intconst_xmod — width_bits u8 overflow on tagged-union `.int_const` (Task R1, 2026-08-20)

## Purpose
RED reproducer for the self-compile PANIC `integer cast overflow` at
`sf/src/c89_emit.zig:5002`: `width_bits: u8` overflows when the `.int_const`
result temp's hoisted type is a tagged union **> 31 bytes** (`size * 8 > 255`).
Task R1 produces this fixture, re-verifies the 2 sibling width-computation
sites, and does a whole-tree scan for the defect class. ZERO compiler source
changes (I-task/F-task own those).

## Fixture (verbatim)
```zig
const std = @import("std");

const Big = union(enum) {
    a: void,
    b: [36]u8,
};

pub fn main() void {
    var u: Big = .a;
    const v = switch (u) {
        .a => @intCast(i32, 0),
        .b => @intCast(i32, 1),
        else => @intCast(i32, 99),
    };
    std.io.printInt(v);
}
```
The brief's example shape (`{ a: u32, b: [36]u8 }` + `u = .b` +
`@enumToInt(u)`) is REJECTED by the current binary (error[3008] "enum literal
member requires payload" for `.b` since `b: [36]u8` has a payload, plus
`@enumToInt` on a union value / `undefined`-init issues). Escalation: payload
member `b: [36]u8` (union = 40 bytes) kept for size; the enum literal is `.a`
(a `void`-payload tag, legal as a bare enum literal). This mirrors the
self-compile pattern: `enum_literal` whose resolved type is a tagged union →
`emitTaggedUnionInit` (lower.zig:1462-1463) → `.int_const` with result temp of
union type → c89_emit.zig:4984-5007 `is_tagged_union=1` path.

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1, no rebuild)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1 main.zig
rc=134
stdout: PANIC: integer cast overflow at /tmp/fx_subfolder/zig_runtime.h:154
stderr: timeout: the monitored command dumped core
```
- **Exact union byte size: 40** (measured via `@sizeOf(Big)` probe = 40;
  tag 4 + payload [36]u8; 40*8 = 320 > 255 → u8 overflow). The brief's note
  that 32 bytes "does not overflow" is WRONG: 32*8 = 256 > 255 → would overflow
  too. Strict threshold is **size > 31 bytes** (`size*8 > 255`).
- **PANIC locus:** `c89_emit.zig:5002` (`width_bits = @intCast(u8, bty.size * @intCast(u32, 8))`)
  in the `.int_const` emitter. Marker trace (`--markers`) shows hoisted temp
  declarations `HT:zT_0...HT:zT_8` (emission phase entered) then
  `VFLOW:rnt1` + `INT:dup178` (result temp `zT_178`, a Big-typed temp, resolved
  during emission) → PANIC. Partial `.c` truncated mid-function after the temp
  declarations, confirming the abort is in body emission.
- No `.c` for main is produced (partial 227-byte stub with only the function
  header + temp decls).

## Sibling-site re-verification (Step 3)

### Site B: `c89_emit.zig:3190` (`emitSatBinary`) — SAFE
```zig
var width_bits: u8 = @intCast(u8, ty.size * @intCast(u32, 8));
```
- **Only caller:** `c89_emit.zig:4862`, in the `.binary` LIR emitter, reached
  only when `b.op >= 19` (BIN_SADD=19/SSUB=20/SMUL=21/SSHL=22, lower.zig:57-60).
- Sat LIR ops are emitted only from `AstKind.sat_add/sat_sub/sat_mul/sat_shl`
  (lower.zig:1603-1610, 3989-3995, 4939-4945). Those AST kinds resolve via
  `semanticAnalyzerResolveArithmetic` (sat_+,-,* → requires
  `typeRegistryIsNumeric` on both operands, else returns TYPE_VOID,
  semantic_analyzer.zig:639) / `semanticAnalyzerResolveBitwise` (sat_shl →
  requires `typeRegistryIsInteger`, semantic_analyzer.zig:654).
- `wty` passed to emitSatBinary is resolved via `getTempTypeInfo`
  (result/lhs/rhs hoisted temps) — always an integer/numeric type, size ≤ 8 →
  width ≤ 64. No overflow.
- **Probe evidence:** `var r = u +| 1` where `u: Big` (40-byte union) is
  REJECTED by semantic analysis (`error[3000] cannot declare variable of type
  void`, rc=2) BEFORE emission — sat-math on union operands never reaches
  emitSatBinary. Static reachability + probe both conclusive.
- Helper params `satMaxLit/satMinLit/satMinMagLit/satMaxULit`
  (c89_emit.zig:3160/3167/3174/3181) and internal consumers (:3313, :3428) all
  receive this ≤64 value. SAFE.

### Site C: `comptime_eval.zig:139` (int_cast fold) — **LIVE 2nd overflow site (corrects spec)**
```zig
var wb: u8 = @intCast(u8, ty.size * @intCast(u32, 8));
```
- Reached from `comptimeEvalBuiltin`'s `int_cast_id` branch (comptime_eval.zig:132),
  called by `comptimeEvalEvaluate` (main.zig:396, iterating every
  `builtin_call` node in phase_ComptimeEvaluation, which runs BEFORE semantic
  analysis at main.zig:219 vs :220) and by var_decl-init folding (main.zig:406).
- **The spec's blast-radius table claims "integer types only, safe today" —
  this is INCORRECT.** Probe `const x = @intCast(Big, 5);` where `Big` is the
  40-byte union PANICS here: `rc=134`, `PANIC: integer cast overflow at
  zig_runtime.h:154`. Marker trace shows `CE` (phase_ComptimeEvaluation) then
  `RTD:n12` (resolving the `@intCast` target type) → PANIC, with NO emission
  markers. The fold computes `wb` from the **target** type of `@intCast`, and a
  >31-byte union target overflows u8.
- Control probe: `@intCast(Small, 5)` where `Small = union(enum){ a: void, b:
  u8 }` (4 bytes) compiles rc=0 and emits `zT_1.tag = 5;` — proving the fold IS
  hit for union targets and only overflows at >31 bytes.
- `@intCast(Big, n)` with a runtime value (not comptime-foldable) does NOT hit
  the fold (rc=0) — the fold requires a comptime-known inner value.
- **Conclusion:** comptime_eval.zig:139 is a second LIVE width overflow site of
  the same class (reachable from a >31-byte union `@intCast` target with a
  comptime value), though it is NOT the self-compile's locus (self-compile dies
  at c89_emit.zig:5002 first). Both sites need the u32 widening; the spec's
  "safe today" label for this site is wrong.

## Whole-tree scan (Step 4) — results

`grep -rn "@intCast(u8, .*size \* @intCast(u32, 8))" sf/src/` → **exactly 3**
sites (spec's 3-site list is COMPLETE):
| Site | File:line | Reachable types | Verdict |
|---|---|---|---|
| A | `c89_emit.zig:5002` (`.int_const`) | any hoisted temp type (tagged union, …) | **LIVE** (self-compile locus; this fixture reproduces rc=134) |
| B | `c89_emit.zig:3190` (`emitSatBinary`) | integer sat-math temps only (size ≤ 8, width ≤ 64) | safe today (int-only, sema rejects union operands) |
| C | `comptime_eval.zig:139` (int_cast fold) | ANY resolvable `@intCast` target type incl. >31-byte unions (with comptime inner) | **LIVE** (probe main2 rc=134; spec's "integer types only" is wrong) |

`grep -rn "width_bits" sf/src/` → 61 hits; full width-typed surface:
- `c89_emit.zig:4992` `var width_bits: u8` decl; `:5002` cast (SITE A);
  consumers `:5020/:5021/:5024/:5028/:5029` (signed masking, dead on
  `is_signed=0` path).
- `c89_emit.zig:3190` (SITE B); helpers `:3160/:3167/:3174/:3181` (params);
  consumers `:3191-3196`, `:3313`, `:3428`.
- `comptime_eval.zig:16` `ComptimeVal.width_bits: u8`; `:56-57` width-max
  arithmetic; `:139` (SITE C); literal constructions `:119/:128/:160/:173/:175/:177/:178/:196`;
  consumers `:183-188` (negate), `:203` (bit_not).
- **No cross-file consumer of `ComptimeVal.width_bits`** (all 61 hits are
  within c89_emit.zig + comptime_eval.zig).

`grep -rn "@intCast(u8, .*size" sf/src/` (broader) → all other hits are
array-index / char-literal / loop-guard casts (e.g. hash.zig:89, c89_emit char
buffer writes, lower.zig flags) — none multiply a type size into a width; no
additional overflow-capable width computation. `intCastTypeBits`
(lower.zig:1059-1067) returns 0 for non-int types — no width from size there.

## Post-fix expectation
`sf/src/c89_emit.zig:5002` (+ :4992) and `comptime_eval.zig:139` widened
u8→u32 per Option B: this fixture flips RED→GREEN (dump rc=0, `.tag = 0;`
emitted for `var u: Big = .a;`, gcc rc=0, run rc=0 prints `0`). Site B widenings
(:3190 + 4 helper params) are lockstep but behavior-neutral. Self-compile
advances past c89_emit.zig:5002.
