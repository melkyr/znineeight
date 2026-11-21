# Phase 1 M1 — Compiler RSS/peak Pre-flight — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the compiler's real peak RSS/arena usage on the standard workload in README + QUICK_REF, with a repeatable measurement recipe, before Phase 1 grows the std.

**Architecture:** Docs-only. Measurement wraps the existing seed build + stdlib gate + one large example compile with `/usr/bin/time -v`; numbers land in `README.md` and `docs/sf/QUICK_REF.md` next to the existing memory claims.

**Tech Stack:** bash, `/usr/bin/time -v`, existing `scripts/seed/build_from_seed.sh`, `scripts/stdlib/verify_stdlib.sh`.

**Spec:** `docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` (§3 constraints, §6 demo RAM budget, §8 M1)

## Global Constraints

- Docs only — zero `sf/src`, example, or script changes.
- Numbers must be measured on this host from committed state (seed v111, archive `5dc851a1a96c0776ef36e8e5b29774b7`, fixed point `21c957730d268f1e7883176fa5413b65`), each with the exact command + observed output.
- Stated budget everywhere: demos 16 MB target / 32 MB hard ceiling; compiler target <16 MB (recorded reality may exceed — record honestly).
- Commits: `docs: Phase 1 M1 compiler RSS truth-up` then `docs(sdd): M1 report`; `git add -f` explicit paths; no push; `run.err` untouched.

## Review Focus

1. A number recorded without its command is unverifiable → every figure carries command + output.
2. Peak RSS measured on the wrong binary (hop1 vs hop2) misleads → measure the fixed-point binary explicitly.
3. Arena vs RSS conflated → record both where the harness exposes them.
4. Recipe drift (host-specific paths) → recipe must run as written from repo root.
5. "Current value exceeds target" omitted → honesty clause in the doc text.

---

### Task 1: Measure compiler peak RSS + arena

**Files:**
- Create: `.superpowers/sdd/2026-10-21-phase1-m1-preflight-rss-plan/task-1-report.md` (measurements only)

**Interfaces:**
- Consumes: `release/seed/zig1-seed.tgz`, `scripts/seed/build_from_seed.sh`, `scripts/stdlib/verify_stdlib.sh`.
- Produces: measured table (workload, max RSS KiB, wall s) fed to Task 2 verbatim.

- [ ] **Step 1:** Build the fixed-point compiler: `FIXED_POINT_MD5=21c957730d268f1e7883176fa5413b65 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_build`. Verify `md5sum /tmp/m1_build/zig1_5_clean` == fixed point.
- [ ] **Step 2:** Measure three workloads with `/usr/bin/time -v` (capture `Maximum resident set size`): (a) the two-hop seed build itself, (b) `bash scripts/stdlib/verify_stdlib.sh /tmp/m1_build/zig1_5_clean`, (c) one compile of `examples/z98/z9play/main.zig` (`-fsafe` emit + `build_target.sh linux`).
- [ ] **Step 3:** Write the report table (workload | max RSS KiB | wall s) with each command and observed output; state whether the <16 MB compiler target currently holds (expected: seed build exceeds slightly — record the number).
- [ ] **Step 4:** Commit `docs(sdd): M1 report` (report only).

### Task 2: README + QUICK_REF truth-up

**Files:**
- Modify: `README.md` (memory/resource section)
- Modify: `docs/sf/QUICK_REF.md` (resource section near the build recipe)

**Interfaces:**
- Consumes: Task 1 table.
- Produces: published numbers + recipe + the Phase 1 demo budget statement.

- [ ] **Step 1:** Add to both docs: the measured table (3 rows), the exact `/usr/bin/time -v` recipe, the compiler target sentence ("<16 MB goal; current peak recorded above; tracked per Phase 1 milestone"), and the demo budget ("16 MB target / 32 MB hard ceiling, enforced with `ulimit -v 32768` + recorded peak RSS").
- [ ] **Step 2:** Verify prose: no stale memory claim contradicts the new table; `git diff --check` clean.
- [ ] **Step 3:** Commit `docs: Phase 1 M1 compiler RSS truth-up`.
