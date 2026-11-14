# undersanded M16 — Win98 validation + ship — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship-ready *Undersanded* on real Windows 98SE hardware at the 64 MB floor: full loop completable, crash UX proven (3 files), manual + CD laid out, imports clean — the project's definition of done.

**Architecture:** Release candidate = `under.exe` + `undtool.exe` + `data.z98` + `assets/` (loose `.ZSP`) + `manual/` (HTML 4.0, same content as embedded pages) + `README`. Operator validation session on real hardware against the spec §34 manual row; crash paths exercised with deliberate traps; final import + budget audit.

**Tech Stack:** Everything already built; `check_win9x_imports.sh <exe> 9x`; `std.debug` crash trio (§33).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §22 (constraints), §32 (data dir on CD install), §33 (crash: `crash.dmp` registers / `crash.log` pre-allocated backtrace / `crashstate.dat` best-effort), §34 (Win98 fidelity row = manual), §35 (budgets: ≤8 MB working set, ≤8 ms dirty frame), §36 (M16 row), §40 (ship checklist).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m15-balance-plan.md`. NEXT: none — project complete.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Manual gates are **operator-attested** (record evidence in NOTES.md): full loop on Win98SE / 64 MB; no crash dumps during normal play; ambient audio gapless on real hardware (§31); focus loss pauses + silences on real hardware. CD scenario must exercise the §32 writability fallback (run from read-only medium → saves in `C:\WINDOWS\TEMP\UNDERSAN\`, path shown once). Fatal/non-fatal copy exactly §33. All tiers green on the RC (regression rule).

## File Structure

- `examples/z98/undersanded/release/` — RC staging (exes, `data.z98`, `assets/out/*.zsp`, `assets.man`, `manual/*.html`, README).
- `examples/z98/undersanded/manual/` — HTML 4.0, one mechanic per page + Legends (content = the embedded `[text]` pages, republished).
- `examples/z98/undersanded/tests/tier_m16_ship.sh`, `tests/crash_probe.zig` (deliberate trap fixture).

## Review Focus

- Crash files that don't appear (trap handler faulting inside itself; buffered stdout lost) → `@stderrWrite` + pre-allocated backtrace verified by the deliberate-trap probe on real hardware.
- CD fallback untested (the path most likely to break on real installs) → read-only-medium run is a mandatory session item.
- Working-set drift >8 MB on 64 MB hardware (ambient + assets resident) → `measure_rss.sh` is a **host/Wine proxy (evidence only — Wine RSS is recorded, not gated, z9gb `tests/measure_rss.sh` precedent; Win98 has no such tool)**; the real gate is **operator attestation via System Monitor** (recorded reading + screenshot in NOTES.md).
- Import creep in the final link (audit both exes after last-mile edits) → **strict import assertion: both exes import EXACTLY KERNEL32/USER32/GDI32** (ddraw/dsound via dynamic load only; `check_win9x_imports.sh` 9x mode whitelists DDRAW/WINMM/WSOCK32 — too weak, assert the exact set, z9edit `tier_edit_gui.sh` precedent). Whitelist amendment + operator sign-off for `MsgWaitForMultipleObjectsEx` (G4) in the check script's USER32 list.
- Manual/embedded copy divergence (two sources of truth) → diff test: HTML text vs `[text]` section content.

---

### Task 0: Preflight

- [ ] Freeze RC scope in NOTES.md: every tier green (M1–M15), git clean, known-issues list empty or explicitly waived.

### Task 1: Crash UX (`crash_probe.zig` + §33 paths)

- [ ] Deliberate trap fixture: overflow/OOB under `-fsafe` writes `crash.dmp` (registers via `writeCoreDump`) + `crash.log` (pre-allocated backtrace buffer) + best-effort `crashstate.dat` (skipped if arena poisoned); then error screen copy "The game has crashed. A crash file has been written. Please report it." Test asserts all three files' shapes (crash.dmp names per §33 line format). Commit `example(undersanded): crash UX probe`.

### Task 2: Manual HTML + release staging

- [ ] Generate `manual/*.html` (HTML 4.0, numbered pages 1–8 + Legends) from the embedded `[text]` content; diff test vs embedded. Stage RC in `release/` (art + terminal entry points, assets, manifest) + **CD image layout**: install steps, `manual/`, `README` with **DX7 runtime prerequisite statement** (98SE ships DX6a; IDirectDraw7 needs DX7), optional DX7 redist folder. `tier_m16_ship.sh`: full CI battery green on staged build + imports clean + budget audit (§35) + manual diff. Commit `example(undersanded): manual + release staging`.

### Task 3: Win98SE operator session (manual gate)

- [ ] On real hardware (64 MB): install to HDD; full loop fresh → … → boss kill → score → continue; **CD-scenario run** (read-only medium: fallback dir + path shown once); alt-tab pause/silence; ambient gapless; save/restore across reboot; idle CPU 0% (gfxWaitEvent); working set ≤8 MB (System Monitor attestation; host `measure_rss.sh` proxy recorded alongside); no crash dumps in normal play; **deliberate trap on hardware** → crash trio files written + error screen shows (SEH behavior ≠ Wine — mandatory item); **256-colour desktop** → art mode refused, terminal fallback with logged reason; **DX7 runtime prerequisite** present/redist noted on CD; **2nd-save + multi-save regression on FAT32** (the MoveFileA `.bak` bug class — saves 2, 3, 4 must all succeed); **soak**: ≥1 h idle + repeated save/restore. **Perf ≤8 ms dirty frame (§35):** consume the `--perf` log (toggle → frame-timing percentiles in errors.log) for the measurement/waiver on the 64 MB box — operator records numbers or signs an explicit waiver. Record **each item as attested evidence with artifact shape** (screenshot / pasted file contents / pasted log lines) in NOTES.md. Commit `docs(undersanded): M16 operator session record`.

### Task 4: `tier_m16_ship.sh` + close

- [ ] Update `scripts/win32_cross/check_win9x_imports.sh` to the strict exact-set check for both exes (KERNEL32/USER32/GDI32 only; DDRAW/WINMM/WSOCK32 rejected) and add `MsgWaitForMultipleObjectsEx` to the USER32 allow-list; record operator sign-off in NOTES.md.
- [ ] Tier: Task 1–2 tests + RC battery + manual diff + imports + budgets. Gate report: full loop completable on Win98SE/64 MB; CD ready. Final commit `release(undersanded): ship candidate` + project retrospective line in NOTES.md (what the M2 three questions and M15 numbers settled). STOP-present for final sign-off.

**Gate (project done):** full loop on Win98SE / 64 MB; crash trio proven; manual + CD ready; all milestones' gates green on the RC.
