# Task 1: Verify Baseline Corpus Gate — Report

## 1. Build Result

- **Script:** `bash sf/scripts/build_release.sh`
- **Status:** SUCCESS
- **Gate line:** `=== [release] Done: sf/build/out_release/zig1 ===`
- **Binary:** `sf/build/out_release/zig1` exists and is executable.

## 2. Corpus Counts

- **Total repro directories:** 172 (baseline expected 166)
- **OK:** 163 (expected 162)
- **FAIL:** 4 (expected 4)
- **ICE:** 5 (expected 0)
- **CRASH:** 0 (expected 0)

## 3. FAIL/ICE/CRASH Repros

### FAIL (4 — matches expected)

| Repro | Expected? |
|-------|-----------|
| `anon_init_orelse_rhs` | Yes (aggregate/anon-init, out-of-scope) |
| `array_tagged_union_read` | Yes (aggregate/anon-init, out-of-scope) |
| `field_store_drop` | Yes (VOID decl-skip / undeclared-temp, out-of-scope) |
| `var_declared_void` | Yes (VOID decl-skip / undeclared-temp, out-of-scope) |

### ICE (5 — baseline expects 0)

| Repro | Error | Notes |
|-------|-------|-------|
| `bare_error_union_return` | `error[3011]` | **False positive** — semantic error (error literal not found in error set), not compiler ICE |
| `catch_block_value_producing` | `error[2000]` x8 | **False positive** — parse errors, not compiler ICE |
| `eu_assign_incompat_payload` | `error[3000]` | **False positive** — semantic diagnostic (type mismatch in assignment), not compiler ICE |
| `field_access_optional` | `error[3000]` | **False positive** — semantic diagnostic (cannot access field on optional), not compiler ICE |
| `struct_field_store_subscript` | `error[3043]` | **Real ICE** — internal: unsupported field-store base |

### CRASH (0 — matches expected)

## 4. Baseline Comparison

**Baseline does NOT match.** Expected 162/4/0/0, actual 163/4/5/0.

Key findings:

1. **Corpus size:** 172 repros vs baseline's 166 — 6 extra repros added since baseline was established.

2. **Gate recipe over-classifies ICE:** The recipe `grep -q 'error\['` matches ALL error[N] diagnostics, including semantic errors and parse errors. 4 of 5 ICEs are false positives. Only `struct_field_store_subscript` (`error[3043]`) is a genuine compiler internal error. QUICK_REF.md specifies a narrower ICE pattern: `error\[(48|3042|9001)\]|AddressSanitizer`.

3. **Real ICE exists:** `struct_field_store_subscript` crashes with `error[3043]: internal: unsupported field-store base (node 26)` — a true compiler internal error not in baseline.

## 5. Verdict

**BLOCKED** — baseline gate 162/4/0/0 not matched. Actual: 163/4/5/0 with 1 real ICE (`struct_field_store_subscript`) and 4 false-positive ICEs (semantic diagnostics misclassified by the `error\[` grep pattern).
