# 11 — Build System [updated: 2026-09-20 — refreshed against the seed bootstrap model (`release/seed/zig1-seed.tgz`, `scripts/seed/build_from_seed.sh`/`archive_seed.sh`), the binding gcc flag set, the emitted companion build scripts, and the `/tmp/fx_subfolder` current-cycle path; line references removed]

> Covers: `sf/scripts/*`, `scripts/seed/*`, `release/seed/*`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| Build scripts | 3 | `sf/scripts/build_release.sh` (zig0 release), `sf/scripts/build_test.sh` (zig0 test runner), `sf/scripts/build.sh` (legacy repo-root zig0 → `sf/build/zig1`) |
| Seed scripts | 2 | `scripts/seed/build_from_seed.sh` (forward gcc-only rebuild), `scripts/seed/archive_seed.sh` (closeout rotation) |
| Build stages (seed/forward) | 3 per hop | seed `-ffast --dump-c89` → gcc `-c` → gcc link (`zig_runtime.c`+`zig_pal.c`+`c_exit.c`) |
| Build stages (release, zig0) | 3 | g++ zig0 → zig0→C89 translation → gcc C89 compile |
| Build stages (test, zig0) | 3 per binary | zig0→C89 translation → gcc compile → runtime execution |
| Test binaries | 9 | test_semantic_bin, test_analyzer_bin, test_mod_reg_bin, test_sym_reg_bin, test_analyzer_integration_bin, test_memory_budget_bin, test_lower_bin, test_name_mangle_bin, dump_ir_bin |
| Emitted companion scripts | 3 | `build_target.sh` (always), `build_target.bat`/`build_owc.bat` (Windows target only) |
| Output directories | per target | `sf/build/` (zig0), `/tmp/fx_subfolder/` (release zig1), `sf/build/out_test_<name>/` (tests), `<seed-out>/{gen,hop2,hop3,lib}` |
| Canonical gcc flag set | 7 | `-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration` (plus `-I <inc>`) |
| GCC sanitizer flags | 1 | `-fsanitize=address` (release only) |

---

## Function Walkthrough

### Seed Bootstrap Model (primary rebuild path)

The zig0-independent rebuild authority is the committed, rotating seed
`release/seed/zig1-seed.tgz` (git-tracked; provenance and rotation history in
`release/seed/CHANGELOG.md`). The archive's top-level `zig1-seed/` carries:
`zig1` (the seed binary), `gen/` (the seed's own self-emission C89 module set —
45 `.c` + 46 `.h` incl. `zig_special_types.h` at seed v41), top-level `c_exit.c`,
`runtime/` (the emitted mode-specific support: `zig_compat.h`, `zig_runtime.h`,
`zig_special_types.h`, `zig_runtime.c`, `zig_pal.c` — no `net_prelude.h`), `lib/`
(the 29 std `.zig`), and `SEED_README.txt` (provenance + recipes + the flag-set
rule). `sf/src` sources are NOT archived; the pinned HEAD in `CHANGELOG.md`
identifies them. The fixed point is the md5 of the gcc-rebuilt archive binary;
current values live in `release/seed/CHANGELOG.md`. The **bootstrap-staging
constraint** holds: a seed at commit N can compile only `sf/src` written in the
subset that seed already understands, so new syntax is adopted only after a new
fixed point exists, and the seed rotates at closeout.

#### `scripts/seed/build_from_seed.sh` — forward rebuild

Usage: `scripts/seed/build_from_seed.sh [--reconstruct-only] <seed> <out_dir>`
(`<seed>` = the `.tgz`, an unpacked `zig1-seed/` dir, or a dir containing one).
Run from the repo root: the dump uses the relative `sf/src/main.zig` path because
module basename-hash tokens are path-derived.

| Step | Purpose | Command |
|------|---------|---------|
| Resolve seed | Unpack a `.tgz` into `<out>/_unpack`; a seed dir is recognized by `gen/` | `tar -xzf <seed> -C <out>/_unpack` |
| Reconstruct fallback | If the seed binary is missing, rebuild the seed compiler from its own C (`--reconstruct-only` does only this) | `gcc -m32 -std=c89 -O0 -Wall ... -I <seed>/runtime -c gen/*.c`; link `runtime/zig_runtime.c` + `runtime/zig_pal.c` + `c_exit.c` |
| Dump hop | Self-emission of current `sf/src` by the seed compiler, `-ffast` | `<compiler> -ffast --dump-c89 --output-dir <dumpdir> sf/src/main.zig` |
| gcc `-c` | Compile every emitted `.c` with the canonical flag set | self-contained: `gcc -m32 -std=c89 -O0 -Wall ... -I . -c *.c`; else `-I <repo>/sf/src/include` |
| gcc link | Link the objects into the next compiler | self-contained: `gcc -m32 -O0 *.o -o <binout>`; else `*.o zig_runtime.c zig_pal.c c_exit.c` |
| std install | Copy the 29 std `.zig` (explicit list) next to the rebuilt compiler | `cp` → `<out>/lib/` |
| Closure gate | hop1 (`<out>/zig1_5_clean`) md5 == hop2 (`<out>/hop2/zig1_hop2`); if the committed seed predates current `sf/src`, require hop2 == hop3 | `md5sum` compare |

