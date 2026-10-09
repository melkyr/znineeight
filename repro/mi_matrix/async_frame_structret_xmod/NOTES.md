# async_frame_structret_xmod — D4 undeclared frame-save temp (by-value struct-return into a module global across a suspension)  [Task I4, 2026-10-09]

**Status:** OPEN compiler defect (investigated by I4; read-only on the compiler). No `sf/src/**` change (fix is F3/F4).
**Corpus:** standalone reproducer. `main.zig` is auto-discovered by
`scripts/corpus/list_corpus_dirs.sh`; pre-fix it is classified **FAIL** (emits C but
`gcc` rejects it) and is expected to move **FAIL→OK** after the shared fix. This
adds one expected pre-fix `FAIL` (the same convention as the D1/D2 repros).

## What it tests

A suspending function (`caller`) assigns a **by-value struct-return result** to a
**module global** and then, inside a loop, takes the address of that global and
passes it to a suspending call at **two** sites (an if/else):

```zig
var g_val: Big = undefined;
fn caller(out: *u32) void {
    g_val = mkBig(1);                 // by-value struct-return -> module global
    var i: u32 = 0;
    while (i < 3) : (i = i + 1) {
        if ((i & 1) == 0) { suspA(&g_val); } else { suspB(&g_val); }
    }
    out.* = g_val.a + g_val.b;
}
```

Expected stdout after a correct fix: `5\n`.

## Pre-fix symptom (seed v94, `/tmp/z9_m0_seed/zig1_5_clean`)

`zig1 -ffast` accepts the program (emit rc 0). The emitted C is rejected by `gcc`:

```
main_09D13793.c:621:15: error: 'zT_20' undeclared (first use in this function); did you mean 'zT_620'?
```

The erroring line is in the frame-save block (`__Z98Step_caller`), storing a
`Big` **value** into a frame slot:

```c
zT_167 = (zT_B8D16159_Big*)(... __az_frame + 68);
*zT_167 = zT_20;                              /* 621: zT_20 never declared */
```

The step-function declaration block declares the neighbouring pointer temps but
**skips** the `Big`-value temp `zT_20` (`repro/mi_matrix/async_frame_structret_xmod`,
emitted `main_09D13793.c:288-291`):

```c
zT_B8D16159_Big* zT_16;
zT_B8D16159_Big* zT_18;
zT_B8D16159_Big* zT_19;
/* zT_20 MISSING (Big value, frame+68) */
zT_B8D16159_Big* zT_21;
```

`zT_20` is only ever written by the resume path (`zT_20 = zT_269;` reloaded from
the frame) and read by the frame save — it has no C producer, because it is a
`load_global` alias (see Locus).

## Locus / D4-specific temp (read-only analysis)

The undeclared temp is **not** the struct-return temporary. The by-value
struct-return result **is** materialised as a named, declared local — e.g. the
zero-initialised `zT_..._Big` temp that receives `mkBig`'s result. The undeclared
temp is the **`load_global` result temp** produced when `&g_val` is lowered:

- `&g_val` (ident lvalue) → `lowerLValueAddr` `sf/src/lower.zig:2264-2268`
  (`operand_temp = lowerExpr(...)`) → `lowerGlobalRef` `:3931-3932`
  (`emitInst(.load_global{...})`). The `load_global` result temp is typed as the
  global's value type (`Big`); the following `addr_of` renders as `&zG_..._g_val`.
- The async frame-layout pass (`sf/src/async_frame_layout.zig:585-623`) hoists any
  temp that is *defined before* and *read after* a suspend point. Because the
  `&g_val` sites are inside a **loop**, the loop back-edge makes these
  `load_global` result temps loop-carried live, so they become
  `ASYNC_FIELD_LIVE` frame fields (the two value temps, one per call site).
- `saveAllFields` (`sf/src/async_state_machine.zig:254-265`) stores the raw
  `fld.temp_id + base`. The emitter's decl loop (`sf/src/c89_emit.zig:3800-3909`)
  suppresses an `.load_global` result's declaration (`d4_nodecl`, marked at
  `:8910`/`:8998`) and relies on `resolveTempName` (`:6614-6628`) to substitute
  the real name from `temp_global_map` (`:7414-7418`).
