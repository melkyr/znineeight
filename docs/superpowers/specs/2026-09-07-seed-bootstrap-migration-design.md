# Seed-Model Migration — Committed zig1 Bootstrap Seed (zig0-independent rebuild path) — Design Spec

> Date: 2026-09-07 · Branch: zig1_improvements · Status: operator-approved design (decisions locked 2026-09-07)

## Goal

Establish a committed, **rotating bootstrap seed** — a packed archive of the current zig1 binary + its self-emission C89 — so the compiler can be rebuilt from source with **only `gcc`**, never `zig0`. This is the forward survival path: zig0's front end is frozen, and every future language/syntax/compaction change to `sf/src` risks making `sf/src` uncompilable by zig0. The seed replaces zig0 as the ultimate authority for rebuilding zig1, following the industry-standard model used by Rust (stage0 snapshot), Go (`GOROOT_BOOTSTRAP`), and Zig (`zig-bootstrap`).

zig0 itself is **kept in-tree and active** for the current compiler cycles (`build_release.sh` unchanged). The seed is the committed safety net, rotated once per completed plan.

## Background / problem (evidence)

- zig1 is self-hosted (`sf/src/*.zig`), but today the reference compiler under test `/tmp/fx_subfolder/zig1` is rebuilt by `sf/scripts/build_release.sh`, which **first g++-rebuilds zig0** from `src/bootstrap/bootstrap_all.cpp`, then dumps `sf/src/main.zig` (gen-0), then gcc-links. No `build_release.sh` run → no reference zig1.
- zig0's C++ front end is **frozen** (type checker unchanged since 2026-05-11; oracle rules in QUICK_REF). INTWIDTH (`uN`/`iN`) is already a language feature set zig0 cannot fully express; PACK-CORE (packed structs), compaction, and further syntax upgrades will push `sf/src` beyond zig0's subset. When that happens, `build_release.sh` can no longer produce a zig1 — and nothing on disk is preserved to build the next one.
- The self-host cycle is already **closed**: at HEAD `1079d90a` the two-hop self-emission reproduces a byte-identical fixed-point binary (md5 `24da89b9d6398ff24f4baecfe2e23f77`, 41 `.c`, 0 `error[`, 0 PANIC, hop1==hop2 `cmp` clean). So a preserved zig1 **can** build the next zig1 by self-emission — the missing piece is a durable, committed, non-`/tmp` copy of that compiler plus its C form.
- `release/staging/` (the 0.20.0 artifact staging dir) is git-ignored and holds a **pre-INTWIDTH** `zig1_linux32` (`10f0ca2b`), so nothing durable yet represents the current INTWIDTH-era compiler.
- Current durable facts (measured 2026-09-07 at HEAD `1079d90a`, verified): reference `/tmp/fx_subfolder/zig1` md5 `3707d33bd1d3779c4a98aab9d5be1841` (zig0-built, valid at HEAD); self-emission fixed point `24da89b9d6398ff24f4baecfe2e23f77`; self-emission C = 41 `.c` + 42 `.h`; std lib = 4 files (`std.zig`, `std_arena.zig`, `std_io.zig`, `std_net.zig`); link rule for self-emission C = `zig_runtime.c` + `zig_pal.c` + `c_exit.c` (`gcc -m32`).

## Operator rulings (binding)

1. **zig0 stays in-tree and active** while we operate with the current compiler cycles. This plan does NOT remove `src/bootstrap`, `README_zig0_bootstrap.md`, `docs/Building.md`, or the zig0 oracle references. (Removal is a separate future decision.)
2. **Seed binary = the zig1 built with zig0** (the current reference, md5 `3707d33b` at capture), NOT the self-emission fixed point. The packed C is the **self-emission set** that zig1 emits for itself (41 `.c` + 42 `.h`).
3. **Seed is committed (git-tracked)**, under `release/seed/` — a new tracked path, distinct from git-ignored `release/staging/`. The seed is a packed, compressed archive of binary + C; git history of the rotating file is the "go back in commits" mechanism.
4. **Rotation only at plan closeout**: one canonical rotating archive `release/seed/zig1-seed.tgz`. Each completed plan that moves the fixed point rotates the seed (new zig1 binary + new self-emission C), overwriting the archive and appending a provenance entry. Prior seeds remain recoverable in git history.
5. **Seed rotation tracking lives in `release/seed/CHANGELOG.md`** (a dedicated per-seed changelog, NOT the release-versioned root `CHANGELOG.md`). One entry per rotation: date, HEAD sha, seed binary md5, self-emission C file count, fixed-point md5.
6. **Gates stay equal only if the changes don't legitimately alter them** — the existing operator-ruled re-baseline rule continues unchanged (4-MD5 / golden / matrix / corpus / fixed point). This infra migration itself must be byte-neutral on every gate.

## Architecture

### Seed archive layout (`release/seed/zig1-seed.tgz`)

Single gzip tarball, committed. Contents (top-level dir `zig1-seed/`):

| Path | Contents |
|------|----------|
| `zig1-seed/zig1` | the seed binary — the zig0-built reference compiler (md5 recorded in CHANGELOG) |
| `zig1-seed/gen/` | the seed's own self-emission C89: 41 `.c` + 42 `.h` (incl. per-module headers + `zig_special_types.h`) |
| `zig1-seed/c_exit.c` | link source (`sf/src/c_exit.c`, 58 B) |
| `zig1-seed/runtime/` | link/include sources needed to compile `gen/`: `zig_runtime.c`, `zig_runtime.h`, `zig_pal.c`, `zig_compat.h`, `zig_special_types.h` (`net_prelude.h` is NOT included — verified 0 references in a linux `-osl` self-emission dump; Task-1 §3.1, archive excludes it per the committed seed v0) |
| `zig1-seed/lib/` | the 4 std `.zig` files (`std.zig`, `std_arena.zig`, `std_io.zig`, `std_net.zig`) |
| `zig1-seed/SEED_README.txt` | provenance + exact rebuild recipe (below) |

