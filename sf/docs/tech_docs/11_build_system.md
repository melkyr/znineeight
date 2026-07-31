# 11 — Build System

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| Build scripts | 2 | `build_release.sh`, `build_test.sh` |
| Build stages (release) | 3 | zig0 compile → zig0→C89 translation → gcc C89 compile |
| Build stages (test) | 3 per binary | zig0→C89 translation → gcc compile → runtime execution |
| Test binaries | 9 | test_semantic_bin, test_analyzer_bin, test_mod_reg_bin, test_sym_reg_bin, test_analyzer_integration_bin, test_memory_budget_bin, test_lower_bin, test_name_mangle_bin, dump_ir_bin |
| Output directories | 10+ | `build/`, `build/out_release/`, `build/out_test_<name>/` |
| GCC C89 flags | 5+ | `-m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration` |
| GCC debug flags | 2 | `-g -O0` (optional, for GDB) |
| GCC sanitizer flags | 1 | `-fsanitize=address` (release only) |

---

## Function Walkthrough

### `build_release.sh` — Release Build (`sf/scripts/build_release.sh:1-50`)

| Step | Line | Purpose | Command | Output | Failures |
|------|------|---------|---------|--------|----------|
| Build zig0 | 11-12 | Compile bootstrap compiler from C++98 | `g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o build/zig0` | `build/zig0` | C++ compile error |
| Clean output dir | 15-16 | Isolate release output — remove stale `.c`/`.h` | `rm -rf build/out_release && mkdir -p build/out_release` | `build/out_release/` (empty) | (none) |
| zig0 → C89 | 19 | Translate `sf/src/main.zig` to C89 | `build/zig0 --header-priority-include -o build/out_release/zig1.c sf/src/main.zig` | `build/out_release/*.c` (35+ files) | zig0 compile error |
| gcc compile | 22-28 | Compile C89 to binary with ASan | `gcc -m32 -std=c89 -O0 -Wall -fsanitize=address -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -Iinclude build/out_release/*.c -o build/out_release/zig1` | `build/out_release/zig1` | gcc error |
| zig1-dump (disabled) | 37-48 | (Commented out) Build dump binary from `main_dump.zig` | (disabled — pre-existing break) | (none) | Would fail on `main_dump.zig` |

**Gate line:** `=== [release] Done: sf/build/out_release/zig1 ===` (`build_release.sh:30`)
**Resulting binary:** `sf/build/out_release/zig1`
**Oracle reference:** `sf/build/zig0`

### `build_test.sh` — Test Build + Run (`sf/scripts/build_test.sh:1-66`)

| Component | Line | Purpose | Command | Notes |
|-----------|------|---------|---------|-------|
| Zig0 check | 9-12 | Build zig0 if missing | `g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o build/zig0` | Conditional — only runs if `build/zig0` missing |
| `build_and_run` function | 18-53 | Per-binary build+compile+run pipeline | (see below) | Shared logic for all 9 test binaries |
| `build_and_run` — zig0→C89 | 27 | Translate test `.zig` to C89 | `zig0 --header-priority-include -o build/out_test_<name>/<name>.c sf/src/tests/<name>.zig` | Failure → counted as FAIL |
| `build_and_run` — gcc compile | 34-43 | Compile C89 to binary | `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -Iinclude build/out_test_<name>/*.c -o build/out_test_<name>/<name>` | No ASan, no `-O0`, no `-Wall`. Failure → counted as FAIL |
| `build_and_run` — execute | 46-49 | Run the test binary | `build/out_test_<name>/<name>` | Nonzero exit → FAIL |
| Test invocations | 56-64 | All 9 test entries | `build_and_run "test_<name>_bin"` | Each gets isolated output dir |
| Results summary | 66 | Final tally | `echo "Results: $PASS passed, $FAIL failed"` | |

### `build_release.sh` GCC flags rationale

| Flag | Purpose | Why needed |
|------|---------|------------|
| `-m32` | 32-bit target | Compiler targets 32-bit Windows 9x/NT |
| `-std=c89` | C89 standard | `zig0` emits C89, must compile under C89 rules |
| `-O0` | No optimization | Easier debugging, avoids optimizer bugs on generated code |
| `-Wall` | All warnings | Catch codegen issues in release build |
| `-fsanitize=address` | ASan | Detect buffer overflows/use-after-free in release binary |
| `-Wno-long-long` | Suppress `long long` warning | C89 extension required for 64-bit types |
| `-Wno-pointer-sign` | Suppress signed/unsigned mismatch | Generated code casts freely |
| `-Wno-implicit-function-declaration` | Suppress implicit decl warnings | Generated code may use undeclared functions |
| `-Iinclude` | Include path for `zig_runtime.h` etc. | Header resolution during compile |

### `build_test.sh` GCC flags differences