Gate: `=== [seed] Done: <out_dir> ===`. Set `FIXED_POINT_MD5=<md5>` to also gate
on the recorded fixed point. A dump is self-contained when the emitted support
`zig_runtime.c` is present, in which case only the emitted objects are linked
(never the repo runtime trio again — that would double-link).

#### `scripts/seed/archive_seed.sh` — closeout rotation

Usage: `scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> <out_tgz> [--update-changelog]`.
It assembles a fresh `zig1-seed/` tree, gcc-rebuilds the archive C self-contained
to prove gcc-only rebuildability and record the fixed-point md5, packs the
tarball, and prints the provenance entry (with `--update-changelog`, prepends it
to `release/seed/CHANGELOG.md`, newest-first). `gen/` receives only the module
emission: the six emitted support files (`zig_runtime.c`, `zig_pal.c`,
`c_exit.c`, `zig_compat.h`, `zig_runtime.h`, `net_prelude.h`) are excluded,
because the three support `.c` are staged from `runtime/` (+ top-level `c_exit.c`)
and would double-link if left in `gen/`. When `gen/` is a self-emission dump
(contains `zig_runtime.c`), the mode-specific emitted support is staged into
`runtime/` so a gcc-only rebuild reproduces the archived binary's exact fixed
point; otherwise the canonical `sf/src/include` copies are used. Rotation is a
closeout-only step, and only when the plan moved the fixed point or changed the
archive `lib/` payload.

### `sf/scripts/build_release.sh` — zig0 Current-Cycle Release Build

Superseded as the rebuild authority by the seed model above. The script first
`g++`-rebuilds `zig0` and uses it to dump `sf/src/main.zig`; `zig0`'s frozen C++
front end no longer parses the current source (it rejects `@intToPtr` in
`main.zig`), so the forward path is `build_from_seed.sh`. It remains the legacy
current-cycle builder while `zig0` still compiles the source.

| Step | Purpose | Command | Output | Failures |
|------|---------|---------|--------|----------|
| Build zig0 | Compile bootstrap compiler from C++98 | `g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0` | `sf/build/zig0` | C++ compile error [inference] |
| Clean output dir | Isolate release output — remove stale `.c`/`.h` | `rm -rf /tmp/fx_subfolder && mkdir -p /tmp/fx_subfolder` | `/tmp/fx_subfolder/` (empty) | (none) [inference] |
| zig0 → C89 | Translate `sf/src/main.zig` to C89 (`-o` is an output *file*; zig0 extracts its directory) | `sf/build/zig0 --header-priority-include -o /tmp/fx_subfolder/zig1.c sf/src/main.zig` | `/tmp/fx_subfolder/*.c` (module `.c` + emitted support) | zig0 compile error [inference] |
| gcc compile | Compile C89 + link PAL to binary with ASan | `gcc -m32 -std=c89 -O0 -Wall -fsanitize=address -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -Iinclude /tmp/fx_subfolder/*.c sf/src/include/zig_pal.c -o /tmp/fx_subfolder/zig1` | `/tmp/fx_subfolder/zig1` | gcc error [inference] |
| zig1-dump (disabled) | (Commented out) Build dump binary from `main_dump.zig` | (disabled — pre-existing break) | (none) | Would fail on `main_dump.zig` [inference] |

**Gate line:** `=== [release] Done: /tmp/fx_subfolder/zig1 ===`
**Resulting binary:** `/tmp/fx_subfolder/zig1`
**Oracle reference:** `sf/build/zig0`

**PAL link (F-S1):** the gcc step links `sf/src/include/zig_pal.c` into zig1 — it defines
`pal_file_open`/`pal_file_write`/`pal_file_close`, which the `pal.zig` wrappers
(`fileOpen`/`fileWrite`/`fileClose`) call. Any manual zig1 rebuild must add it to the gcc
line, else the link fails with `undefined reference to 'pal_file_*'`. The seed link set is
larger — `zig_runtime.c` + `zig_pal.c` + `c_exit.c` (`zig_pal.c` alone is insufficient).

