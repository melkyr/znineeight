# async_frame_global_xmod — D3 undeclared frame-save temp (global struct address across a suspension)

**Status:** FIXED (F3, commit `06a7a793`, 2026-10-09). The shared D3/D4 fix pre-populates the emitter's `temp_global_map` for every `.load_global` result before body emission, so the frame save/restore at the suspend site resolves the suppressed `load_global` alias to the global name instead of the undeclared `zT_N`. The fix reproduces Zig semantics (a frame save must store a declared temp/global), not merely `gcc` acceptance. (History: investigated by I3, 2026-10-09.)
**Corpus:** NOTES-only. This dir has **no `main.zig`**, so `scripts/corpus/list_corpus_dirs.sh`
does not list it and `scripts/corpus/classify` never sees it — the corpus tally is unchanged.
**Why no standalone:** D3 is temp-layout sensitive; it was **not** reducible to a standalone
two-function program (six standalone variants all linked clean — see
`examples/torrent_example_defects.md` D3 "Reduction attempts"). The faithful reproducer is the
in-example `peer.zig` patch below.

---

## Defect

A coroutine that passes the address of a **module-global struct** to a suspending, cross-module
call (`wire.readMessageAsync`) emits a deferred-frame save whose source is a temp the emitter
**never declares**:

```
peer_CE8C2A2B.c:4428:16: error: 'zT_569' undeclared (first use in this function); did you mean 'zT_5769'?
peer_CE8C2A2B.c:4442:16: error: 'zT_583' undeclared (first use in this function); did you mean 'zT_5843'?
```

The erroring lines are inside `saveAllFields`'s emitted block:

```c
zT_1294 = (zT_770BDB7D_MsgReader*)(... __az_frame + 376);
*zT_1294 = zT_569;                              /* <-- line 4428 */
...
zT_1322 = (zT_770BDB7D_MsgReader*)(... __az_frame + 424);
*zT_1322 = zT_583;                              /* <-- line 4442 */
```

Both `zT_569` and `zT_583` are `MsgReader` **values** saved into the frame. The step-function
declaration block declares the neighbouring pointer temps but **skips** them:

```c
zT_770BDB7D_MsgReader* zT_566;   /* frame+364  (MsgReader*) */
zT_D78E74E2_Rc4*       zT_567;
zT_AE0ED984_Message*   zT_568;
/* zT_569 MISSING (MsgReader value, frame+376) */
zT_770BDB7D_MsgReader* zT_570;   /* frame+396  (MsgReader* = &g_reader) */
```

`zT_569`/`zT_583` are written by the resume path (`zT_569 = zT_1784;` from the frame) and read only
by the frame save.

## Reproducer (in-example patch; not standalone)

Apply to `examples/z98/z9torr/peer.zig` (current tree, HEAD `e32ec60d`): make the `MsgReader` a
module global and pass `&g_reader` to the suspending call (reverting the D3 workaround). The
reference patch is recorded in `examples/torrent_example_defects.md` D3; the exact change used here:

```diff
--- a/examples/z98/z9torr/peer.zig
+++ b/examples/z98/z9torr/peer.zig
@@ var g_empty_blockstate: [1]piece.BlockState = undefined;
+var g_reader: std_stream.MsgReader = undefined;
@@ (in peerRun, ~line 686)
-    var reader: std_stream.MsgReader = undefined;
-    reader.src = &peer.sock;
-    reader.buf = peer.read_buf[0..];
-    reader.pending = peer.read_buf[0..0];
+    g_reader.src = &peer.sock;
+    g_reader.buf = peer.read_buf[0..];
+    g_reader.pending = peer.read_buf[0..0];
@@ (~line 791 / 796)
-            wire.readMessageAsyncEnc(&reader, &peer.enc.in, &msg) catch {
-            wire.readMessageAsync(&reader, &msg) catch {
+            wire.readMessageAsyncEnc(&g_reader, &peer.enc.in, &msg) catch {
+            wire.readMessageAsync(&g_reader, &msg) catch {
```

### Exact commands (run out of tree, so `examples/z98/z9torr` is never modified)

