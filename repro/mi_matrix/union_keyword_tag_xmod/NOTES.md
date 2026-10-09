# union_keyword_tag_xmod — D1 repro (C keyword as a `union(enum)` tag)  [Task I1, 2026-10-09]

## What it tests
A tagged union whose variant tag is a **C keyword**: `int`. In Zig/Z98 any
identifier is a legal `union(enum)` tag (`int`, `long`, `switch`, … are not Zig
keywords), so `V = union(enum) { int: i64, bytes: []const u8, flag: bool }` is
valid Z98. It constructs `V{ .int = 3 }`, switches on all three variants, prints
`3`, and writes a newline. Expected stdout after a correct fix: `3\n`.

## Zig semantics (the reference)
Zig permits any identifier as a tagged-union tag; the C89 backend must therefore
emit a **valid C identifier** for every variant member (C-keyword-mangle the
union member name, or use a stable non-keyword member name) — at the payload
declaration *and* at every access site. `int` must not be written verbatim into
the emitted C.

## Pre-fix symptom (seed v94, /tmp/z9_m0_seed/zig1_5_clean)
`zig1` accepts the program; the emitted C is rejected by gcc.

Emitted `main_9290789A.h` (payload union member):
```c
struct zT_D30C0E69_V {
	unsigned int tag;
	union {
		char _dummy;
		struct { zT_C69B2266_i64 _0; } int;   /* <-- C keyword member name */
		struct { zT_8F083A69_Slice_zT_0B42B2F8_u _0; } bytes;
		struct { unsigned char _0; } flag;
	} payload;
};
```
Emitted `main_9290789A.c` (payload designator):
```c
zT_1.payload.int._0 = zT_3;   /* construction */
x = v.payload.int._0;         /* .int capture  */
```

gcc `-m32 -std=c89` errors:
```
main_9290789A.h:18:48: error: expected ';', identifier or '(' before 'int'
main_9290789A.c:19:18: error: expected identifier before 'int'
main_9290789A.c:29:19: error: expected identifier before 'int'
```

The tag **constants** are safe (`#define zT_D30C0E69_V_int 0` — prefixed), and
switch dispatch compares numeric case values (`case 0: …`) / `.tag`, so only the
payload member **declaration** and payload **access** leak the raw name.
`@"int"` (the usual Zig escape) is rejected by Z98 with `error[4]`, so the tag
cannot be spelled around.

## Compiler locus (seed v94, `sf/src/c89_emit.zig`)
- **Declaration:** `emitTaggedUnionType` (`:1921`). It reads the variant field
  name `fe.name_id` at **`:2013`** and writes it verbatim as the C union member at
  **`:2020`** (`" _0; } "` then `fe_name` then `";\n"`) — no C-keyword mangling.
- **Access:** `emitVariantFieldPayload` (`:419`; called from `resolveFieldAccess`
  `:499`, shared by `.assign_field` / `.load_field` / `.store_field`). It reads
  `evp_vfe.name_id` at **`:435`** and writes it verbatim into the payload
  designator `.payload.<name>._<sub>` at **`:436`**.
- The tag-constant `#define` names (`:1973-1982`, prefix `zTU_<base>_`) and switch
  dispatch are already safe.
- Adjacent same-class site (not D1's trigger): bare `union_type` member emission
  `emitUnionType` `:2104`/`:2109` writes `fe.name_id` verbatim too.

## Classification
**FAIL pre-fix → expected OK post-fix (task F1).** The compile-only corpus
classify cannot observe the (currently unreachable) runtime; the pre-fix FAIL is
the gcc reject above. After F1 the repro must compile, link, and run printing
`3\n`.

## Exact repro commands
```
# corpus-universe classify (single-dir emulation); gcc flags are the canonical set
Z=/tmp/z9_m0_seed/zig1_5_clean
OUT=$(mktemp -d /tmp/d1corpus.XXXXXX)
$Z -ffast --dump-c89 --output-dir "$OUT" repro/mi_matrix/union_keyword_tag_xmod/main.zig
for f in "$OUT"/*.c; do
  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null
done
# -> main_*.h:18 / main_*.c:19,29  error: expected identifier before 'int'

# full link path
O=/tmp/d1linkout; rm -rf "$O"; mkdir -p "$O"
$Z -ffast -o "$O" repro/mi_matrix/union_keyword_tag_xmod/main.zig
sh "$O/build_target.sh" linux "$O/prog"
# -> rc=1, same gcc errors
```

## Perf/gates
- Corpus baseline at this HEAD: `1115 = 941 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`
  (documented plan baseline `1097 = 923/58/116` was cut at seed HEAD `78dd4593`;
  the +18 dirs are all OK M4 repros added after the seed cut). This new dir is
  expected to move FAIL→OK after F1 (net: this repro adds 1 FAIL pre-fix).
- Stdlib: 283 PASS / 0 FAIL. Seed v94 fixed point `296c48f676deec290387b57132e4e2bd`.