`sf/src` `.zig` sources are NOT duplicated in the archive: the pinned `HEAD` sha recorded in `CHANGELOG.md` identifies the source; the source lives in git.

### Rebuild recipes (recorded verbatim in SEED_README.txt)

- **Rebuild from the seed binary (primary, forward path):** `./zig1-seed/zig1 --dump-c89 --output-dir <fresh> sf/src/main.zig` from the repo root (current `sf/src`), then `cd <fresh>`, `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <repo>/sf/src/include -c *.c`, link `*.o` + `zig_runtime.c` + `zig_pal.c` + `c_exit.c` → next zig1. Verify two-hop fixed-point closure.
- **Rebuild the seed binary itself from C (fallback if the binary is lost):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I zig1-seed/runtime -c zig1-seed/gen/*.c`, link `*.o` + `zig1-seed/runtime/zig_runtime.c` + `zig1-seed/runtime/zig_pal.c` + `zig1-seed/c_exit.c` → a zig1_5-class binary (reproduces the recorded self-emission fixed point, NOT the zig0-built reference md5 — both are the same compiler state at the pinned HEAD).
- **std install:** the produced binary needs the std lib next to it (`lib/` with the 4 std `.zig`) — copied from `zig1-seed/lib/` or `<exe_dir>/lib`.

**Flag-set note (AMENDMENT, operator 2026-09-07):** every gcc `-c` command MUST use the full canonical build flag set (`-O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration`). Verified: the self-emission fixed point `24da89b9…` reproduces ONLY with `-Wall` present; without it the deterministic result is `0696756c…` (cosmetic assembler local-label numbering only, `.text` instruction-identical — not a code difference). This is consistent with the warning-reduction objective: the memory-refactor W2 series already made the emitted C warning-clean at `-Wall -Wextra -O3` (17,788 → 0 warnings; the 3 `-Wno-*` are the structural carve-outs for long-long / pointer-sign / implicit-function-declaration). The stricter `-Wall -Wextra -O3 -fsyntax-only` warning-clean check is a SEPARATE verification gate, never the build command.

### The bootstrap-staging constraint (the rule that keeps the chain alive)

A seed compiled at commit N can only compile `sf/src` written in the language subset that seed already supports. Therefore:

1. The compiler code implementing a NEW feature must be written in constructs the CURRENT seed already understands.
2. Only after that feature lands AND a new fixed-point binary exists (which supports the feature) may `sf/src` itself be rewritten to use the new syntax.
3. At that closeout the seed rotates to the new fixed point, so the next plan starts from a seed that understands everything shipped so far.

This rule must be encoded in AGENTS.md and referenced by every future plan's Global Constraints so no plan paints itself into a "seed can't compile the new source" corner.

### Transition path

- **Phase 0 (this plan):** capture seed v0 at HEAD `1079d90a` (binary `3707d33b`, self-emission C set), commit it + `CHANGELOG.md`, add the build/archive scripts, parametrize the self_compile scripts on a seed path, and update AGENTS.md / QUICK_REF.md / plan conventions. zig0 remains the active reference builder.
- **Later (future plans):** each plan that moves the fixed point rotates the seed at closeout (`scripts/seed/archive_seed.sh`), keeping the chain: seed_N → (self-emission) → fixed point_N+1 → seed_N+1.
- **Eventual zig0 drop:** when a plan makes `sf/src` uncompilable by zig0, the last zig0-built reference is the archived seed; from then on the reference compiler for gates is built **from the seed**, and `build_release.sh`'s zig0 step is superseded by `build_from_seed.sh`.

## Gates

- This migration is infra/docs-only (`release/seed/`, `scripts/seed/`, docs). No `sf/src` change. All gates must remain byte-identical: 4-MD5 (gol `302df36b` / lisp `3591bad9` / json `76056b97` / mud `846106ac`), golden 9/9, matrix 21/21, corpus 433-dir `-s0` state, self-compile fixed point `24da89b9`.
- Archive correctness gate: the committed tgz, unpacked in a fresh dir, rebuilds a working compiler via the recorded recipes (dump rc=0, gcc rc=0, a hello-class program runs; two-hop closure holds).

## Out of scope

- Removing zig0 or its sources/docs/oracle references.
- Re-staging the 0.20.0 release artifacts at the new fixed point (separate release task).
- Any `sf/src` behavior change.
- The src_sh self-containment migration (`@cInclude` for compiler internals, dropping `__bootstrap_*` symbols) — orthogonal; the seed model works regardless of whether src_sh ever lands.

## Success criteria

1. `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` committed and tracked at HEAD; archive unpacks to the documented layout.
2. Unpacked seed rebuilds a working compiler using only `gcc` (both recipes verified); recorded md5s (`3707d33b` binary, `24da89b9` fixed point) reproducible.
3. `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` exist and work; `build_zig1_5.sh`/`build_next_gen.sh` accept a seed/compiler path.
4. AGENTS.md / QUICK_REF.md / plan conventions updated: seed model, rotation protocol, bootstrap-staging constraint.
5. All gates byte-identical (no re-baseline).
