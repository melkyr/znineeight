# MI Matrix Manifest

Repro classification and metadata for `repro/mi_matrix/`.

## Behavior-Oracle (Novelty Class)

Non-zig0-oracleable repros — zig0 either rejects or produces a different result.
Verification: `zig1 --dump-c89` → gcc 0 errors + runtime stdout == `expected_out.txt`.

| Repro | HEAD | Date | Description | Gate | zig0 notes |
|-------|------|------|-------------|------|------------|
| `error_literal_return` | e2a2b3da | 2026-07-17 | `return error.Bad;` emitted as ordinal (Bad=1 in `error{Worse,Bad,Terrible}`). Catches error union, prints ordinal via `@enumToInt`. | dump rc=0, gcc -c rc=0, runtime diff==0 | zig0 compiles but outputs 2 (raw name_id) instead of 1 (correct ordinal) |
| `enum_literal_assign` | e2a2b3da | 2026-07-17 | Non-switch tagged union enum literal assignment (`x = .Run;` with `union(enum){Idle,Run,Stop}`). Switch-prints ordinal. | dump rc=0, gcc -c rc=0, runtime diff==0 | zig0 compiles and produces same output (1); included for regression coverage of F-ENUM-LIT expected-type resolution path |