### `sf/scripts/build_test.sh` — zig0 Test Build + Run

| Component | Purpose | Command | Notes |
|-----------|---------|---------|-------|
| Zig0 check | Build zig0 if missing | `g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0` | Conditional — only runs if `sf/build/zig0` missing [inference] |
| `build_and_run` | Per-binary build+compile+run pipeline | (see below) | Shared logic for all 9 test binaries [inference] |
| `build_and_run` — zig0→C89 | Translate test `.zig` to C89 | `sf/build/zig0 --header-priority-include -o sf/build/out_test_<name>/<name>.c sf/src/tests/<name>.zig` | Failure → counted as FAIL [inference] |
| `build_and_run` — gcc compile | Compile C89 to binary | `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -Iinclude sf/build/out_test_<name>/*.c sf/src/include/zig_pal.c -o sf/build/out_test_<name>/<name>` | No ASan, no `-O0`, no `-Wall`. Failure → counted as FAIL [inference]. `zig_pal.c` linked (added 2026-08-01) so `pal.zig`'s `pal_file_*` externs resolve |
| `build_and_run` — execute | Run the test binary | `sf/build/out_test_<name>/<name>` | Nonzero exit → FAIL [inference] |
| Test invocations | All 9 test entries | `build_and_run "test_<name>_bin"` | Each gets isolated output dir [inference] |
| Results summary | Final tally | `echo "=== [test] Results: $PASS passed, $FAIL failed ==="` | [inference] |

Test entries: `test_semantic_bin`, `test_analyzer_bin`, `test_mod_reg_bin`,
`test_sym_reg_bin`, `test_analyzer_integration_bin`, `test_memory_budget_bin`,
`test_lower_bin`, `test_name_mangle_bin`, `dump_ir_bin`.

### Canonical gcc flag set (binding)

The seed recipes and the emitted companion scripts all use the same canonical
`gcc -c` flag set. The self-emission fixed point reproduces **only** with `-Wall`
present: `-Wall` does not change the generated instructions, but it changes the
assembler's local-label numbering, so the linked bytes (and their md5) differ
without it. Every translation unit — emitted modules and runtime support alike —
must be compiled with `gcc -c` under the full set, never implicitly on a link line.

```
gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -I <inc> -c ...
```

Link set for self-emission C89: `zig_runtime.c` + `zig_pal.c` + `c_exit.c`
(`zig_pal.c` alone is insufficient — `undefined std_panic`/`c_exit`). The stricter
`-Wall -Wextra -O3 -fsyntax-only` warning-clean check is a separate verification
gate, never the build command.

### Release GCC flags rationale

| Flag | Purpose | Why needed |
|------|---------|------------|
| `-m32` | 32-bit target | Compiler targets 32-bit Windows 9x/NT [inference] |
| `-std=c89` | C89 standard | The emitter targets C89, must compile under C89 rules [inference] |
| `-O0` | No optimization | Easier debugging, avoids optimizer bugs on generated code [inference] |
| `-Wall` | All warnings | Catch codegen issues; part of the canonical fixed-point flag set [inference] |
| `-fsanitize=address` | ASan | Detect buffer overflows/use-after-free in release binary [inference] |
| `-Wno-long-long` | Suppress `long long` warning | C89 extension required for 64-bit types [inference] |
| `-Wno-pointer-sign` | Suppress signed/unsigned mismatch | Generated code casts freely [inference] |
| `-Wno-implicit-function-declaration` | Suppress implicit decl warnings | Generated code may use undeclared functions [inference] |
| `-Iinclude` | Include path (vestigial) | The tree is `src/include`; emitted module headers are quote-includes in the output dir, and the compiler reaches no std module, so no prelude needs this path [inference] |

### Test GCC flags differences

| Flag | `build_release.sh` | `build_test.sh` | Reason |
|------|-------------------|-----------------|--------|
| `-O0` | Yes | No (default) | Test binaries don't need consistent address mapping [inference] |
| `-Wall` | Yes | No | Test builds skip warning noise [inference] |
| `-fsanitize=address` | Yes | No | Test binaries don't use ASan [inference] |
| `-m32` | Yes | Yes | Both target 32-bit [inference] |
| `-std=c89` | Yes | Yes | Both compile emitted C89 [inference] |

### Emitted Companion Build Scripts

