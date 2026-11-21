# undersanded M12 — audio + options — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DirectSound audio (ambient loop + 4 cues, mandatory focus-loss Stop) and the options menu (volume, keybindings, save slot, colour-blind) — alt-tab pauses and silences, options persist.

**Architecture:** `sf/src/std_audio.zig` (G9 — the std exception for this milestone) wraps DirectSound **static buffers**: WAV load (22.05 kHz mono), `Play(0)` / `Stop()` / `SetVolume` (0–100 → negative hundredths-of-dB); **cue replay protocol: `Stop()` → `SetCurrentPosition(0)` → `Play(0)`** — a finished buffer resumes at end = silence otherwise; caps `DSBCAPS_GLOBALFOCUS|DSBCAPS_STATIC|DSBCAPS_CTRLVOLUME` (**CTRLVOLUME mandatory** — `SetVolume` returns `DSERR_CONTROLUNAVAIL` without it), never `LOCHARDWARE`; cooperative level `DSSCL_NORMAL`. `audio.zig` (game side) owns ambient start-once-loop and cue overlap; `options.zig` owns the menu + persistence in the save (`[options]` section). Pause-on-focus reuses M1/M9 `focus_lost`/`focus_gained` + `gfxWaitEvent` idle.

**Tech Stack:** Z98 → C89 `-fsafe`; dsound.dll dynamic load (no import lib); std_file for WAV; M7 save for options.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §31 (whole audio section: ambient 90 s = 3,969,000 bytes, caps, Play looping, focus Stop mandatory, volume, gapless crossfade; cues hit ≤0.5 s / subdue ≤1 s / kill ≤1 s / bosskill ≤3 s, static at startup, overlap allowed, **no subdue-failure cue**), §29 (timing: ambient not timed, focus lost stops ambience, no auto-resume), §26 (options at start menu only; Esc menu has none), §34 (focus-pause row), §38 S5/T1/T2, §36 (M12 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m11-boss-score-plan.md`. NEXT: `2026-11-12-undersanded-m13-t234-content-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Audio is never fatal (spec §33: cannot open → continue silently). No threads, no callbacks, no streaming (T1). **Focus loss: logic pauses AND `Stop()` fires — mandatory**; restart only after player confirms resume (T2). Volume persisted via M7. Colour-blind mode: T8 dotted border + inline numerics are unconditional; the option ON adds hatch-pattern bar fills (the defined delta). `undtool.exe` runs audio-less (console mode never opens dsound).

## File Structure

- `sf/src/std_audio.zig` — `audioOpen() ?*Audio`, `audioLoadWav(path) ?*Buffer`, `audioPlay(buf, loop: bool)`, `audioStop(buf)`, `audioSetVolume(v: i32)` (0–100 → dsound units), `audioClose`. Errors named (R15).
- `examples/z98/undersanded/audio.zig` — ambient (start once, loop) + cue table (4), subdue-failure deliberately silent, screen shake already on the warn path (M9).
- `examples/z98/undersanded/options.zig` — options state + menu screen + save section.
- `examples/z98/undersanded/tests/audio_test.zig`, `tests/tier_m12_audio.sh`, `tests/run_dsound_probe.sh` (pattern after z9gb's).

## Review Focus

- Focus-loss audio leak (GLOBALFOCUS keeps playing without `Stop()` — the classic bug): tier asserts `Stop` on `focus_lost` and no restart before resume confirm (spec §34 row).
- LOCHARDWARE caps on a 3.9 MB buffer (fails on 4 MB cards): caps assertion in the load path + probe.
- WAV decode edge cases (mono/16-bit/22.05 kHz only — reject others cleanly) → negative fixtures.
- Options persisted inconsistently (volume applied at load before buffers exist) → order test: load save → open audio → apply volume.
- Keybinding rebind collisions (two actions same key) → binding validation test.

---

### Task 0: Preflight

- [ ] Obtain/generate the ambient WAV (90 s, 22.05 kHz mono, gapless — offline 250 ms tail→head crossfade per §31) and 4 cue WAVs to the lengths above; record provenance in NOTES.md. z9gb's `run_dsound_probe.sh` as the platform pattern.

### Task 1: `std_audio` buffers + WAV load

**Interfaces:** as File Structure. WAV parser: RIFF/WAVE, PCM 16-bit mono 22.05 kHz only; caps `DSBCAPS_GLOBALFOCUS|DSBCAPS_STATIC|DSBCAPS_CTRLVOLUME`; **reject LOCHARDWARE**. **Vtable discipline:** exact MinGW dsound.h slot order (precedent `sf/src/std_dsound_pal.zig:23`); type `SetCurrentPosition` (:149) and `SetVolume` (:151) — both placeholders in the streaming PAL.
- [ ] Unit tests: WAV parse accept/reject matrix (stereo → reject, 44.1 k → reject, truncated → reject); **mock-buffer state machine tests (the gate):** second-fire of every cue asserts Stop→SetCurrentPosition(0)→Play sequence; volume path asserts CTRLVOLUME → SetVolume called. Probe run (real device) = SLOW evidence only. Implement. PASS. Commit `feat(std): std_audio static buffers + WAV load`.

### Task 2: Ambient + cues (`audio.zig`)

**Interfaces:** `pub fn ambientStart/Stop`; `pub fn cuePlay(kind)` kinds HIT/SUBDUE/KILL/BOSSKILL; **overlap policy:** HIT gets 2 rotating duplicate buffers (rapid re-triggers don't cut each other); cold cues (SUBDUE/KILL/BOSSKILL) restart via the replay protocol; hooks: any Strike lands→HIT, subdue success→SUBDUE, kill→KILL, Derelict first kill only→BOSSKILL; **subdue failure → no cue** (warn log + shake only).
- [ ] Tests: trigger matrix (every hook fires exactly the right cue; bosskill only on first kill); silence on subdue failure (cue counter 0); ambient single-start. Implement. PASS. Commit `example(undersanded): ambient + 4 cues`.

### Task 3: Pause-on-focus (T2)

- [ ] Wire `focus_lost` → pause logic, `audioStop(ambient)`, keep last frame; `focus_gained` → **no auto-resume** (resume confirm). Test via `gfxTestFocus`: logic halts (cycle/action counters frozen), ambient stopped, resume requires confirm. Commit `example(undersanded): pause-on-focus + audio Stop`.

### Task 4: Options (`options.zig`)

**Interfaces:** options state `{volume 0–100, keybinds[9], colorblind bool}` persisted in save `[options]`; **save_slot bootstrap (the chicken-egg fix):** save_slot is read from `options.cfg` beside the saves (writability dir, read at boot BEFORE any save load); everything else in the save; start-menu Options screen only (Esc menu per spec §28 has Journal/Map/Save/Quit) — the start menu (built at M7) is where Options lives; greyed reason strings per §32 UX conventions.
- [ ] Tests: round-trip persistence; volume applied at startup; rebind + collision validation; save-slot selection routes `save1.dat` via `options.cfg`; colour-blind toggle golden — **delta defined: ON adds hatch-pattern bar fills** (T8 dotted border + inline numerics stay unconditional). Implement. PASS. Commit `example(undersanded): options menu + persistence`.

### Task 5: `tier_m12_audio.sh`

- [ ] Tier: Tasks 1–4 tests + dsound probe + focus-pause row + `undtool` builds/runs audio-less + all prior goldens unchanged. Non-vacuous. Run PASS. Commit `example(undersanded): M12 audio tier`.

**Gate:** alt-tab pauses and silences; options persist; audio plays with no callback thread.

### Task 6: Next-milestone amendment review (M13)

- [ ] Read `2026-11-12-undersanded-m13-t234-content-plan.md`; judge data schema sufficiency for 56 creatures / 12 zones (journal text keys, encounter rows per zone/phase). Amendment or "no amendment needed" in NOTES.md.
