# slice_index_field_store_xmod — D5 lost store through a slice-index aggregate lvalue  [Task I5, 2026-10-09]

**Status:** OPEN compiler defect (investigated by I5; read-only on the compiler). No
`sf/src/**` change (fix is F5, planned).
**Corpus:** standalone reproducer. `main.zig` is auto-discovered by
`scripts/corpus/list_corpus_dirs.sh`. This is a **runtime** defect: pre-fix it emits C
that `gcc` accepts, so the compile-only classify is **OK** (it does **not** add a FAIL).
The gate is the runtime assertion below — classify alone cannot see a lost write.

## What it tests

A struct `Peer { peer_id: [4]u8, score: u32 }` stored in a fixed array and in a slice.
The program performs three field-index stores and then reads each back and prints it:

```zig
var backing: [4]Peer = undefined;
var p: Peer = undefined;
p.peer_id[0] = 9;              // control: local struct (addressed correctly today)
backing[1].peer_id[1] = 11;    // fixed-array element (store lost pre-fix)
var peers: []Peer = backing[0..2];
peers[1].peer_id[2] = 22;      // slice element (store lost pre-fix; the z9torr shape)
```

Expected stdout (`expected.txt`, post-fix): `9\n11\n22\nslice_index_field_store ok\n`,
exit 0 (`expected.rc`). Pre-fix the read-backs print the **pre-store** value.

## Pre-fix measurement (seed v94, `/tmp/z9_m0_seed/zig1_5_clean`)

`zig1 -ffast` accepts the program (emit rc 0); `build_target.sh` links clean (rc 0). The
run **succeeds** (rc 0) but prints the wrong values — the write is silently lost:

```
$ /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/d5out repro/mi_matrix/slice_index_field_store_xmod/main.zig
$ sh /tmp/d5out/build_target.sh linux /tmp/d5out/prog     # rc 0
$ /tmp/d5out/prog
9
0
0
slice_index_field_store FAIL
$ echo $?
0
```

Emitted `main_B1564416.c` (the by-value materialisation, exactly the D5 ledger shape):

```c
zT_11 = 1;
zT_12 = zG_49D8D4BE_backing[zT_11];   /* Peer copied BY VALUE into a local temp   */
zT_13 = zT_12.peer_id;                /* pointer into the LOCAL copy              */
zT_14 = 1;
zT_13[zT_14] = zT_9;                  /* store lands in the temp, not backing[1]  */
...
zT_26 = peers.ptr;
zT_27 = 1;
zT_28 = zT_26[zT_27];                 /* slice element copied BY VALUE            */
zT_29 = zT_28.peer_id;                /* pointer into the LOCAL copy              */
zT_30 = 2;
zT_29[zT_30] = zT_25;                 /* store lost                               */
```

The control (`p.peer_id[0] = 9`) emits `zT_4 = p.peer_id; zT_4[0] = zT_3;` — `p` is a local
struct, so `p.peer_id` decays to a pointer into the real `p`. The loss only occurs when the
base is itself an **index** (`backing[i]` / `peers.ptr[i]`) whose element is materialised by
value before the field is accessed.

## Compile-only classify is insufficient

Corpus-classify emulation (canonical flags):

```sh
Z=/tmp/z9_m0_seed/zig1_5_clean
OUT=$(mktemp -d /tmp/d5class.XXXXXX)
$Z -ffast --dump-c89 --output-dir "$OUT" repro/mi_matrix/slice_index_field_store_xmod/main.zig   # rc 0
for f in "$OUT"/*.c; do
  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null     # rc 0
done
# -> classification OK (6 .c, gcc clean). The lost write is invisible here.
```

Therefore this repro adds one **OK** to the corpus (no FAIL increase); its correctness gate
is the runtime stdout comparison against `expected.txt`.

## Full link/run reproducer

```sh
Z=/tmp/z9_m0_seed/zig1_5_clean
O=/tmp/d5out; rm -rf "$O"; mkdir -p "$O"
$Z -ffast -o "$O" repro/mi_matrix/slice_index_field_store_xmod/main.zig   # rc 0
sh "$O/build_target.sh" linux "$O/prog"                                   # rc 0
"$O/prog" > /tmp/d5.actual; diff -u repro/mi_matrix/slice_index_field_store_xmod/expected.txt /tmp/d5.actual
# -> pre-fix diff: lines 2/3 (11->0, 22->0) and the status line (ok->FAIL)
```