The compiler writes companion build scripts into the output dir alongside the
self-contained emitted tree (emitter details in 08 §6.1). `build_target.sh` is
emitted always; `build_target.bat` (MSVC `cl`) and `build_owc.bat` (OpenWatcom
`wcc386`/`wlink`) only for the Windows target (`-osw` / `--target windows`).
Each enumerates the reachable module `.c` files first and the runtime sources
`zig_runtime.c`/`zig_pal.c`/`c_exit.c` last (deterministic link order), and adds
the winsock library iff a `net_prelude.h` c-include was emitted.

| Script | Toolchain | Compile flags | Link | Warnings |
|--------|-----------|---------------|------|----------|
| `build_target.sh` | `gcc` (linux) / `i686-w64-mingw32-gcc` (mingw) | `-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I .` | `-m32 -O0` (linux) / `-m32` (mingw), `... -o "$OUT" $LIBS`; `LIBS=-lwsock32` iff net emitted | none (`-Werror` not used) |
| `build_target.bat` | MSVC `cl` | `/c /Za /W3 /WX /DZIG_WIN32 /I .` | `link /subsystem:console kernel32.lib ... [wsock32.lib] /out:%OUT%` | `/WX` (warnings-as-errors; documented removable) |
| `build_owc.bat` | OpenWatcom `wcc386`/`wlink` | `wcc386 /za /we /dZIG_WIN32 /i=. ...` | `wlink system console op q opt stack=65536 file ... [library wsock32] name %OUT%` | `/we` (warnings-as-errors; documented removable) |

`build_target.sh` takes `[TARGET] [OUT]` (default target `linux`, default output
`prog`/`prog.exe`); the `.bat` scripts take `[OUT]`.

### Output Directory Isolation

| Directory | Script | Binary | Cleanup |
|-----------|--------|--------|---------|
| `sf/build/` | both zig0 scripts | `zig0` (bootstrap) | gitignored, manual rebuild [inference] |
| `/tmp/fx_subfolder/` | `build_release.sh` | `zig1` | `rm -rf` before each build [inference] |
| `sf/build/out_test_<name>/` | `build_test.sh` | `<name>` test binary | `rm -rf` before each build_and_run [inference] |
| `<seed-out>/{gen,hop2,hop3}` | `build_from_seed.sh` | `zig1_5_clean`, `zig1_hop2`, `zig1_hop3` | `rm -rf <out>` at start [inference] |

**Why isolation matters** (`AGENTS.md §9.1`): the emitter writes `.c` / `.h` files per module. Different builds emit different file sets. Stale files from a previous build cause C89 type mismatch errors (`unknown type name 'Slice_*'`). Each target gets its own `rm -rf` + `mkdir -p`.

### Verification Scripts and Gates

| Test Type | Command | Verifier |
|-----------|---------|----------|
| Release build | `bash sf/scripts/build_release.sh` | Gate on `=== [release] Done: /tmp/fx_subfolder/zig1 ===` (requires `zig0` to parse `sf/src`) [inference] |
| Test suite | `bash sf/scripts/build_test.sh` | `=== [test] Results: 9 passed, 0 failed ===` [inference] |
| Seed rebuild | `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` | `=== [seed] Done: <out> ===`; `<out>/zig1_5_clean` md5 == recorded fixed point [inference] |
| Differential (single program) | `bash sf/scripts/differential_test.sh <test.zig> [--verbose]` | Normalized zig0-vs-zig1 line match ≥ 90% → PASS (strong); 50-89% → PASS (partial structural match); < 50% → INFO [inference] |
| C89 validation | `bash sf/scripts/validate_c89.sh <dir> [--pedantic]` | gcc `-fsyntax-only` all pass; Wine `cl /Za` and `wcc386 -za` optional, info-only [inference] |
| Memory profile | `bash sf/scripts/memory_profile.sh [test.zig] [max_bytes]` | `/usr/bin/time -v` peak RSS or `--track-memory` under the 16 MB budget [inference] |
| Byte-identical gate | zig1 `--dump-c89` output vs parent/seed `--dump-c89` output | `md5sum` match [inference] |
| Corpus gate | 818 dirs under `repro/mi_matrix/` (817 carry `main.zig`) | `repro/mi_matrix/EXPECTED_FAIL.md` manifest (per-dir expected stdout + rc) [inference] |
| Compile-only gate | `gcc -m32 -std=c89 -c` on zig1 output | gcc rc=0 [inference] |

---

## Data Flow

