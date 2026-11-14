# zig1 Spill Backend Configurability + Additional Spill Gains + RSS Budget — Design

**Date:** 2026-09-02
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start
**Baseline:** HEAD `40d72e04` (F-TABLE); reference zig1 `/tmp/fx_subfolder/zig1`, self-compiled `/tmp/zig1_5/zig1_5_clean`; `pool=15,324 K` (below the 16,384 K target)

## Goal

Give the user control over the compiler's memory/I-O tradeoff and squeeze more of the remaining pool: (1) disk-back the AST side tables for further gains, (2) introduce a **spill backend** abstraction (Disk vs Ram) selected by an immutable flag array, (3) add a **`-mm<N>`** hard RSS budget and **`-s<N>`** decremental spill levels (documented in `--help` + README), and (4) unify the spill temp formats (via an I-task evaluation).

## Scope Decisions (operator-ruled 2026-09-02)

- **New plan** — the allocator-crux-measurement plan is CLOSED (its tasks F-2/F-3/F-4/F-FREE/I-F1/I-TABLE/F-TABLE complete, I-SPILL investigated a NO-GO on *automatic* gating; the operator's new framing is *user-selected* levels, which this plan implements).
- **Spill levels are decremental** (m1340/m1345): `-s0` = every spill on disk (today's state); increasing N **deactivates** spills from the head of an ordered registry (→ Ram), leaving the tailmost spill(s) on disk. The mechanism is an **immutable (const) array of per-spill flags** that directly selects each `SpillStore`'s backend.
- **Deactivation order = addition order** (oldest spills first — they were the upfront largest offenders): S-AST(nodes) → S-LIR → S-HASH → S-RES → S-SIDE(new).
- **Backend split into I + F** (m1347): `I-SBackend` (read-only design of the `SpillStore` abstraction + per-spill I/O-site census) then `F-SBackend` (implement).
- **`-mm` split into I + F** (m1347): `I-MM` (read-only: current `--max-mem` plumbing, the friendly-switch semantics, enforcement point) then `F-MM` (implement).
- **`-mm<N>` = hard RSS budget**, default **64 MB** when unset, friendly switch syntax (`-mm64` = 64 MB) so command lines don't run out of char budget; enforced via the existing `checkCombinedPeak` tripwire.
- **Unified spill format I-task** (m1345): evaluate ALL spill temp formats so they share "a likely same thing" (a common block/record shape + validation), incl. the `resolved_types` 10→5 B/node drop.
- **Inline review given; approved** (deactivation order confirmed); docs written now.

## Background — measured facts (2026-09-02)

- **Pool trajectory:** 25,742 K → F-2 23,921 K → F-3 21,874 K → F-4 21,141 K → F-FREE 18,378 K → F-TABLE 15,324 K (≈14.96 MiB, **below the 16,384 K target**). Remaining resident dead-after-lowering: AST side tables `extra_children`+`extra_ranges` ~1.4 MB (F-4 measured "1,458 K") + `identifiers`/int/float/string/`fn_protos` ~0.6–1.0 MB; `coercion_table` ~0.2–0.5 MB; small maps.
- **Four spills are always-on today** (all I/O via `pal.stream*` on a `FILE*`):
  - **S-AST** (nodes): `ast.zig` block spill — 114,688 B blocks (4096 nodes × 24 B + 4096 payload × 4 B), `astBlockSpillHead`/`astBlockFaultIn` at offset `bi × AST_BLOCK_REC_SIZE`, 8-slot resident ring, `spill_handle`. Self-gates below 4096 nodes (no file).
  - **S-LIR**: `lir_stream.zig` — per-fn byte stream (`lirStreamAppend` writes 44 B header + raw arrays; `lirStreamReadFunction` faults in), disk-slot-driven emission.
  - **S-HASH**: `module_registry.zig` — `path_to_id`/`content_to_id` spilled at end of import resolution.
  - **S-RES**: `resolved_type_table.zig` — dense 10 B/node (types u32 + flag u8 + source u32 + src_flag u8), 4090 B blocks, 8-slot write-back cache, `.zig1_res.tmp`.
- **The `SpillStore` abstraction is clean** (verified): all four call `pal.streamWrite/Read/Seek` on a handle; a `write(off, bytes)`/`read(off, bytes)` interface over Disk (pal) or Ram (growable sand, offset-addressed) is a mechanical substitution. Data is byte-identical in both modes → 4 MD5 gates hold in both modes (no dual codegen).
- **`--max-mem` exists** (M0, commit `aceca4ee`): opt-in tripwire, space-syntax `--max-mem N` (KB), gates `pool.peak` vs `alloc.max_mem` at `checkCombinedPeak` (allocator.zig:219-228); default `RELEASE_MAX_MEM` ≈ 16 GiB KB-semantics (inactive).
- **Current gates** (authoritative): gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `4591fef0`. Golden fixtures 9. Self-compile 41 `.c` / 0 err / 0 PANIC. Ref 0-warning.

## Architecture — 5 phases, 11 tasks

1. **Additional gains:** I-SIDE (census + read order) → F-SIDE (disk-back the side tables; extend S-AST machinery or a dedicated block spill). Prize ~1.4–2 MB.
2. **Unified spill format:** I-FMT (evaluate all spill temp formats; propose a common block/record shape + validation + the `resolved_types` 10→5 B/node drop) → F-FMT (apply it; byte-identity-safe).
3. **Storage backend:** I-SBackend (design `SpillStore` + per-spill I/O-site census) → F-SBackend (implement; route all five spills through it).
4. **Config:** I-MM (current `--max-mem` plumbing + `-mm64` semantics) → F-MM (implement `-mm<N>`, default 64 MB, enforced) → F-S (`-s<N>` decremental levels → immutable flag mask; `--help` + README).
5. **GATE:** full sweep + reconciliation across `-s0..-sN` and `-mm` combinations.

## Success criterion

`pool=` stays ≤ 16,384 K at `-s0` (spill-all), drops further at higher `-s` levels (deactivated spills resident), and `-mm<N>` enforces a hard ceiling (ICE on exceed, default 64 MB). All modes keep the 4 MD5 gates byte-identical-or-re-baselined with golden 9/9 evidence, self-compile clean, ref 0-warning.

## Constraints

- Z98 dialect; `edit`/`fastedit` only; never touch `sf/build/out_release/`.
- All spill I/O via `pal.stream*` (AMENDMENT 12 rule: no self-declared externs); S-FIX-1 I/O-error discipline (ICE on short write/read/seek).
- 4 MD5 keep-or-re-baseline with golden runtime evidence (runtime is the bar).
- Ledger `.superpowers/sdd/progress.md`; mnemoria `--agent spillconfig-session`.
- Report file `.superpowers/sdd/task-SPILLCONFIG-report.md` (gitignored; WARNING `task-1-report.md` is TRACKED).
- Pre-existing dirty files never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`.
- Reference rebuild `timeout 900 bash sf/scripts/build_release.sh` (repo root, gate `=== [release] Done ===`, reinstall std lib); self-compile `timeout 900 bash scripts/self_compile/build_zig1_5.sh`; `timeout 120` on invocations; `--output-dir` must pre-exist.