| Flag | `build_release.sh` | `build_test.sh` | Reason |
|------|-------------------|-----------------|--------|
| `-O0` | Yes | No (default) | Test binaries don't need consistent address mapping |
| `-Wall` | Yes | No | Test builds skip warning noise |
| `-fsanitize=address` | Yes | No | Test binaries don't use ASan |
| `-m32` | Yes | Yes | Both target 32-bit |
| `-std=c89` | Yes | Yes | Both compile zig0-emitted C89 |

### Output Directory Isolation

| Directory | Script | Binary | Cleanup |
|-----------|--------|--------|---------|
| `build/` | both | `zig0` (bootstrap) | gitignored, manual rebuild |
| `build/out_release/` | `build_release.sh` | `zig1` | `rm -rf` before each build |
| `build/out_test_<name>/` | `build_test.sh` | `<name>` test binary | `rm -rf` before each build_and_run |

**Why isolation matters** (`AGENTS.md §9.1`): zig0 generates `.c` / `.h` files per module. Different builds emit different file sets. Stale files from a previous build cause C89 type mismatch errors (`unknown type name 'Slice_*'`). Each target gets its own `rm -rf` + `mkdir -p`.

### Differential Testing Scripts (from QUICK_REF)

| Test Type | Command | Verifier |
|-----------|---------|----------|
| Release build | `bash sf/scripts/build_release.sh` | Gate on `Done: .../zig1` |
| Test suite | `bash sf/scripts/build_test.sh` | `PASS=9 FAIL=0` |
| Compile+run with zig1 | `sf/build/out_release/zig1 --dump-c89 <FILE> > /tmp/x.c && gcc -m32 ... /tmp/x.c sf/include/zig_runtime.c sf/include/zig_pal.c -o /tmp/x && /tmp/x` | Exit code 0 |
| Byte-identical gate | zig1 `--dump-c89` output vs parent zig1 `--dump-c89` output | `md5sum` match |
| Corpus gate | 166 repros in `repro/mi_matrix/*/main.zig` | Baseline: `OK=162 FAIL=4 ICE=0 CRASH=0` |
| Compile-only gate | `gcc -m32 -std=c89 -c` on zig1 output | gcc rc=0 |

---

## Data Flow

```
Source tree                 Build output
──────────                  ────────────
sf/src/bootstrap/           build/zig0  (g++ -std=c++98)
  bootstrap_all.cpp
       │
       ▼                    (zig0 --header-priority-include -o ...)
sf/src/main.zig ──────────► build/out_release/zig1.c  (zig0→C89)
sf/src/*.zig                build/out_release/*.c     (35+ per-module .c files)
       │
       ▼                    (gcc -m32 -std=c89 ...)
                            build/out_release/zig1  (release binary)

Test flow:
sf/src/tests/test_*.zig ──► build/out_test_<name>/*.c ──► build/out_test_<name>/<name> ──► run
           (zig0 --header-priority-include)    (gcc -m32 -std=c89)    (execute)
```

**Reference oracle (QUICK_REF):**
```
sf/build/zig0 ──► target .c ──► gcc ──► binary
                              (reference output for --dump-c89 comparison)
```

---

## Debugging

- **`Makefile` not found** — there is no Makefile. Use `bash sf/scripts/build_release.sh` or the manual gcc commands from QUICK_REF.
- **`gcc` outputs warnings** — expected. Suppressed by `-Wno-long-long`, `-Wno-pointer-sign`, `-Wno-implicit-function-declaration`. Only `error:` count matters. Gate on nonzero exit, not stderr emptiness.
- **`build/zig0` missing** — run `bash sf/scripts/build_release.sh` (or `build_test.sh` which auto-builds zig0 if absent).
- **Stale `.c` / `.h` errors** (`unknown type name 'Slice_*'`) — always `rm -rf` the output directory before zig0 invocation. Check `build/out_release/` or `build/out_test_*` for leftovers.
- **`-Werror`** — not used. Warnings do not cause build failure. Release uses `-Wall` but no `-Werror`.
- **`-pedantic`** — NOT used despite the task brief's mention. Actual scripts use `-std=c89` without `-pedantic`.
- **`zig1-dump` build disabled** — the commented-out section at `build_release.sh:32-49` is intentionally dead. Do NOT re-enable; `main_dump.zig` has a pre-existing break.
- **Test count mismatch** — `build_test.sh` runs 9 tests. Count is static: `PASS`/`FAIL` variables at top, 9 `build_and_run` calls.
- **ASan in release only** — `build_release.sh` uses `-fsanitize=address`, `build_test.sh` does not. A test binary crash with ASan-like output may not appear in test builds.
- **`-m32` requires 32-bit multilib** — on Debian/Ubuntu: `sudo apt install gcc-multilib g++-multilib`.