```
zig0 current-cycle flow:
src/bootstrap/              sf/build/zig0  (g++ -std=c++98)
  bootstrap_all.cpp
       │
       ▼                    (zig0 --header-priority-include -o <dir>/zig1.c)
sf/src/main.zig ──────────► /tmp/fx_subfolder/*.c  (zig0→C89, module .c + emitted support)
       │
       ▼                    (gcc -m32 -std=c89 -O0 -Wall -fsanitize=address ...)
                            /tmp/fx_subfolder/zig1  (release binary)

Seed flow (forward):
release/seed/zig1-seed.tgz ──► seed zig1 -ffast --dump-c89 --output-dir <out>/gen sf/src/main.zig
                              ──► gcc -c (canonical flags) ──► gcc link ──► <out>/zig1_5_clean
                              (hop2 re-dumps + relinks; hop1 md5 must equal hop2)

Test flow (zig0):
sf/src/tests/test_*.zig ──► sf/build/out_test_<name>/*.c ──► sf/build/out_test_<name>/<name> ──► run
           (zig0 --header-priority-include)    (gcc -m32 -std=c89)    (execute)
```

**Reference oracle:** while `zig0` still compiles the source it is the differential
oracle; otherwise the committed seed compiler at the recorded fixed point is the
reference for `--dump-c89` comparison.

```
sf/build/zig0 (or the seed zig1) ──► target .c ──► gcc ──► binary
```

---

## Debugging

- **`Makefile` not found** — there is no Makefile. Use the seed model (`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>`) or the legacy `bash sf/scripts/build_release.sh`.
- **`gcc` outputs warnings** — expected. Suppressed by `-Wno-long-long`, `-Wno-pointer-sign`, `-Wno-implicit-function-declaration`. Only `error:` count matters. Gate on nonzero exit, not stderr emptiness.
- **`sf/build/zig0` missing** — run `bash sf/scripts/build_release.sh` (or `build_test.sh` which auto-builds zig0 if absent).
- **Stale `.c` / `.h` errors** (`unknown type name 'Slice_*'`) — always `rm -rf` the output directory before a dump. Check `/tmp/fx_subfolder/`, `sf/build/out_test_*`, or the seed `<out>` tree for leftovers.
- **`-Werror`** — not used in the shell build scripts. Warnings do not cause build failure. The emitted MSVC/OpenWatcom companion scripts *do* enable warnings-as-errors (`/WX`, `/we`), documented as removable.
- **`-pedantic`** — not used by the build scripts. `sf/scripts/validate_c89.sh --pedantic` adds it for a separate validation pass only.
- **`zig1-dump` build disabled** — the commented-out section in `build_release.sh` is intentionally dead. Do NOT re-enable; `main_dump.zig` has a pre-existing break.
- **Test count mismatch** — `build_test.sh` runs 9 tests. Count is static: `PASS`/`FAIL` variables at top, 9 `build_and_run` calls.
- **ASan in release only** — `build_release.sh` uses `-fsanitize=address`, `build_test.sh` does not. A test binary crash with ASan-like output may not appear in test builds.
- **`-m32` requires 32-bit multilib** — on Debian/Ubuntu: `sudo apt install gcc-multilib g++-multilib`.

---

## Known Issues

- **`build_release.sh` / `build_test.sh` depend on `zig0`, which no longer parses current `sf/src`.** `zig0`'s frozen C++ front end rejects newer syntax (verified: `build_release.sh` aborts at `main.zig`'s `@intToPtr`). The seed model (`build_from_seed.sh`) is the only working rebuild path; `build_release.sh` is superseded.
- **`build_release.sh` hardcodes `/tmp/fx_subfolder`** (not isolated under `sf/build/`), so stale artifacts persist there between builds unless the script's `rm -rf` runs.
- **`-Iinclude` in both zig0 scripts is vestigial.** No `include/` exists at the repo root or under `sf/`; the tree is `src/include`. Generated module headers are quote-includes in the output dir and the compiler reaches no std module, so no angle-bracket prelude needs the path.
- **`sf/scripts/build.sh` is stale.** It builds `zig0` at the repo root (`$ROOT_DIR/zig0`), links `$WORK_DIR/*.c` with `-I"$ROOT_DIR/include"` (non-existent), and predates the self-contained output model; it is not part of the documented gates.
- **`archive_seed.sh` copies `lib/` from the working tree, not HEAD**, so an archive's `lib/` payload can correspond to a different revision than its binary/gen (seed v41 records this: binary/gen at HEAD `1b1371ba`, `lib/` from working tree `ba9aa6ae`).
- **`build_test.sh`'s test set is static** (9 `build_and_run` calls); adding a test requires editing the script.

