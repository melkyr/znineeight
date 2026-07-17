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

## Version History

| Ver | HEAD | Date | Corpus | Description |
|-----|------|------|--------|-------------|
| v10 | 6a4e9563 | 2026-07-17 | **168 dirs, OK=164, FAIL=4, ICE=0, CRASH=0** | Literal name_id->ordinal resolution complete (7 commits). Fixed: error_literal (return/assign/eq/catch-RHS/inline RHS contexts) + enum_literal (non-switch void-member assign/eq contexts) + ERR_3008/3009 diagnostics + hack deletion (:620-628) + review-hardening policy. Behavior-oracle novel repro class established (error_literal_return non-zig0-oracleable; enum_literal_assign regression guard). Known FAILs unchanged: anon_init_orelse_rhs, array_tagged_union_read, field_store_drop, var_declared_void. |

## Future Work (tracked, not in scope)

| Item | Origin | Description |
|------|--------|-------------|
| `@errorName` builtin | Task 4e PASS ruling | Error-set name table emission at emitErrorSetType + builtin — would let apps print error names instead of manual if-chains |
| Untyped-literal fix | Task 6 operator ruling | Two-part: (a) error-literal untyped var-decl inference via error-set name search; (b) enum-literal untyped → level-0 diagnostic |
| Phase-C skip justification | Task 4d review F1 | Reviewer-proven wrong verification claim; recorded debt only, no action needed |
| `.gitignore` `*.txt` rule | Task 5 gotcha | `expected_out.txt` files require `git add -f`; note for future repros |
