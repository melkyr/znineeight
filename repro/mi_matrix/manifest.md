# MI Matrix Manifest

Repro classification and metadata for `repro/mi_matrix/`.

## Behavior-Oracle (Novelty Class)

### Non-zig0-oracleable

zig0 rejects or produces a different result.
Verification: `zig1 --dump-c89` → gcc 0 errors + runtime stdout == `expected_out.txt`.

| Repro | HEAD | Date | Description | Gate | zig0 notes |
|-------|------|------|-------------|------|------------|
| `error_literal_return` | e2a2b3da | 2026-07-17 | `return error.Bad;` emitted as ordinal (Bad=1 in `error{Worse,Bad,Terrible}`). Catches error union, prints ordinal via `@enumToInt`. | dump rc=0, gcc -c rc=0, runtime diff==0 | zig0-compiled binary prints 2 (raw name_id, not ordinal 1): measured 2026-07-17 |

### Regression Coverage (zig0-agreeing)

zig0 produces the same result as zig1 — included as regression guards for fixed resolution paths.
Verification: `zig1 --dump-c89` → gcc 0 errors + runtime stdout == `expected_out.txt`.

| Repro | HEAD | Date | Description | Gate | zig0 notes |
|-------|------|------|-------------|------|------------|
| `enum_literal_assign` | e2a2b3da | 2026-07-17 | Non-switch tagged union enum literal assignment (`x = .Run;` with `union(enum){Idle,Run,Stop}`). Switch-prints ordinal. Guards F-ENUM-LIT expected-type resolution path — pre-fix this shape gcc-FAILED. | dump rc=0, gcc -c rc=0, runtime diff==0 | zig0 compiles and produces same output (1) |
