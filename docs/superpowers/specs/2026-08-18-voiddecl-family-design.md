# Self-Compile VOID-decl Family Design

> **Date:** 2026-08-18
> **Status:** Approved by operator (2026-08-18)
> **Basis:** Self-compile state review at HEAD `b86279d4` — 9 residual `error[3000]` "cannot declare variable of type void" sites.

## Problem

After the u16→u32 payload/index sweep (silent-drop plan), self-compile reaches semantic analysis with modules 1–4 registering cleanly, but still emits **9× `error[3000]: cannot declare variable of type void`** across `main.zig`, `symbol_registrator.zig`, and `lower.zig`. These are the same VOID-decl family that previously counted 213x; the residual 9 are newly-reached sites, not regressions.

The 9 sites group into **4 shape classes** (correcting for the diagnostic span-drift that points the caret at the following statement):

| Shape | Sites | Failing `var` declaration |
|-------|-------|---------------------------|
| A. Value-position `if (cond) A else B` (no optional, no capture, const branches) | `lower.zig:4410` | `var cmp_op = if (pattern.kind == AstKind.range_inclusive) BIN_LE else BIN_LT;` |
| B. Switch-expression init + enum annotation | `symbol_registrator.zig:258` (var at :259) | `var type_kind: TypeKind = switch (init_node.kind) { … };` |
| C. u64 bitwise-and + intCast init (post-F1 payload u32→u64) | `symbol_registrator.zig:357` | `var name_id: u32 = @intCast(u32, node.payload & @intCast(u64, 0xFFFFFFFF));` |
| D. Struct-literal init + cross-module struct annotation | `main.zig:588` | `var sem_ctx: SemanticContext = SemanticContext{ .store = …, .registry = … };` |
| E. Field-access index chain → union element (inferred) | `lower.zig:5218,5275,5319,5395,5403` (5×) | `var inst = blk.insts.items[ii];` (`LirInst` = tagged union) |

## Suspected distinct root causes

1. **IFEXPR** (shape A) — non-optional value-position `if (cond) A else B` resolves to void. Related to, but distinct from, the F-PARSERGAP capture work (`if (opt) |cap| …`); this is the plain `if (bool) …` value form.
2. **SWITCHEXPR** (shape B) — `switch` as a value expression (typed by enum annotation) resolves to void.
3. **U64CAST** (shape C) — u64 `&` / `@intCast(u32, u64)` / `0xFFFFFFFF`-class literal typing resolves to void. Strong candidate for a post-F1 regression (AstNode.payload widened u32→u64; these sites read the low 32 bits).
4. **XMODTYPE** (shapes D+E) — cross-module struct (`SemanticContext`) and tagged-union (`LirInst`) type references in annotation position and through multi-hop field-access chains resolve to void. This is the unresolved lead from the silent-drop R2 ladder ("explicit cross-module type ref trips at N=3").

## Design

Investigation-first with the operator-mandated cadence: **R (repro) → I (investigation, read-only) → STOP (consolidated ruling) → F (placeholder fixes) → GATE → M-FINAL.**

### Phase R — 4 repros, each minimal + type-kind matrix sweep

| Repr | Fixture dir | Core construct (RED) | Matrix sweep (other cases) |
|------|-------------|----------------------|---------------------------|
| R1 | `voiddecl_ifexpr_xmod` | `var cmp_op = if (cond) BIN_LE else BIN_LT;` | cond bool vs optional; branch types: u8 const, enum const, bool const, struct value |
| R2 | `voiddecl_switchexpr_xmod` | `var t: TypeKind = switch (x) { a => .one, else => .two };` | switch returning enum / struct / union / int |
| R3 | `voiddecl_u64cast_xmod` | `var n: u32 = @intCast(u32, p & @intCast(u64, 0xFFFFFFFF));` | u64 `&`/`|`/`^`, `@intCast(u32,u64)` + reverse, literal `0xFFFFFFFF`/`0xFFFFFFFFFFFFFFFF` typing |
| R4 | `voiddecl_xmodtype_xmod` | cross-module `var s: T = T{...}` (struct w/ pointer fields) + `var inst = list.items[i]` (tagged union) | struct / union / tagged-union / enum / error-set, in annotation vs inferred positions |

Each repro: RED = `error[3000]` / void fallback; GREEN = correct output; `NOTES.md` records the matrix results (which sibling kinds also fail vs pass) — this feeds the I-task blast-radius analysis.

### Phase I — 4 read-only investigations

- **I-IFEXPR**: non-optional value-position `if (cond) A else B` → void. Locus: `semanticAnalyzerResolveExpr` if_expr arm.
- **I-SWITCHEXPR**: `switch` value → void. Locus: switch-expr resolution + enum-annotation path.
- **I-U64CAST**: u64 `&` + `@intCast` + large literal → void. Suspect post-F1 payload-u64 regression.
- **I-XMODTYPE**: cross-module struct/tagged-union refs (annotation + field-access chain) → void.

Each I task is read-only (markers/intrusive fprintf on a `/tmp` copy only), reports root cause + blast radius + byte-identity reasoning, and reverts all instrumentation.

### Phase STOP → F → GATE → M-FINAL

- **STOP**: one consolidated ruling presents all 4 I findings; operator fills the 4 F placeholders.
- **F1..F4**: placeholder fix tasks, one per confirmed root cause.
- **GATE**: corpus sweep + EXPECTED_FAIL version bump + QUICK_REF baseline.
- **M-FINAL**: whole-branch review (base `b86279d4`, requesting-code-review template) + fix wave if needed.

## Constraints

- 4 MD5 gates byte-identical unless operator re-baselines (single-file `--dump-c89 | md5sum`, lisp from repo root): gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`.
- Corpus 277 dirs OK=267/FAIL=6/ICE=0/CRASH=0/GG=4 — no regression. Corpus recipe per-module (`--dump-c89 --output-dir DIR` then gcc each `.c`).
- 21-example matrix 21/21. test_analyzer_bin '5 passed, 4 failed' baseline.
- Z98 dialect: no `anytype`/`@Type`. edit/fastedit ONLY for source. Never touch `sf/build/out_release/`.
- Verification MUST scan the whole tree/closure for the defect class, never stop at first error.
- Zig-spec claims MUST be verified online before acceptance.
- Repros are new fixture dirs only (no emitted-output change); use the existing `/tmp/fx_subfolder/zig1` (no rebuild during R tasks).

## Success criteria

Self-compile advances past the 9 `error[3000]` sites (or the frontier advances to the next recorded blocker, documented not fixed), with all gates green and byte-identity preserved.
