# slice_index_field_store_oob_xmod — D5/F6 lost `-fsafe` root-index check  [Task F6, 2026-10-10]

**Status:** FIXED by F6 (restore the `-fsafe` bounds check for the D5 chain root index).
**Corpus:** standalone reproducer. `main.zig` is auto-discovered by
`scripts/corpus/list_corpus_dirs.sh`. This is a **runtime** defect: pre-fix the C compiles,
so the compile-only classify is **OK** (no FAIL). The gate is the runtime trap below.

## What it tests

`peers[i].peer_id[0] = 1` with `i = 5` on a length-2 slice (`backing[0..2]`). The D5
address-taking path (`lowerAssignLValue` -> `lowerLValueAddr`) bypassed the by-value element
read that carried the `-fsafe` bounds check, so the out-of-range ROOT index did **not** trap.

Expected (`-fsafe`, `expected.rc=133`, empty `expected.txt`): `pal_trap` -> SIGTRAP, no stdout.

## Pre-fix measurement (v95 / F5 build)

```
$ zig1 -fsafe -o /tmp/oob repro/mi_matrix/slice_index_field_store_oob_xmod/main.zig   # rc 0
$ sh /tmp/oob/build_target.sh linux /tmp/oob/prog                                     # rc 0
$ /tmp/oob/prog ; echo $?                                                             # prints "no trap", rc 0
```

Emitted `-fsafe` C (pre-fix) went straight from `zT = peers.ptr` to the address add with no
`peers.len` check — the inner `peer_id[j]` check remained, but the root index was unchecked.

## Post-fix (F6)

`lowerLValueAddr` now takes a `safe_check: u8`; only the D5 call site opts in. Emitted
`-fsafe` C regains the pre-D5 shape:

```c
zT_15 = peers.len;
zT_16 = i < zT_15;
if (!(zT_16)) { pal_trap(); }
zT_17 = zT_14 + i;
zT_18 = &zT_17->peer_id;
```

Run traps (rc 133). `-ffast` is byte-identical pre/post (no check). See
`sf/docs/tech_docs/08_c89_emission.md` §1.13.

## Reproduce

```sh
Z=/tmp/f6/post/zig1_5_clean
O=/tmp/f6/oob; rm -rf "$O"; mkdir -p "$O"
$Z -fsafe -o "$O" repro/mi_matrix/slice_index_field_store_oob_xmod/main.zig   # rc 0
sh "$O/build_target.sh" linux "$O/prog"                                       # rc 0
"$O/prog"; echo "rc=$?"                                                       # rc=133, no stdout
```
