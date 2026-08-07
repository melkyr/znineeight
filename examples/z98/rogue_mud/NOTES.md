# rogue_mud — Z98 Example

**Status:** BROKEN

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** N/A (dump fails)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/rogue_mud/main.zig -o build/rogue_mud
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/rogue_mud/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
N/A — does not build
```

## Notes
Multi-file: 14+ modules. Dump rc=2, syntax errors. Uses `catch |err| { ...; s }` block-expression pattern unsupported by Z98 parser. Also uses `fn(...)` ptr types. Syntax incompatibilities with Z98 parser.

### Emission-defect status (2026-08-07, rogue_mud emission-defects plan closeout)

The 5 C89 emission defects that blocked end-to-end compilation are all FIXED on branch
`zig1_start` (each gated by a defensive repro in `repro/mi_matrix/`, all runtime-verified):

| Gap | Fix (commit) | Repro |
|-----|--------------|-------|
| #1+#2 duplicate-typed struct fields (topo-sort) | F1 Option B, `c89_emit.zig` `tstEdgesCount`/`tstEdgesFill` dedupe (a5ac4598) | `dup_optptr_field_emit`, `dup_val_field_emit` |
| #3 `undefined` array struct-literal init | F2 Option A, `lower.zig` skip `assign_field` (ba89a6e0) | `undef_arr_struct_literal` |
| #4 cross-module `pub const` | F3 Option C, `lower.zig` literal fold at ref site (317f3a82) | `xmod_pub_const_global` |
| #5 switch mixed-case arg typing | F4 Option A, `semantic_analyzer.zig:1167` return→continue (b1b3f7e9) | `switch_mixed_case_argtype` |

Corpus (2026-08-07 F5 sweep): 215 repros, OK=208/FAIL=3/gg=4 (raw 7); 4 MD5 gates byte-identical
(mud `906fa59c…` post-F2 re-baseline). **Still blocking rogue_mud itself:** the source remains
syntactically incompatible with the Z98 parser (catch-block expr, fn-pointer types — see above),
and the out-of-scope char_literal switch-`case`-label bug (lower.zig:3858-3860/:3121-3123) would
leave rogue_mud's input switch (`main.zig:236-256`) runtime-dead even after the 5 fixes. Both
tracked as follow-ups, NOT compiler defects fixed in this plan.
