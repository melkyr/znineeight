# SPECFIX — Spec Accuracy + Corpus Completeness + Emitter Minor Cleanup — Design Spec

**Date:** 2026-09-10 · **Branch:** `zig1_improvements` · **Type:** documentation accuracy + corpus tooling + emitter minor cleanup

## 1. Purpose

Make the Z98 documentation tell the truth about the current self-hosted compiler, make the corpus
list reproducible from the repository, and clear the outstanding emitter/script minors recorded by
the EMITEMIT final review.

## 2. Problem

- `docs/reference/Language_Spec_Z98.md` was last changed `1cc646c9` on **2026-04-13** — the bootstrap
  era, before self-hosting began (2026-04-27). It predates every self-hosted feature the compiler now
  implements: introspection/pointer builtins, `export fn`/`export var`, arbitrary-width `uN`/`iN`,
  `packed struct`/`packed union`/`enum(uN)`, switch case-range lowering, the per-invocation target
  model (`-osl`/`-osw`/`@isWindows()`), `std_net` extern bindings, and the 8-module stdlib. Its §2
  arena description (`arena_alloc`/`*Arena`) does not match the shipped `std.arena.init/alloc/reset`.
- `README.md` is frozen at release `0.20.0`: fixed point `10f0ca2b…`, 41 `.c`, the old 4-MD5 rows
  (`302df36b`/`3591bad9`/`76056b97`/`846106ac`), corpus 428 / EXPECTED_FAIL v70, a 4-file `lib/`, and
  `--dump-c89` as the only compile path. It does not document the EMITEMIT user workflow
  (`zig1 -o DIR prog.zig` → self-contained dir → `sh build_target.sh`).
- The canonical corpus sweep list has never been committed; the `corpus_dirs_*.txt` snapshots live
  only in `/tmp`. As a result **13 committed fixtures** are silently outside the recurring `-s0`
  sweep: `catch_ret_err_{chain,direct,if,lzw_shape,multi,nested_fn,value_ctx}`, `catch_return_err_tco`,
  `orelse_ret_err`, `orelse_ret_err_void`, `store_dedup_{assign,const,valueblock}_xmod`.
- The EMITEMIT final review recorded emitter/script minors that remain open.

## 3. Scope

1. **Investigation (I) then rewrite (F) of the Z98 language spec** to the features the compiler
   actually implements today, plus a short explicit "Not yet supported" list.
2. **README refresh** to the current self-hosted state, including the EMITEMIT user workflow.
3. **A committed canonical corpus-list generator** whose output includes the 13 omitted fixtures.
4. **Emitter + script minor fixes** (listed in §4.3), which change `sf/src` and therefore move the
   self-emission fixed point → N-hop closure + seed rotation v8 → v9 at closeout.

## 4. Design

### 4.1 Spec accuracy (I → F)

The investigation audits **each section** of `Language_Spec_Z98.md` against the live compiler source —
keyword table (`sf/src/token.zig`), supported-builtin membership (`sf/src/semantic_analyzer.zig`),
type registry (`uN`/`iN`, packed types), parser (`packed`, switch ranges), lowerer/emitter (bitfields),
and the 8 std modules — and produces a section-by-section delta: *stale*, *missing*, *wrong*. It also
enumerates **designed-but-unimplemented** features for the "Not yet supported" list. Confirmed
unimplemented at plan start: the `c89-ahead` quartet `static` / `do…while` / type-alias / `volatile`
(no keywords in `token.zig`), `@errorName`, `extern struct`/`opaque`/`vector`, generics/`anytype`.

The rewrite is **in place** (`docs/reference/Language_Spec_Z98.md` is *the* spec, referenced by
README/AGENTS), reflecting only implemented behavior. The investigation STOP-presents the delta and
the rewrite outline before the fix lands.

### 4.2 Canonical corpus-list generator

A committed bash script (repo `.sh` convention; no perl/python) that prints the sorted canonical
`-s0` sweep universe. The exact universe rule is a Task-1 deliverable (the historical sweeps counted
"repro top-level + `mi_matrix` + `examples/z98`" with some container dirs excluded); the generator
must reproduce that set and include all 13 omitted fixtures. **Generator + list only** — no full sweep
re-run and no documented-count re-baseline in this plan.

### 4.3 Emitter + script minors

- **Conditional `net_prelude.h`**: `emitSupportFiles` currently writes all six support files
  unconditionally; gate `net_prelude.h` on the reachable set already computed for the companion
  scripts (net only when `std_net` is reachable). Update `scripts/check_emit_support.sh` so its
  hello/stdio probe expects five files.
- **`openSupportOutputFile` long-path guard**: the fixed `[512]u8` path buffer silently truncates;
  add a length check that aborts with a diagnostic instead.
- **`build_target.sh` exec bit**: emit a self-chmod line (`chmod +x "$0" 2>/dev/null || true`) in the
  Linux `.sh` — operator ruling: self-chmod line, NOT a new PAL `chmod` primitive.
- **Script cleanups**: `cross_build_run.sh` / `cross_nocrt.sh` legacy-branch comments say "trio" but
  append only the duo `zig_runtime.c`+`zig_pal.c`; `run_upgraded.sh` uses `timeout 30`, raise to `120`.
- **Link order**: `build_target.sh`'s modules-then-runtime order is intentional; **leave as-is and
  document** (operator ruling) — it only matters if script output ever becomes a byte-identity gate.

### 4.4 Documentation closeout

README refresh (current fixed point, seed, 4-MD5, corpus counts, 8-file `lib/`, `--dump-c89` as a
debug alias, EMITEMIT workflow), the stale `QUICK_REF` Multi-Module Build recipe, `CHANGELOG.md`,
`EXPECTED_FAIL.md` (bump only if a fixture class actually moves), and seed rotation v8 → v9.

## 5. Testing / verification

- **Spec/README**: the investigation's delta closes section-by-section; no placebo edits.
- **Generator**: running it includes the 13 fixtures and reproduces the historical sweep universe
  (count reconciled to the historical rule; counts themselves not re-baselined).
- **Emitter changes**: strict `-Wall -Wextra -O3 -fsyntax-only` clear; golden 9/9 + matrix 21/21;
  corpus `-s0` zero-asymmetric; 4-MD5 unchanged (the stdout dump path is not touched by support-file
  or build-script bytes); stdio `-o` dir contains no `net_prelude.h`, a net program does; hello
  builds+runs via `sh build_target.sh`; the emitted `.sh` becomes executable after one `sh` run.
- **Fixed point**: N-hop closure from the committed seed; new fixed point recorded; seed rotated
  v8 → v9 at closeout with archive + CHANGELOG provenance.

## 6. Risks

- **Fixed-point movement** is expected and bounded by the N-hop procedure; the seed is rotated only
  at the closeout.
- **Spec over-claiming**: mitigated by the I-task's source-grounded audit and the explicit
  "Not yet supported" list; designed-but-unimplemented features are never presented as present.
- **Generator universe drift**: mitigated by reconciling the generated set against the historical
  sweep accounting and the 13-fixture inclusion check.
- **`net_prelude.h` gating coupling**: `check_emit_support.sh` and any seed-archive support-file
  handling must stay consistent; the self-emission graph does not reach `std_net`, so the emitted
  self-host dir legitimately drops `net_prelude.h`.
