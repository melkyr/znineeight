### Task 1 Report — D1: comptime-missing ICE for `@sizeOf`/`@alignOf`

**Status:** DONE

**Commit:** `34657612`

---

#### RED Baseline (Step 1)

- **Lisp gate gcc errors (6):**
  - `/tmp/l.c:3743:9: error: used struct type value where scalar is required`
  - `/tmp/l.c:3796:9: error: used struct type value where scalar is required`
  - `/tmp/l.c:5363:5: error: 'zT_329' undeclared ...`
  - `/tmp/l.c:5363:26: error: 'zT_328' undeclared ...`
  - `/tmp/l.c:5367:14: error: 'zT_330' undeclared ...`
  - `/tmp/l.c:6710:26: error: incompatible types when assigning ...`

- **man `--dump-c89` md5:** `1ea4057da4cfe2a2932f3cfcdf23202f`
- **gol `--dump-c89` md5:** `80e978322f281fb49b2075234f4ae9d0`
- **mud `--dump-c89` md5:** `276a8e49e2ff01ad3ac1e6af6c24fe2c`
- **mi_matrix split:** OK=111 / FAIL=20 / ICE=1

---

#### Edits (Step 2–4)

All edits to `sf/src/lower.zig`:

| # | Location | Change |
|---|----------|--------|
| 1 | LirLowerer struct (after `enumtoint_name_id`) | Added `size_of_name_id: u32,` and `align_of_name_id: u32,` fields |
| 2 | `lowererInit` (before `return LirLowerer{`) | Interned `"@sizeOf"` → `sizeof_id`, `"@alignOf"` → `alignof_id` |
| 3 | Return struct literal (after `.enumtoint_name_id`) | Added `.size_of_name_id = sizeof_id, .align_of_name_id = alignof_id,` |
| 4 | After `iceInvalidIndex` (new function) | Added `fn iceUnresolvedComptime` — builds message via `diagnosticBuilderMakeMsg`, emits `ERR_9001_ICE`, exits 3 |
| 5 | builtin_call site (after comptime_values miss block) | Wired: if `node.child_0` matches `size_of_name_id` or `align_of_name_id`, call `iceUnresolvedComptime(self, node_idx)` |

---

#### GREEN Verification (Step 6)

- **Lisp gate:** Now ABORTS with exit 3 and ICE:
  ```
  error[48]: internal: comptime value unresolved for @sizeOf/@alignOf (node 2145)
  ```
  Proves bug #3 is upstream (comptime_eval never populates comptime_values for pointer-type args).

- **man md5:** `1ea4057da4cfe2a2932f3cfcdf23202f` (unchanged)
- **gol md5:** `80e978322f281fb49b2075234f4ae9d0` (unchanged)
- **mud md5:** `276a8e49e2ff01ad3ac1e6af6c24fe2c` (unchanged)
- **mi_matrix split:** OK=111 / FAIL=20 / ICE=1 (unchanged)

---

#### Deviations

None. All steps followed verbatim.

---

#### Concerns

None.
