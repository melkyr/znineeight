# Task 1 Report: `const_alias_prepass.zig`

**Commit:** `4da84fc1` — "feat: add topo-sort const-alias pre-pass between symbol reg and type resolution"
**Files:** `sf/src/const_alias_prepass.zig` (new, 240 lines), `sf/src/main.zig` (+2 lines)

## What was built

- `sf/src/const_alias_prepass.zig` with:
  - `resolveWellKnownTypeName([]const u8) u32` — maps primitive type names to `TYPE_*`.
  - top-level `growDep(...)` helper (edge-array growth).
  - `pub fn constAliasPrepass(symbol_reg, registry, interner, store, perm_alloc) void` — 4-phase pass:
    1. catalog unresolved `kind==global`, `type_id==0` `var_decl` aliases whose init is an `ident_expr`; build reverse edges keyed by dependency name;
    2. seed a worklist by resolving terminal aliases (raw nameCache id, composite-key scan across modules, then well-known-type match);
    3. Kahn propagation across the alias DAG, setting `sym.type_id` and `nameCachePut` for each resolved alias;
    4. residuals left for sema.
- Wired into `main.zig` `phase_TypeResolution`, immediately after `registerModuleSymbols` and before type resolution.

## Deviations from the brief (all required for zig0 / correctness)

1. **`growDep` made top-level** — brief flagged this; zig0 rejects nested fns. Uses literal `4` instead of the in-function `SZ_U32`.
2. **Single-line param list** — zig0's parser errored ("Expected parameter name") on the multi-line signature with trailing comma. Collapsed to one line.
3. **`var resolved: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED)`** — zig0 dropped the C declaration when a `var` is initialized directly to an imported comptime const then reassigned (produced `'resolved' undeclared`). Wrapping in `@intCast` forces a runtime var (matches `semantic_analyzer.zig:1346`).
4. **Corrected array sizing (memory-safety fixes over the brief's literal text):**
   - `alias_sym_id`: brief allocated `SZ_U8 * tl * 2` (bytes) for a `[*]u32` indexed to `2*tl-1`. Changed to `SZ_U32 * tl * 2`.
   - `dep_head`: brief sized it `tl`, but it is indexed by **canonical interner IDs** (which can far exceed the symbol count). Sized to `interner.entries_len` (min `tl`) and initialized over that range. Without this it OOBs on any non-trivial program.
5. **Composite nameCache keys via `x * 4294967296 + y`** instead of `(x << 32) | y`, matching the existing convention in `symbol_registrator.zig:250`, `comptime_eval.zig:65`, `main.zig:310`, and avoiding zig0 shift-amount typing.
6. **All `[*]` pointer indices cast to `usize`** (codebase always does this, e.g. `string_interner.zig:98`); `sandAlloc` size arithmetic cast to `usize` per Z98 rule.

## Verification results

| Gate | Command | Result | Expected |
|------|---------|--------|----------|
| Build zig1 | `zig0 -> gcc -m32 -std=c89` | **0 errors** ✅ | 0 |
| file_const_single | dump-c89 + gcc | **3** ⚠️ | 0 |
| json_parser | dump-c89 + gcc | **13** ⚠️ | < 13 |
| mandelbrot | dump-c89 + gcc | **0** ✅ | 0 |
| game_of_life | dump-c89 + gcc | **0** ✅ | 0 |
| mud_server | dump-c89 + gcc | **1** ⚠️ | 0 |

### Important finding: the numeric repro gates are not movable by Task 1 alone

I built a **no-prepass baseline** (`main.zig` with the call disabled) and compared:

- `file_const_single`: **3 errors with AND without** the prepass — identical.
- `json_parser`: **13 with AND without** — identical.
- `mud_server`: **1 with AND without** — identical (pre-existing).
- mandelbrot / game_of_life: 0 both ways.

**Root cause:** On all current repros the prepass finds *nothing to resolve* (`alias_count == 0`, confirmed: no `KAHN:*` markers emitted). The only alias in these inputs is `pub const File = void;`, and `void` is pre-seeded into the name cache as interner id 1 → `TYPE_VOID` at type-registry init, so `symbol_registrator` already resolves it to `type_alias` during registration (marker `RCA:H1`). The prepass's `kind==global && type_id==0` filter correctly skips it.

The 3 residual `file_const_single` errors and the 13 `json_parser` errors are an **`orelse` / optional-pointer lowering** defect (`zT_3` unwrap temp typed `int`, `x` typed as the full optional instead of `*void`), located in `lower.zig`/`semantic_analyzer.zig` — outside the scope of `const_alias_prepass.zig`. These are the target of the remaining tasks (2/3).

### Proof the prepass itself works

On a constructed out-of-order chain (`pub const A = B; pub const B = C; pub const C = u32;`) the pass emits:

```
KAHN:start
KAHN:res1  KAHN:rt10   (B -> u32, TYPE_U32=10)
KAHN:res0  KAHN:rt10   (A propagated -> u32)
KAHN:end
```

i.e. topo-sort seed + propagation resolve both `A` and `B` to `u32`. Generated C compiles with 0 errors.

## Conclusion

Task 1 deliverable is complete: the pre-pass compiles cleanly into zig1 (0 gcc errors), is correctly wired between symbol registration and type resolution, is functionally verified via markers, and introduces **zero regressions** (every baseline is byte-for-byte identical in error count vs. the no-prepass build). The unmet numeric gates (`file_const_single=0`, `json_parser<13`, `mud_server=0`) are downstream `orelse`/optional lowering issues that this task's infrastructure does not and cannot address on its own; they depend on Tasks 2–3.
