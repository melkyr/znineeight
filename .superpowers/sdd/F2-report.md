# Task F2 Report — Fix: single-use defer/errdefer expansion

**Status:** DONE
**Date:** 2026-07-31
**Commit:** `bugfix: F2 fix single-use defer expansion`

---

## Fix Summary

Applied **Option B** from I2 report: hybrid pop at block-exit only. Added a `pop: u8` parameter to `expandDefers` (`sf/src/lower.zig:3922`). Pop=1 at scope-termination sites (block exits, fn-end); pop=0 at internal exits (return, break, continue, try-error). This ensures defer/errdefer bodies are inlined at EVERY runtime exit path while the scope is live, but are removed (popped) once the declaring scope closes.

### Files changed
- `sf/src/lower.zig` — signature + 4 guarded pops + 7 call site additions
- `sf/src/tests/lower_test/main.zig` — added `test_multi_return_defer`
- `sf/src/tests/test_lower_bin.zig` — fixed `SemanticContext` init, added `found_count>=5` check
- `sf/docs/tech_docs/07_lir_lowering.md` — removed single-use caveat, documented fix

---

## Evidence

### Unit tests
- `test_lower_bin`: **PASS** (GREEN). All 5 functions (including `test_multi_return_defer` with defer + 2 returns) lower without ICE.
- Pre-existing test failures unchanged: `test_semantic_bin` (zig0 type mismatch), `test_mod_reg_bin` (run failure), `test_sym_reg_bin` (zig0), `test_analyzer_integration_bin` (missing file).

### I2 repro verification
Pre-fix `/tmp/I2.c`: defer body (`f = zT_5`) at `z_bb_1` ONLY (`:52,54,58`); `z_bb_2` (`:59-63`) returns without it.
Post-fix `/tmp/I2_fixed.c`: defer body at BOTH `z_bb_1` (`:54-62`) AND `z_bb_2` (`:63-72`), plus dead-code re-emission at fn-end (`:73-77`).

### json_parser fclose fix
Pre-fix: 1 `fclose` call at line 849 ONLY.
Post-fix: 7 `fclose` calls at lines 861, 884, 909, 955, 973, 983, 996 — one at each of the 6 return paths plus dead-code after fn-end.

### Example programs
| Program | Build | Run | Notes |
|---------|-------|-----|-------|
| mud_server | PASS | Runs (timed out after 3s, expected) | |
| game_of_life | PASS | Runs (generations rendered) | |
| lisp_interpreter_curr | PASS | Runs (`(+ 1 2)` → `3`) | |
| json_parser | PASS (warn only) | Segfault (pre-existing; confirmed on baseline) | |

### Corpus gate
`OK=176 FAIL=8 ICE=0 CRASH=0` — **no regression** from baseline `176/8/0/0`.

### Byte-identical gate
| Entry | Expected md5 | Actual md5 | Match |
|-------|-------------|------------|-------|
| mud_server | `87954d75...` | `87954d75...` | IDENTICAL |
| game_of_life | `9cc38ab9...` | `9cc38ab9...` | IDENTICAL |
| lisp_interpreter_curr | `6a8ca449...` | `6a8ca449...` | IDENTICAL |
| json_parser | (changed) | `6d52e479...` | New baseline re-captured |

Man/gol/lisp have zero defer → unaffected, byte-identical confirmed. Json changes (gaining `fclose` on all paths) → baseline re-captured.

---

## Concerns

1. **json_parser segfault**: Pre-existing (confirmed on baseline without fix). Not introduced by F2. json_parser links with a missing `arena_alloc_default` runtime symbol that requires `sf/build/out_release/zig_runtime.c` (emitted by zig0). The segfault occurs at runtime before entering main — separate issue from defer expansion.

2. **Dead-code after return**: Under the hybrid scheme, defers inlined at a return site are also re-inlined at block-exit/fn-end as dead code after the return. Harmless and unreachable. Minor emitted-code bloat for defer-bearing programs only.

3. **errdefer never fires on `return error.X`**: `return_stmt` calls `expandDefers` with `is_error_path=0` (`lower.zig:3615`), so errdefers are never expanded at error returns. This is a separate gap (documented in I2 B.1), out of scope for F2.

---

## Verification commands

```bash
# Unit test
bash sf/scripts/build_test.sh | grep test_lower_bin  # PASS

# I2 repro
sf/build/out_release/zig1 --dump-c89 /tmp/I2_repro.zig > /tmp/I2_fixed.c
grep -c "f = zT" /tmp/I2_fixed.c  # 6 (2 sites × 3 defer body insts each)

# json_parser fclose
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | grep -c fclose  # 7

# Corpus gate
for d in repro/mi_matrix/*/; do ... done  # OK=176 FAIL=8 ICE=0 CRASH=0
```