- `temp_global_map` is populated **lazily, in block emission order**. The frame
  save for the suspend in the loop is emitted **before** the `.load_global`
  instruction that defines `zT_20`, so `resolveTempName` finds no alias entry and
  falls through to the undeclared `mangleTempName` output `zT_20`. Later save
  sites (after that `.load_global` has been emitted) correctly resolve to
  `zG_945B2E6A_g_val`.

The struct-return assignment (`g_val = mkBig(1)`) only changes the surrounding
temp layout/order; it is **not** the cause. Replacing the struct-return
assignment with the D3 field-init form (`g_val.a = 1; …`) reproduces the same
`'zT_NNN' undeclared` defect in this same standalone (only the temp ids shift) —
i.e. the D4 trigger is a variant of the D3 locus, and the two share **one fix**.

## In-example reproducer (the D4 ledger patch; not required now that a standalone exists)

Apply the ledger's D4 diff to `examples/z98/z9torr/peer.zig` (add a module-global
`g_reader`, replace the coroutine-local field-init `reader` with
`g_reader = std_stream.initMsgReader(&peer.sock, peer.read_buf[0..])`, and pass
`&g_reader` to `wire.readMessageAsync*`). Run out of tree so the example tree is
never modified:

```sh
cp -r examples/z98/z9torr /tmp/i4src          # patch /tmp/i4src/peer.zig per D4
mkdir -p /tmp/i4out
/tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/i4out /tmp/i4src/main.zig   # rc 0
sh /tmp/i4out/build_target.sh linux /tmp/i4out/prog                       # rc 1
```

Observed (2026-10-09): the unpatched tree links clean; the D4-patched tree emits

```
peer_E0C135AE.c:4424:16: error: 'zT_563' undeclared (first use in this function); did you mean 'zT_5763'?
peer_E0C135AE.c:4438:16: error: 'zT_577' undeclared (first use in this function); did you mean 'zT_5779'?
```

Both are `MsgReader` **values** at the same frame slots as D3 (offsets 376/424),
and the by-value struct-return temp itself (`zT_398`, `zT_770BDB7D_MsgReader`) is
declared in the step preamble — confirming the undeclared temp is the
`load_global` alias of `g_reader`, not the struct-return temp.

## Exact standalone repro commands

```sh
Z=/tmp/z9_m0_seed/zig1_5_clean
# corpus-universe classify emulation (canonical gcc flags) -> FAIL
OUT=$(mktemp -d /tmp/i4corpus.XXXXXX)
$Z -ffast --dump-c89 --output-dir "$OUT" repro/mi_matrix/async_frame_structret_xmod/main.zig
for f in "$OUT"/*.c; do
  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null
done
# -> main_*.c:621: error: 'zT_20' undeclared

# full link path -> rc 1
O=/tmp/i4linkout; rm -rf "$O"; mkdir -p "$O"
$Z -ffast -o "$O" repro/mi_matrix/async_frame_structret_xmod/main.zig
sh "$O/build_target.sh" linux "$O/prog"
```

## Zig semantics (the reference)

In Zig a coroutine captures referenced state correctly across a suspension; the
emitted frame save must store a **declared** temp (or the global name). Emitted C
must never reference an undeclared `zT_N`. Proper fix (open, F3/F4): declare every
temp the save/restore stores, or populate/pre-resolve the `load_global` alias
before the save block, so the save resolves to the global.

## Correlation vs D3 — **YES (one fix)**

D3 (`repro/mi_matrix/async_frame_global_xmod/NOTES.md`) is the field-init form;
D4 is the struct-return form. Both emit the same shape: `saveAllFields` stores a
loop-carried `load_global` alias of a module global whose declaration the DCE
suppressed, before `temp_global_map` is populated. The frame slots and the
emitter suppression/resolution path are identical. The struct-return temporary is
materialised in both; the undeclared temp is the `&g` `load_global` alias. One fix
covers both.