## Zig semantics (the reference)

In Zig `s[i].field[j] = x` is a store through the **lvalue** `&s[i].field[j]`. The whole
index/field chain denotes a location; the backend must address it once and write there —
never copy the element and write into the copy. Z98 must reproduce that.

## Locus (read-only analysis)

**Lowering (root cause).** `sf/src/lower.zig` `lowerAssignLValue`, `index_access` arm
**`:2484-2531`**:

- `:2487` `var base_temp = lowerExpr(self, indexBaseAfterArrayDeref(self, lv_node.child_0));`
  lowers the base **by value**. For `s[i].field[j]` the outer node is `index_access` whose
  `child_0` is `field_access(index_access(s, i), field)`; `lowerExpr` on that field access
  yields a **copy** of the indexed element's field.
- The address-taking path exists only for the **tuple** sub-case
  (`:2493-2508`, gated on the base temp being a `tuple_type`); a struct base falls through
  to the value path and the final `assign_index` at `:2531`.

Correct sibling: `lowerFieldStore` **`:2878-2928`** takes nested bases by address —
- `:2878-2909` an `index_access` base: `slice_temp = lowerExpr(child_0.child_0)` then
  `maybeExtractSlicePtr` + `load_index{decay=1}` / `binary ADD(ptr, idx)` to form the element
  **address**;
- `:2910-2928` a `field_access`/`deref`/`paren_expr` base: `lowerLValueAddr` (or `lowerExpr`
  when the nested base is already a pointer).
This is why a direct `s[i].field = x` (handled by `lowerFieldStore`) is correct while
`s[i].field[j] = x` (handled by `lowerAssignLValue`) is not.

**Emission chain.** `emitBaseIdxAccess` **`c89_emit.zig:204-267`** (`load` copy at
`:229-251`; `assign` at `:252-266`), `.assign_index` **`:7226-7271`**, `load_index`
**`:7593-7596`**, `load_field` **`:7456-7513`**. The emitter faithfully renders the
value-copying LIR it is given; the defect originates in lowering.

**D5 ledger cross-check** (`examples/torrent_example_defects.md`): the emitted pattern
`zT = peers.ptr[i]; p = zT.field; p[j] = …` (from `/tmp/z9_linbin/main_B8D622A5.c`,
`spawnPeerAt`) matches this repro's `zT_28 = zT_26[zT_27]; zT_29 = zT_28.peer_id;
zT_29[zT_30] = …` byte-for-byte in shape. The z9torr `g_sched.peers[slot].peer_id[pid_i] =
peer_id[pid_i]` is the same lvalue chain.

## Fix (task F5, planned)

Route non-tuple index-assign bases through address-taking exactly as `lowerFieldStore`
(`lowerLValueAddr` on a `field_access`/`index_access`/`deref`/`paren_expr` base), so the
whole chain `(slice.ptr + idx)->field[…]` is addressed once and the store lands in the
element. The array branch of `lowerFieldStore` is already correct; only the general
`lowerAssignLValue` `index_access` arm needs the address path. This touches the core lvalue
path, so the full corpus/examples/goldens/4-MD5 battery is the safety net.

## Correlation vs D3/D4 (and D1/D2)

**D5 is distinct from D3/D4.** D3/D4 (`repro/mi_matrix/async_frame_global_xmod/`,
`async_frame_structret_xmod/`) are **async frame-save temp-declaration** defects in
`async_state_machine.zig`/`c89_emit.zig` — they fail at `gcc` (undeclared `zT_N`) and are
compile-time-visible. D5 is a **synchronous lvalue-lowering** defect in `lower.zig`; it
compiles/links cleanly and fails only at runtime. They share no site or subsystem (per the
spec §4 hypothesis: D3≡D4 expected; D5 distinct).

**D5 is also distinct from D1/D2**, which are C-identifier/type-name *emission* defects.
D5 is lvalue addressing in *lowering* plus the emission chain that consumes it.

## Gate note

This I-task records the pre-fix runtime result and localises the defect; it makes **no
compiler change**. Post-fix (F5) the runtime output must move `9\n0\n0\nslice_index_field_store
FAIL\n` → `9\n11\n22\nslice_index_field_store ok\n` (diff against `expected.txt`).
