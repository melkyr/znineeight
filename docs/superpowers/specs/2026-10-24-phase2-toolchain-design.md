# Phase 2 — Self-Hosting Toolchain (umbrella) — Design

**Status:** approved (operator, 2026-10-24).
**Blueprint:** `examples/projects_phase2.txt` (Projects 3 + 4), `examples/roadmap.txt` §Phase 2.

---

## 1. Why

Phase 2 makes the toolchain self-sufficient **on the target machine**: the debugger
lets you diagnose the binaries `zig1` emits (Project 3), the editor lets you modify
the source that produces them (Project 4). Neither is glamorous; both are load-bearing
infrastructure for Phases 3–5.

The blueprint's true mandate for Project 4 is not user convenience alone — it is a
**minimal windowed DirectDraw/GUI layer**: *"a stress test for your DirectDraw layer"*
(`examples/roadmap.txt:28`), the COM / `extern "stdcall"` vtable rehearsal that the
Phase 5 D3D6 game consumes. The editor is the vehicle that proves the layer.

## 2. Milestone map (this is the contract for "which project is which")

| Tag | Project | Deliverable | Plan | Spec |
|---|---|---|---|---|
| `P3-M1..M4` | Project 3 — Source-Level Debugger | `--debug`/`-d` sidecar map + `z9dbg` (ptrace / Win32 Debug API) | `docs/superpowers/plans/2026-10-24-phase2-z98-debugger-plan.md` | `docs/superpowers/specs/2026-10-24-phase2-z98-debugger-design.md` |
| `P4-M1..M3` | Project 4 — GUI layer + `z9edit` | `std_gfx` (minimal windowed DirectDraw) + `z9edit` single-file editor | `docs/superpowers/plans/2026-10-24-phase2-gfx-editor-plan.md` | `docs/superpowers/specs/2026-10-24-phase2-gfx-editor-design.md` |

- Every plan task, commit, and report carries its `P3`/`P4` tag.
- Execution order: **P3 first** (plan is approved and ready), then **P4**.
  Seed rotation: P3 closeout rotates `release/seed/` v119 → **v120**
  (compiler-source-changing: map code is compiler `gen/`, `hop2 == hop3`);
  P4 closeout rotates v120 → **v121** (**std-payload-only**: `std_gfx`/
  `std_gfx_pal` grow `lib/`, the self-emission fixed point is UNCHANGED,
  `hop1 == hop2` — v103 precedent, QUICK_REF rotation protocol).
- The P3 spec/plan are binding and untouched by this umbrella. Where this document
  and a project spec disagree on that project's internals, the project spec wins.

## 3. Shared Phase 2 constraints

- Z98 subset; no new language features; no compiler-pipeline refactor beyond the
  P3 map side-table work already contracted in the P3 spec.
- Both projects are **off the default compiler path**: no compiler flag ⇒ no output
  change (P3 `--debug` gate; P4 adds no compiler flag at all — it is user-side code).
- Windows target is **Win98 first** (Win32 Debug API / DirectDraw); Linux is the
  development platform. Linux story for P4 GUI is **Wine only** (decision
  `ef95c21b` in `.opencode/memory`): one graphics backend, no native Linux GUI
  backend until a user requests one.
- RAM: debugger < 32 MB (`ulimit -v 32768`), 16 MB target; editor likewise
  budget-bound (P4 spec §6).
- Test programs: `hello`, `mud_server`, `lisp_interpreter_curr`, then `z9torr`
  or `z9play` (P3 spec §5); P4 editor gates use the P4 spec's own set.
- Seed model unchanged: `release/seed/` rebuild, rotate at closeout via
  `scripts/seed/archive_seed.sh`; `run.err` untouched; no push.

## 4. What is left to the builder

Each project's plan owns its task granularity. This umbrella owns only the
tagging, the order, and the seed-rotation schedule above.