```sh
# 1. copy the example out of tree; patch peer.zig per the diff above
cp -r examples/z98/z9torr /tmp/i3src
# 2. emit C (v94 seed build)
mkdir -p /tmp/i3out
/tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/i3out /tmp/i3src/main.zig    # rc 0 (warnings only)
# 3. gcc -m32 -std=c89 link
sh /tmp/i3out/build_target.sh linux /tmp/i3out/prog                       # rc 1
```

Observed (2026-10-09): the unpatched tree links clean (`rc 0`); the patched tree emits the two
`'zT_NNN' undeclared` errors above. (Temp ids/filenames depend on the module basename hash of the
copy path; the defect class is identical to the in-tree `peer_07FFFED1.c:865 'zT_144'` in the
defects ledger.)

## Locus / suppression path (read-only analysis)

- **Save/restore emit site.** `sf/src/async_state_machine.zig:254-265` `saveAllFields` (and
  `:267-280` `reloadAllFields`) call `storeField(b, blk, fld.offset, fld.type_id, fld.temp_id + b.base)`
  — the value is the **raw shifted temp id**, no declaration check. Call sites: explicit suspend
  `:1189-1199`, implicit yield `:563-574`, result delivery `:587-589`. Step temps are seeded at
  `:949-955` (`base = 2`, `:926`); `newTemp` `:207-211`.
- **Emit path.** `storeFieldBase` → `LirInst.store` → `sf/src/c89_emit.zig:7609-7643`; the value is
  printed via `emitValueExpr` → `resolveTempName` (`:6614-6628`). `resolveTempName` resolves a
  function-local (`fl_temps`) or a `load_global` alias (`temp_global_map`), else falls back to
  `mangleTempName` → `zT_N`.
- **Declaration loop.** `sf/src/c89_emit.zig:3800-3906` skips a temp when `written_flag == 3`
  (`:3485`, large module-array `load_global`), `d4_dead` (`=1` when `read_count == 0`,
  `:3709-3713`), `d4_local` (`:3571`), or `d4_nodecl` (`.load_global` result alias,
  `dceMarkLoadGlobalAliases`/`dceMarkAllReads` at `:8902-8917`/`:8998`). For a suppressed temp the
  emitted name is only correct if `resolveTempName` substitutes it.
- **Mismatch.** The two undeclared temps are `MsgReader` values that the DCE classified as
  `load_global` aliases (`d4_nodecl`), so their stack declaration is suppressed. But
  `temp_global_map` is populated **lazily during body emission** (`c89_emit.zig:7414-7418`, the
  `.load_global` arm) and reset per function (`:9095-9099`). `saveAllFields`' block is emitted
  **before** the `.load_global` that defines these temps, so `resolveTempName` finds no alias entry
  and falls through to the undeclared `zT_569`/`zT_583`. (Later, after the map is populated, other
  save sites emit the global name directly, e.g. `*zT_4246 = zG_1DDBC924_g_reader;`.) Whether the
  precise flag is `d4_nodecl` (alias map not yet populated) or `d4_dead` is for F3 to fix; both
  produce an un-substituted `zT_N`.

## Zig semantics (the reference)

In Zig a coroutine captures referenced state correctly across a suspension. A frame save must
**store a declared temp**; the emitted C must never reference an undeclared `zT_N`. The backend
must either declare every temp the save/restore stores, or allocate the frame slot without a
by-value struct temp.

## Correlation vs D4 — YES (same site / same discipline)

D4 (`g_reader = std_stream.initMsgReader(...)` instead of field init) reproduces with the same
shape and the **same frame slots**:

```
peer_E0C135AE.c:4424:16: error: 'zT_563' undeclared (first use in this function); did you mean 'zT_5763'?
peer_E0C135AE.c:4438:16: error: 'zT_577' undeclared (first use in this function); did you mean 'zT_5779'?
```

- D3: undeclared `MsgReader` values at frame offsets **376** and **424** (`zT_569`, `zT_583`).
- D4: undeclared `MsgReader` values at frame offsets **376** and **424** (`zT_563`, `zT_577`).

Same `saveAllFields`/`reloadAllFields` site, same emitter declaration-suppression +
`resolveTempName` path, same "by-value struct live temp stored by the frame save is undeclared"
defect. The **trigger** differs (D3 = global address/value crossing a suspension; D4 = by-value
struct-return temp assigned to a module global) but the defect locus is shared, so one fix is
expected to cover both (spec §4).
