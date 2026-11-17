# Example Performance Program (z9play CPU, z9gb dynarec, showcase perf) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Z98 showcase examples perform credibly on real Win9x-era hardware — starting with z9play's 49% CPU, the z9gb dynarec fatal fault on real Win98, and the worst per-unit-of-work anti-patterns in z9gb/z9edit/z9torr/z9git.

**Architecture:** Every fix follows the same shape: measure a baseline on the Linux host with the same emitted C89 code shape, remove a per-bit/per-cycle/per-glyph/per-byte loop or a poll loop, then re-measure and re-run that example's tier gates. Two shared root causes dominate: (a) bit-at-a-time readers with one function call + error-union return per bit (z9play Vorbis and FLAC), and (b) per-unit-of-work function calls where one bulk operation exists (per-cycle timer ticks, per-step PPU register pushes, per-pixel PPU passes, per-glyph draws, per-byte copies). The z9gb dynarec fault is a calling-convention/entry-ABI defect between the emitted C dispatcher and the hand-emitted x86 glue/body, not a translation-quality problem.

**Tech Stack:** Z98 (strict Zig subset) emitting C89; OWC `/ox` + `-ffast` is the shipping Win9x build; Linux host gates build `-m32 -std=c89`; per-example `tests/tier_*.sh`.

**Spec:** This plan implements the findings recorded in `examples/z98/z9gb/KNOWN_GAPS.md` (§3, §3.1), `examples/z98/z9play/NOTES.md`, `examples/z98/z9play/demo/win9x_README.txt`, and the audit in this plan's task list. Where a spec doc exists it is the authority: `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`, `docs/superpowers/specs/2026-10-19-z9play-streaming-playback-design.md`.

## Global Constraints

- Z98 subset only (see `docs/sf/AGENTS.md` §1.3): no generics/`anytype`/`@Type`, no `@cImport`, no pointer captures, `switch` requires `else`, no method syntax, strict `i32`/`usize` `@intCast`.
- Edits: use only the `edit` tool or `fastedit` (line-based). **Python/sed bulk transforms are prohibited** (`docs/sf/AGENTS.md` X.3). Re-read before every `fastedit`.
- Do not change compiler emission pins: the 8-pin `--dump-c89` table in `docs/sf/QUICK_REF.md` must not move. Example sources are user code; each example's own recorded dump md5 (in its `NOTES.md`/`README.md`) must be re-baselined in the task that changes it.
- Keep the shipping build profile: `-osw` default (Win9x no-CRT), OWC `/ox`, `-ffast`. No `-fsafe`/`-O0` regressions in the shipping recipe.
- Every example fix keeps runtime behavior byte/bit-identical where a golden exists: z9play PCM (tolerance + RMS LSB + 3× SHA-1 determinism), z9play WAV output, z9gb frame output (headless), z9edit save bytes and screenshots, z9torr/z9git data correctness.
- All build/dump invocations run sequentially from the repo root (`.zig1_*.tmp` CWD collision hazard, QUICK_REF).
- Gates are runtime gates; a compile-only pass is not acceptance (`docs/sf/AGENTS.md` §2.5.3).
- Do not weaken or skip a gate to make a task pass. Missing external ROM/tool = truthful `SKIP`, never `PASS`.

## Review Focus

1. **Bit-reader output drift.** A refactored reader that mis-orders LSB/MSB, mis-handles the `n <= 32` boundary, or drops the accumulator on `brSkip` changes decoded PCM silently. Pinned by each reader task's golden comparison (z9play tolerance/RMS + FLAC exact; 3× determinism).
2. **End-of-stream/truncation semantics.** Vorbis must keep tolerating short packets (past-end reads yield zero bits, `decodeScalar` returns `-1`/single-symbol; `brRead` returns `error.Truncated` before consuming), and FLAC must keep returning `error.Truncated`/`error.BadFrame` with the frame-header CRC-8 recording intact. Pinned per reader task with truncated-packet tests.
3. **Win9x vs host toolchain ABI.** The dynarec call is emitted C calling hand-emitted machine code; Watcom default `__watcall` (register args) vs `Z98_STDCALL` (callee-clean stack args) changes where the `*DynCtx` argument lands and who pops it. Any fix must be verified in the OWC no-CRT build (Wine + operator hardware), not only the mingw build. Pinned by Task 4's Wine OWC reproduction, the `ret $N` evidence, and `tier_dynarec`/`tier_win32`.
4. **z9edit cache invalidation.** The cached line map must stay correct across insert/delete, newline edits, CRLF folding, gap moves, undo, and large pastes; a stale map shows wrong gutter numbers/line text. Pinned by Task 7's differential test vs the naive scan.
5. **Idle-behavior regressions.** z9torr's added sleep must not delay stall detection/timeouts or the `<500 ms` fallback gate; z9edit skipping repaints must not break the smoke-byte or theme-screenshot goldens. Pinned in Tasks 8 and 9.

---

## File Structure

New/modified files (all existing paths except the new plan/test files):

| File | Responsibility |
|---|---|
| `examples/z98/z9play/vorbis_setup.zig` | Vorbis bit reader (`BitReader`, `brInit`, `brRead`, `brSkip`) — word accumulator |
| `examples/z98/z9play/codebook.zig` | `decodeScalar` bit sink — accumulator fast path |
| `examples/z98/z9play/residue.zig` | `decodeScalarEop` bit sink — accumulator fast path |
| `examples/z98/z9play/flac.zig` | FLAC `StreamBitReader` — word accumulator, batched file refill, recording-safe |
| `examples/z98/z9play/platform/audio_win9x.zig` | `waitFree`/`drain` poll interval; bulk buffer copy |
| `examples/z98/z9play/main.zig`, `examples/z98/z9play/ui.zig` | `mixWrite` volume multiply (no per-sample divide) |
| `examples/z98/z9play/player.zig` | `playerRingAppend` bulk copy |
| `examples/z98/z9gb/dynarec/dynarec.zig`, `dynarec/x86.zig`, `dynarec/helpers.zig`, `dynarec/cache.zig` | Dynarec stdcall entry/helper ABI, glue offsets |
| `examples/z98/z9gb/timer.zig` | Batched `timerTick` |
| `examples/z98/z9gb/emu.zig` | Dirty-only `ppuSyncIn` |
| `examples/z98/z9gb/ppu.zig` | Single-pass line render (bg/window write fb directly) |
| `examples/z98/z9edit/buffer.zig` | Cached line-start map + incremental invalidation |
| `examples/z98/z9edit/ui.zig` | Dirty-driven paint, glyph runs, cached status scan |
| `examples/z98/z9edit/main.zig` | Paint-on-dirty loop (present stays each frame) |
| `examples/z98/z9torr/main.zig`, `wire.zig` | Idle sleep, single-pass slot scans, bulk copies |
| `examples/z98/z9git/httpgit.zig`, `packhash.zig` (new), `delta.zig`, `pack.zig` | Batched SHA-1 tail window, bulk copies |
| `examples/z98/z9play/tests/bitreader_test.zig` (new, wired into `tier_setup.sh`), `z9gb/tests/tier_dmg.sh` (inline `timer_test.zig` heredoc), `z9edit/tests/buffer_test.zig` (extended), `z9git/tests/packhash_test.zig` (new, wired into `unit_store.sh`) | Differential/unit tests for the refactors |
| `diagnostic-tier-flac-report.md` (scratch, under `.superpowers/sdd/…`) | per-failure ownership verdict for the z9play tier_flac/tier_tui failures (no source change) |
| `examples/z98/z9play/tests/tier_flac.sh`, `tier_tui.sh` | frame-aware mixed-completion/playlist waits (no program change) |

---

## Phase 0 — Baselines

### Task 0: Measurement harness and baseline table

**Files:**
- Create: `docs/superpowers/plans/2026-11-17-example-performance-baselines.md` (evidence log; tracked)
- Read: `docs/sf/QUICK_REF.md` seed recipe, each example's tier scripts

**Interfaces:**
- Consumes: nothing.
- Produces: the before/after metric table every later task appends to: z9play decode-rate (audio-s per wall-s), z9gb headless fps, z9torr idle CPU %, z9git clone/hash wall time, z9edit frame cost estimate.

- [ ] **Step 1: Build the compiler under test**

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/perf_seed
# gate: script closure line (hop1 == hop2 for a std-only seed)
```

- [ ] **Step 2: z9play baseline** — emit + build Linux, time flat-out decode of both formats:

```bash
mkdir -p /tmp/perf_z9play
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9play examples/z98/z9play/main.zig
sh /tmp/perf_z9play/build_target.sh linux /tmp/perf_z9play/prog
/usr/bin/time -v /tmp/perf_z9play/prog --wav examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/perf_z9play/ogg.wav
# repeat for a FLAC fixture (tests/mkfixtures.sh output or operator ROM sample path)
```

Record: fixture duration, wall seconds, derived decode-rate (audio-s/wall-s).

- [ ] **Step 3: z9gb baseline**

```bash
mkdir -p /tmp/perf_z9gb
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9gb examples/z98/z9gb/main.zig
sh /tmp/perf_z9gb/build_target.sh linux /tmp/perf_z9gb/prog
# headless, unpaced, fixed frame count with a public-domain test ROM from the tier harness
/tmp/perf_z9gb/prog --headless --turbo --no-audio --frames 600 --rom <rom> --fb-out /tmp/perf_z9gb/fb.bin
```

Record: frames/s.

- [ ] **Step 4: z9torr idle CPU + z9git throughput baselines**

```bash
mkdir -p /tmp/perf_z9torr /tmp/perf_z9git
# emit + build both; run z9torr against a local seed for 10 s and sample CPU with `timeout` + `/usr/bin/time -v`
# z9git: sh examples/z98/z9git/tests/profile_small.sh (existing perf harness)
```

Record: z9torr idle CPU% (expected ~100% today) and z9git `profile_small.sh` numbers.

- [ ] **Step 5: z9edit frame-cost estimate (no Linux GUI target)**

Read `ui.zig/uiPaint` and count per-frame work analytically (rows × `bufLineRange` rescans + per-char draw calls); record the count for a 5k-line file. GUI timing is operator-side (Wine smoke later).

- [ ] **Step 6: Commit the baseline log**

```bash
git add docs/superpowers/plans/2026-11-17-example-performance-baselines.md
git commit -m "docs(perf): baseline metrics for example performance program"
```

---

## Phase 1 — z9play (49% CPU)

### Task 1: Vorbis bit-reader word accumulator

**Files:**
- Modify: `examples/z98/z9play/vorbis_setup.zig:152-181` (`BitReader`, `brInit`, `brRead`, `brSkip`)
- Modify: `examples/z98/z9play/codebook.zig:265-284` (`decodeScalar`)
- Modify: `examples/z98/z9play/residue.zig:63-96` (`decodeScalarEop`)
- Test: `examples/z98/z9play/tests/bitreader_test.zig` (new; compile+run wired into `examples/z98/z9play/tests/tier_setup.sh` following the `tier_console.sh:67` pattern)

**Interfaces:**
- Consumes: existing `ogg.OggError`, `BitReader.pos` semantics (bit position, LSB-first reads).
- Produces: `BitReader` gains `acc: u64`, `acc_bits: u32`, `next_byte: usize`; `brInit(data: []const u8) BitReader` unchanged signature; `brRead(br: *BitReader, n: u32) ogg.OggError!u32` unchanged signature/semantics; `brSkip(br: *BitReader, n: u32) ogg.OggError!void` unchanged signature; new `pub fn brBitZero(br: *BitReader) u32` returning the next bit (0/1) and 0 past end **without** advancing `pos` past `nbits`.
- `brSkip` advances `n` bits; `pos` stays authoritative (consumed bits). It MUST NOT re-anchor by clearing `acc` and setting `next_byte = pos >> 3`, because that rewinds up to 7 bits when `pos % 8 != 0`. Correct behavior: discard prefetched accumulator bits and consume the partial byte first (`8 - (pos & 7)` bits, if non-zero), then advance whole bytes; `pos` ends at exactly the requested position.
- Keep the existing `decodeScalar` `used == 1` semantics: consume one bit when available, consume nothing past `nbits` (matches `vs.brRead(bits,1) catch 0`); `brBitZero` implements that same one-bit behavior for the fast path.

- [ ] **Step 1: Write the failing differential test**

`bitreader_test.zig`: for lengths 0..64 and bit counts 1..32, compare `brRead` against a naive bit-by-bit reference; assert `pos` equals total consumed bits; assert past-end returns `error.Truncated` with `pos` unchanged; assert `brSkip` then `brRead` equals naive; assert `brBitZero` past end returns 0 and clamps `pos` at `nbits`. The differential test must include non-byte-aligned `brSkip` values (1, 3, 7, 9, 13) followed by `brRead`, plus `brSkip` past `nbits` returning `Truncated` with `pos` unchanged (`vorbis_setup.zig:180-183` is the current skip).

- [ ] **Step 2: Run it to verify it fails**

Run: `sh examples/z98/z9play/tests/tier_setup.sh`
Expected: FAIL — `brBitZero` undefined (the new test entry does not compile).

- [ ] **Step 3: Implement the accumulator**

Refill from `data` in 8-bit steps into `acc`/`acc_bits` (max 7 bits resident before a 32-bit read); `brRead` shifts `acc` by `n`; `brSkip` discards prefetched accumulator bits, consumes the partial byte first (`8 - (pos & 7)` bits if non-zero), then advances whole bytes and leaves `pos` at exactly the requested bit; do not clear `acc` and re-anchor `next_byte` from `pos` (that rewinds up to 7 bits when `pos % 8 != 0`). `brBitZero` consumes from `acc`, refilling one byte at a time. Keep the bounds check `br.pos + n > br.nbits → error.Truncated` before any consumption.

- [ ] **Step 4: Switch the codebook hot path**

`decodeScalar` and `decodeScalarEop` use `brBitZero` for their one-bit tree walks (no error-union return per bit).

- [ ] **Step 5: Verify**

Run: `sh examples/z98/z9play/tests/tier_setup.sh` (new bitreader entry passes), then `sh examples/z98/z9play/tests/tier_decode.sh`, `tier_math.sh`, `tier_info.sh`.
Expected: PASS; PCM tolerance + 3× determinism unchanged.

- [ ] **Step 6: Commit**

```bash
git add examples/z98/z9play/vorbis_setup.zig examples/z98/z9play/codebook.zig examples/z98/z9play/residue.zig examples/z98/z9play/tests/bitreader_test.zig examples/z98/z9play/tests/tier_setup.sh
git commit -m "perf(z9play): word-accumulator Vorbis bit reader"
```

### Task 2: FLAC bit-reader word accumulator

**Files:**
- Modify: `examples/z98/z9play/flac.zig:660-760` (`StreamBitReader`, `sLoadByte`, `sReadBit`, `sReadBits`, `sReadSigned`, `sReadUnary`, `sAlignByte`)
- Test: extend `examples/z98/z9play/tests/flac_test.zig` (existing) with a truncated-frame + recording + prefetch multi-frame test

**Interfaces:**
- Consumes: `stream.bufferedFileRead(bf, out) StreamError!usize`, `bufferedFileReadByte` semantics.
- Produces: this reader is **MSB-first** (`sReadBit` uses `7 - bit_pos`; `sReadBits` builds `v = (v << 1) | bit` in `flac.zig:691-702`). The accumulator must preserve MSB-first order; do not copy the Vorbis LSB-first design. `StreamBitReader` gains `acc: u64`, `acc_bits: u32`; the existing `cur`/`bit_pos` fields are removed or kept only for the recording/provenance path; `sReadBit/sReadBits/sReadSigned/sReadUnary/sAlignByte` signatures unchanged.
- Produces: record bytes **as they are consumed while recording** (keep provenance for prefetched bytes; append the consumed byte to `hdr`), or otherwise guarantee the accumulator is empty at frame start. Current `sLoadByte` records at *load* (`flac.zig:679-682`) and `recording` is enabled per frame (`:956-957`); CRC-8 is computed over `hdr[0..hdr_len]` (`:1067-1069`). With prefetch, header bytes of the next frame can already be in the accumulator when `recording` turns on, so load-time recording loses them. Prefetching must never put next-frame payload bytes into `hdr`.
- Produces: `sAlignByte` consumes to the next byte boundary (discard `acc_bits & 7`). Prefetch must tolerate a short read at EOF (`bufferedFileRead` returns a short count; do not report `Truncated` while the bits actually needed are present).

- [ ] **Step 1: Write the failing test** — a bit-stream differential test over a fixed byte array: `sReadBits`/`sReadSigned`/`sReadUnary` vs the current per-bit reference; a truncated stream returns `error.Truncated` at the same bit; with `recording = true` the captured `hdr` bytes/`hdr_len` equal the byte-by-byte path for a header-length read. Add a multi-frame test with prefetch enabled — frame 1 followed by frame 2 must keep frame 2's header CRC-8 exact (the existing `tests/flac_test.zig` + `tier_flac.sh` must stay green).

- [ ] **Step 2: Run it — expect FAIL** (recording path not yet split).

- [ ] **Step 3: Implement** — prefetch 8 bytes via `bufferedFileRead` into `acc` when `!recording`; while `recording`, append each byte to `hdr` at consumption time (not at load time), preserving prefetched-byte provenance, and never append next-frame payload bytes. `sReadUnary` counts zero bits in `acc` word-wise (refilling between words) with the same `q > 0x00ffffff → error.BadFrame` cap. `sAlignByte` discards `acc_bits & 7` and realigns.

- [ ] **Step 4: Verify** — `sh examples/z98/z9play/tests/tier_flac.sh` (58/0: the current check inventory after `38a18deb` removed the pinned rotating-seed md5 check; lossless exact PCM, 3× deterministic), `tier_decode.sh`; the multi-frame prefetch test keeps frame 2's header CRC-8 exact.

- [ ] **Step 5: Commit**

```bash
git add examples/z98/z9play/flac.zig examples/z98/z9play/tests/flac_test.zig
git commit -m "perf(z9play): word-accumulator FLAC bit reader"
```

---
### Task 12: Diagnostic — z9play `tier_flac`/`tier_tui` failures (investigation only)

> **Execution note (operator ruling 2026-11-17):** run this task immediately after Task 2 and before Task 3. Verdicts only — no fixes, no gate changes, no commits. Implementation tasks wait for the operator's ruling on the report.

**Files:**
- Read: `examples/z98/z9play/tests/tier_flac.sh`, `tier_tui.sh`, `tier_decode.sh`, `tests/flac_test.zig`, `main.zig`, `ui.zig`, and the emitted C for the failing paths
- Create (scratch, **not committed**): `.superpowers/sdd/2026-11-17-example-performance-program/diagnostic-tier-flac-report.md`
- Modify: none

**Interfaces:**
- Consumes: Task 2 report (`task-2-report.md`), the recorded baseline result at `c6028b11` (`tier_flac` 55/3 with the same three failures), HEAD `abafb620`.
- Produces: one ownership verdict per failure — compiler defect (minimal repro), tier/harness defect (exact line), example defect (exact line), or environment flake — with reproducible command evidence and candidate fix scopes. No code change.

- [ ] **Step 1: Reproduce at HEAD.** With `/tmp/perf_seed/zig1_5_clean`, run `sh examples/z98/z9play/tests/tier_flac.sh`; capture the three failing check names and their assertion output. Run `sh examples/z98/z9play/tests/tier_tui.sh` standalone 3 times; capture each failing case name and repeat pattern (`playlist-add-status`, `playlist-add-no-stale-zero` are the reported flakes).
- [ ] **Step 2: Baseline parity.** In a detached worktree (do not disturb the main worktree), check out `c6028b11`, build with the same compiler, and run the same checks. Confirm identical failures or characterize any difference.
- [ ] **Step 3: Isolate each failure.** Read the tier scripts and run the smallest command each failing check runs. Record exit codes, stdout/stderr, fixtures used, temp paths, ports and timing. Repeat 3-5 times to separate deterministic defects from flakes.
- [ ] **Step 4: `mixed TUI OGG payload out of bound (max_delta=999999 rms_milli=999999)`.** Determine how the payload is produced and compared (fixture, WAV, TUI mode, file reuse), whether the comparison reads a stale/wrong file, and whether the `999999` sentinel means the comparison never ran. State exactly which line produces it.
- [ ] **Step 5: `mixed-ogg-wav-complete`.** Identify the exact completion assertion and the input/order that triggers it; run it in isolation.
- [ ] **Step 6: `tier_tui` 38/1.** Identify the failing case per run and whether it is a race/timeout/port/temp-file issue or a real behavior bug; report repeat counts.
- [ ] **Step 7: Verdicts.** For each failure: owner (compiler / tier / example / environment), file:line evidence, and the candidate fix scope, risk and cost. If compiler is suspected, include a minimal repro (command, rc, emitted C excerpt, expected vs actual).
- [ ] **Step 8: STOP.** Write the report to the scratch path above and return; do not implement any fix and do not commit.
---
### Task 13: Fix z9play tier-harness framing races (tier fixes only)

> **Why:** Task 12 proved the `tier_flac` 55/3 and `tier_tui` 38/1 failures are pty frame-timing defects in the tier drivers, identical at baseline `c6028b11`; FLAC/OGG/UI behavior is correct. This task makes the gates honest; it does not change the program.

**Files:**
- Modify: `examples/z98/z9play/tests/tier_flac.sh` (`mixed` driver heredoc)
- Modify: `examples/z98/z9play/tests/tier_tui.sh` (playlist-add checks)
- Read: `diagnostic-tier-flac-report.md` (`task-12` report path)

**Interfaces:**
- Consumes: Task 12's evidence: `tier_flac.sh:450-471` (stale pre-Enter `State: Ended` after the play mark), `tier_flac.sh:174-181,530-547` (empty-payload `999999` sentinel), `tier_tui.sh:330-334` plus `:204-210` (non-frame-aware `wait_bytes`).
- Produces: same checks and thresholds, frame-aware waits; `tier_flac.sh` 58/0 (current inventory; `38a18deb` removed the pinned rotating-seed md5 check) and `tier_tui.sh` 39/0 on repeated runs. No app, compiler, std, plan, or fixture changes.

- [ ] **Step 1: Read the Task 12 report.** Confirm the exact failing offsets/checks before editing.
- [ ] **Step 2: Fix `tier_flac.sh` mixed completion.** After the `b.ogg` play marker, wait for a *new* `State: Ended` occurrence (compare occurrence counts vs at-mark), or poll the WAV sink until `44 + OGG_DATA` before asserting, copying, and sending `q`. Replace the stale-text match; do not delete `mixed-ogg-ended`, `mixed-ogg-wav-complete`, or the bound checks.
- [ ] **Step 3: Fix the empty-payload sentinel.** In the payload comparator (`tier_flac.sh:174-181`), treat `n == 0` as an explicit empty/stale-payload failure with a descriptive line; keep the numeric tolerance path and `MAX_DELTA_BOUND`/`RMS_MILLI_BOUND` unchanged.
- [ ] **Step 4: Fix `tier_tui.sh` add checks (`:330-334`).** Set `add_mark` at a frame boundary (e.g. drain a short quiet period before pressing `a`), wait for `added to playlist` with `wait_bytes(..., add_mark)`, and replace `b"Playlist: 0" not in buf[add_mark:]` with an assertion on the last complete post-add frame's `Playlist:` value. Keep `playlist-add-counts-one` and all other checks.
- [ ] **Step 5: Verify.** Run `tier_tui.sh` 5× expecting 39/0; run `tier_flac.sh` 3× expecting 58/0 (all FLAC checks still exact); run `tier_decode.sh` once expecting 25/0. Record every run in the report.
- [ ] **Step 6: Commit** only the two tier scripts:
```bash
git add examples/z98/z9play/tests/tier_flac.sh examples/z98/z9play/tests/tier_tui.sh
git commit -m "test(z9play): fix tier_flac/tier_tui pty framing races"
```

---

### Task 3: z9play audio wait + copy/mix micro-fixes

**Files:**
- Modify: `examples/z98/z9play/platform/audio_win9x.zig:128-137,261` (poll interval), `:232-245` (bulk copy)
- Modify: `examples/z98/z9play/player.zig:287-298` (`playerRingAppend` bulk copy)
- Modify: `examples/z98/z9play/main.zig:158-165`, `ui.zig:393-405` (`mixWrite`)
- Test: `examples/z98/z9play/tests/audio_test.zig`, `tier_audio.sh`, `tier_win9x.sh`

**Interfaces:**
- Consumes: `std_mem.copyU8(dst: [*]u8, src: [*]const u8, n: usize)` (`sf/src/std_mem.zig:1`), `@memcpy` if supported by the seed (check; otherwise `copyU8`).
- Produces: `waitFree`/`drain` poll `sleepMs(10)`; `mixWrite` uses a precomputed scale (`s * vol * 32768 / 100` → shift) with no per-sample division.

- [ ] **Step 1: Baseline check** — `tier_audio.sh` + `tier_win9x.sh` PASS before edits.
- [ ] **Step 2: Apply poll interval change** — 1 ms → 10 ms in `waitFree` and `drain` (500 ms buffers tolerate it).
- [ ] **Step 3: Apply bulk copies** — `copyU8` in the win9x `write` inner loop, `playerRingAppend` (handle the wrap by two bulk copies), and the mix buffer.
- [ ] **Step 4: Apply mix scale** — precompute `g_mix_mul: i32 = vol * 32768 / 100` in the volume handler; apply `@intCast(i16, (s * g_mix_mul) >> 15)`; clamp only if the existing behavior clamps.
- [ ] **Step 5: Verify** — `tier_audio.sh`, `tier_win9x.sh`, `tier_cli.sh`, `tier_tui.sh`; WAV byte parity under Wine.
- [ ] **Step 6: Re-measure z9play decode rate, append to baseline log, commit.**

---

## Phase 2 — z9gb dynarec fatal (Win9x)

### Task 4: Root-cause and fix the dynarec Win9x fault

**Files:**
- Modify: `examples/z98/z9gb/dynarec/dynarec.zig` (dispatcher call, glue entry/exit), `examples/z98/z9gb/dynarec/x86.zig` (body epilogue, helper-call cleanup), `examples/z98/z9gb/dynarec/helpers.zig` (helper ABI), `examples/z98/z9gb/dynarec/cache.zig` (allocation/protection if implicated)
- Modify: `examples/z98/z9gb/KNOWN_GAPS.md` (§3.1 → root cause + status)
- Test: `examples/z98/z9gb/tests/tier_dynarec.sh`, `tier_win32.sh`, `tier_dmg.sh`, `tier_cgb.sh`, Wine OWC run

**Interfaces:**
- Consumes: fault evidence `EIP=011c0004`, `EAX=0`, faulting bytes `8b 10 8b 48 04` (`mov (%eax),%edx; mov 0x4(%eax),%ecx`), `KNOWN_GAPS.md:111-159`.
- Produces: machine-callable helper entries with the Win32 stack convention: `pub extern "stdcall" fn helperRead8(ctx: *DynCtx, addr: u16) u8`, `pub extern "stdcall" fn helperWrite8(ctx: *DynCtx, addr: u16, value: u8) void`, `pub extern "stdcall" fn helperIoRead(ctx: *DynCtx, addr: u16) u8`, `pub extern "stdcall" fn helperIoWrite(ctx: *DynCtx, addr: u16, value: u8) void`, `pub extern "stdcall" fn helperSync(ctx: *DynCtx) void`. Support exists today: `repro/mi_matrix/known_excluded/stdcall_def_ok/main.zig:12`, `sibling_fnptr.zig:5`; `dynarec/cache.zig:23-26` already uses `extern "stdcall"` Win32 APIs.
- Produces: `examples/z98/z9gb/dynarec/dynarec.zig`: `const GlueFn = extern "stdcall" fn (*DynCtx) u32;` and `@ptrCast(GlueFn, d.mem + @intCast(usize, e.glue_off))` replacing the bare `fn (*DynCtx) u32` cast (`dynarec.zig:554`).
- Produces: a documented stdcall entry-ABI contract: dispatcher calls glue at `glue_off` with the `*DynCtx` argument on the stack; chained entries jump to `glue_off + GLUE_BODY_OFF` with the same frame; block bodies receive ctx where they read it.

**Root cause (established):** the emitted C type for the dispatcher/glue call is plain (`typedef unsigned int (*...)(DynCtx*)`, no convention attribute; `QUICK_REF.md:253`: `"cdecl"` is byte-identical to bare = no annotation). OpenWatcom `wcc386` defaults to `__watcall` (register args), so the glue's stack read `push [esp+0xC]` (`buildGlue`, `dynarec.zig:114-121`) yields 0; the body prologue (`x86.zig:1470-1479`) then faults at body+4 (`8b 10 8b 48 04`, EAX=0 = `KNOWN_GAPS.md` §3.1). Mingw/gcc default cdecl, which is why the host passes. Helpers (`helpers.zig` header says cdecl) are plain too, so the helper ABI must change as well — entry-only fixes are insufficient.

**Machine-code ABI, Win32 only (`@isWindows()`)**, because stdcall is callee-clean:
- body epilogue (`x86.zig:1560`) `C3` → `C2 04 00` (`ret 4`);
- glue exit (`dynarec.zig:240-245`) `C3` → `ret 4`;
- remove the `83 C4 04` cleanup after the internal body call in `buildGlue`;
- remove the helper-call cleanups (`add esp,4/8/0xC`) at `x86.zig:544-578` and `emitChargeResidual` (`x86.zig:1507-1519`);
- Linux keeps today's cdecl sequence (plain `ret`, `add esp`) because `Z98_STDCALL` is empty non-Windows.
- Argument layout unchanged: args stay at `[esp+4]`; keep `mov 4(%esp),%eax` and glue's `push [esp+0xC]`.

- [ ] **Step 1: Reproduce under Wine with the OWC no-CRT build** and capture EIP/registers; confirm it matches `KNOWN_GAPS` §3.1.

- [ ] **Step 2: Disassemble the OWC-built `helperRead8` and the OWC dispatcher call site** — prove callee-clean (`ret $N`) vs caller-clean/register args; record the evidence in the task/report.

- [ ] **Step 3: Implement the stdcall changes** — helper signatures, `GlueFn`, and the Win32-only machine-code epilogue/cleanup edits above.

- [ ] **Step 4: Verify `objdump` shows `ret $N` for an OWC helper.**

- [ ] **Step 5: Run a ROM under Wine with `--dynarec` (OWC exe) without fault.**

- [ ] **Step 6: Mingw build parity** + `tier_dynarec.sh` + `tier_win32.sh` + `tier_dmg.sh`/`tier_cgb.sh`.

- [ ] **Step 7: Operator real-Win98 run.**

- [ ] **Step 8: Update `KNOWN_GAPS.md` §3.1** with root cause and status; commit the ABI fix and the gap update.

- **Fallback (keep):** if the OWC check disproves the workaround, fail closed on Win9x (dynarec disabled with an explicit diagnostic, interpreter default) and document it — do not ship a crashing dynarec.

- **Notes:** D22 (bare/cdecl fn types are not cdecl on OpenWatcom) is a deferred doc-only defect; the stdcall workaround is this plan's deliverable. Do not edit the defects file here.

---

## Phase 3 — z9gb interpreter performance

### Task 5: Batched timer advance

**Files:**
- Modify: `examples/z98/z9gb/timer.zig:29-48` (`timerTick`)
- Test: extend the inline `timer_test.zig` heredoc in `examples/z98/z9gb/tests/tier_dmg.sh:399` (the existing timer-gate builder)

**Interfaces:**
- Consumes: `Timer { divider: u16, tima: u8, tma: u8, tac: u8, reload: u8 }`, `selectedMask(tac) u16`, `bumpTima(t)`, `mmumod.busRaiseIrq(bus, 0x04)`.
- Produces: `timerTick(t: *Timer, cycles: u32, bus: *mmumod.Bus) void` with identical observable state to the per-cycle loop for any `cycles`.

- [ ] **Step 1: Write the failing differential test** — inside the `tier_dmg.sh:399` `timer_test.zig` heredoc add a `naiveTimerTick` reference copy of the current per-cycle loop and compare it against `timerTick` over random `(divider, tima, tma, tac, reload, cycles)` sequences (divider + TIMA + irq counter).

- [ ] **Step 2: Implement** — advance in chunks bounded by the next TIMA increment (period `2^(k+1)` for mask bit `k`) and by `reload` remaining; preserve the `reload`/overflow IRQ ordering exactly.

- [ ] **Step 3: Verify** — differential test 3×, `tier_dmg.sh`, `tier_cgb.sh`, `tier_audio.sh` (`dmg_sound`).

- [ ] **Step 4: Re-measure z9gb headless fps; commit.**

### Task 6: Dirty-only PPU sync + single-pass line render

**Files:**
- Modify: `examples/z98/z9gb/emu.zig:215-237` (`ppuSyncIn`/`ppuSyncOut`)
- Modify: `examples/z98/z9gb/ppu.zig:406-423` (`renderBackground` writes `fb` directly), `:560-583` (`renderLine` no second pass)
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`, `tier_cgb.sh`, headless framebuffer goldens

**Interfaces:**
- Consumes: `bus.io[0x40..0x4B]`, `bus.lyc_dirty`, `ppuWrite`/`ppuRead`, `p.bg_lut`/`bus.cram_rgb`.
- Produces: `Emu` gains `ppu_io_shadow: [11]u8` + `ppu_shadow_valid: bool`; `ppuSyncIn` pushes only changed registers (plus always-fresh LCDC/STAT if the PPU requires it — decide from `ppuWrite` semantics); `renderBackground`/`renderWindow` write `fb[line*SCREEN_W + x]` directly and keep `shades[b]` only for sprite priority.

- [ ] **Step 1: Baseline** — headless frame goldens + fps from Phase 0.
- [ ] **Step 2: Implement dirty sync** — shadow compare per step; `lyc_dirty` path kept.
- [ ] **Step 3: Implement single-pass render** — fold the LUT conversion into the bg/window loops; keep the CGB palette/priority arrays for `renderSprites`.
- [ ] **Step 4: Verify** — `tier_dmg.sh`, `tier_cgb.sh`, `tier_audio.sh`, headless golden bytes identical, fps re-measured.
- [ ] **Step 5: Commit.**

---

## Phase 4 — z9edit

### Task 7: Cached line-start map

**Files:**
- Modify: `examples/z98/z9edit/buffer.zig:33-46` (`BufState` gains `edit_gen`), `:150-172` (`lineCountOf`/`lineStartOf`), `:187-215` (`bufLoad` bump), `:350-410` (`bufInsert`/`bufDelete` bump, `bufCopy` bulk), `:415-435` (`bufLineRange`)
- Modify: `examples/z98/z9edit/ui.zig:860,894,904` (use cached accessors)
- Test: extend `examples/z98/z9edit/tests/buffer_test.zig` (existing, run by `tier_edit.sh`) with the cached-vs-naive differential test

**Interfaces:**
- Consumes: `BufState { arena, buf, cap, gap_start, gap_end, len, uses_crlf, dirty }`, `bufByteAtState`, `MAX_BUF = 16 MiB`. `BufState` has only `dirty` (the unsaved-changes flag, `buffer.zig:36`) — no serial exists.
- Produces: `BufState` gains `edit_gen: u64`, bumped on every content mutation (insert, delete, load, and any undo/restore path), exposed as `pub fn bufEditGen(b: *GapBuffer) u64`; the line map is keyed by `edit_gen`. Public cached accessors: `pub fn bufLineCountCached(b: *GapBuffer) usize`, `pub fn bufLineStartCached(b: *GapBuffer, line: usize) usize`, `pub fn bufLineRangeCached(b: *GapBuffer, line: usize, start: *usize, len: *usize) void`; internal `LineMap { starts: [*]u32, count: usize, edit_gen: u64, valid: bool }` with `MAX_LINE_CACHE: usize = 131072` and fallback to the naive scan when the file has more lines.

- [ ] **Step 1: Write the failing differential test** — in `tests/buffer_test.zig`: random edit scripts (insert/delete, newlines, CRLF input, undo, load) applied to a buffer; assert cached count/starts/range equal the naive functions after every edit, and assert the generation increases on each mutation.
- [ ] **Step 2: Implement** — add `edit_gen` and bump it on every mutation (`bufLoad`, `bufInsert`, `bufDelete`, and the undo path, which mutates through those functions); build the map lazily on first use when `edit_gen` differs from the cached key; on insert/delete of a newline adjust count and shift starts after the edit point by the gap delta (`O(lines)`, not `O(bytes)`); `bufCopy` uses `copyU8`.
- [ ] **Step 3: Verify** — differential test 3×, `tier_edit.sh`, `tier_edit_gui.sh` (save bytes + screenshots unchanged).
- [ ] **Step 4: Commit.**

### Task 8: Dirty-driven paint, glyph runs, cached status scan

**Files:**
- Modify: `examples/z98/z9edit/ui.zig:750-775` (`paintTokens` runs), `:805-822` (`paintStatus` cached unbalance), `:840-916` (`uiPaint` dirty gate), `:845-847` (time-based ident rebuild), `uiStep` (set dirty on edits/keys/scroll/resize/theme/time-based ident rebuild)
- Modify: `examples/z98/z9edit/main.zig:227-234` (`paintFrame`: begin → conditional `uiPaint` → end), `:424-456` (`loop`: present when clean)
- Test: `tier_edit_gui.sh` (2× save-byte golden, three theme screenshots, F2 cycle, bad-config, idle repaint)

**Interfaces:**
- Consumes: `gfx.gfxDrawText(g, x, row, text, fg, bg)` accepts a slice; `UiState` gains `dirty: bool` (initial true) plus a cached-unbalance key `{ ub_gen: u64, ub_valid: bool, ub_ch, ub_line }`.
- Produces: `paintTokens` groups consecutive same-`(fg,bg)` cells into runs and draws each run once; `paintStatus` reuses the cached unbalanced result keyed by the buffer edit generation (`ub_gen`/`ub_valid`); `uiStep` sets `st.dirty = true` on every mutation, on scroll/resize, on theme/F2 changes, **and on the time-based ident rebuild** — `uiPaint` rebuilds declared identifiers when `now - last_edit_ms >= IDLE_MS` (`ui.zig:845-847`; state `ui.zig:61-62,193-194`), which is a visual change the dirty gate would otherwise freeze. The present path is `gfxBeginFrame → (uiPaint if dirty) → gfxEndFrame`; when clean, skip `uiPaint` but still present (begin+end, or an explicit present if available), and keep the dirty=true first frame so GPU smoke still sees frames.

- [ ] **Step 1: Baseline** — screenshot means/colors + save bytes from `tier_edit_gui.sh`.
- [ ] **Step 2: Implement runs + cached scan.**
- [ ] **Step 3: Implement the dirty gate** — full `uiPaint` only when dirty; on idle, present the existing back buffer. `uiPaint`'s 2 s ident rebuild must mark the frame dirty so the resulting visual change repaints.
- [ ] **Step 4: Verify** — `tier_edit_gui.sh` all screenshots/save bytes identical; `tier_edit.sh`; add an idle check that the 2 s ident rebuild produces a repaint.
- [ ] **Step 5: Commit.**

---

## Phase 5 — z9torr + z9git

### Task 9: z9torr idle sleep, single-pass scans, bulk copy

**Files:**
- Modify: `examples/z98/z9torr/main.zig:544-676` (pump loop)
- Modify: `examples/z98/z9torr/wire.zig:624-633` (bulk copy into scratch)
- Test: `tier1.sh`, `tier2.sh`, `tier3_encrypted.sh`, `tier4_wine.sh`, `tier_stall.sh`, `tier_fallback.sh`, `tier_safe.sh`

**Interfaces:**
- Consumes: `std.async.tick(&sched)`, `std.time.sleepMs`, `std_mem.copyU8`.
- Produces: pump loop sleeps `sleepMs(1)` when no task made progress in the iteration; the four `O(peers)` scans (retire/spawn/progress-sum/liveness) collapse into one pass that computes `progressed`, `live`, `dnow`; `wire.writeExtendedEnc` copies `payload[off..off+n]` with `copyU8`.

- [ ] **Step 1: Baseline** — idle CPU ~100%; record `tier_stall` timing.
- [ ] **Step 2: Implement** the single pass + `sleepMs(1)` at iteration end when `!progressed`.
- [ ] **Step 3: Implement** the bulk copy.
- [ ] **Step 4: Verify** — all listed tiers; `tier_stall` still <500 ms; idle CPU re-measured.
- [ ] **Step 5: Commit.**

### Task 10: z9git batched SHA-1 tail window + bulk copies

**Files:**
- Create: `examples/z98/z9git/packhash.zig` (pure, dependency-free hash-feed helper)
- Modify: `examples/z98/z9git/httpgit.zig:859-891` (`packWriteBytes`), `:1786-1790` (`packVerify` flush contract)
- Modify: `examples/z98/z9git/delta.zig:100-127`, `examples/z98/z9git/pack.zig:489-507`
- Test: `examples/z98/z9git/tests/packhash_test.zig` (new; compile+run wired into `examples/z98/z9git/tests/unit_store.sh` following its `store_test.zig` build lines 37-38)

**Interfaces:**
- Consumes: `crypto.sha1Update(&h, data: []const u8)`, `crypto.sha1Final`, the 20-byte git pack trailer rule (`hold_len == 20` at finalize excludes the trailer).
- Produces: `packhash.zig` exposes `pub const PackHash = struct { hasher: crypto.Sha1, pending: [4096]u8, pending_len: usize, tail: [20]u8, tail_len: usize, tail_pos: usize };`, `pub fn packHashInit() PackHash`, `pub fn packHashFeed(ph: *PackHash, data: []const u8) void` (hashes all but the final 20 bytes of the stream seen so far, in order), `pub fn packHashFinal(ph: *PackHash, digest: *[20]u8) bool` (false unless exactly 20 trailer bytes remain). `PackSink` (`httpgit.zig`) replaces `hold`/`hold_len`/`hold_pos` with a `PackHash`.

- [ ] **Step 1: Write the failing test** — `packhash_test.zig`: feed synthetic streams (lengths 0, 1, 19, 20, 21, 4095, 4096, 4097, 100000; odd chunk sizes) through `packHashFeed`; assert `packHashFinal` digest == `SHA1(stream[0..len-20])` and returns true only when exactly 20 bytes remain (false when fewer).
- [ ] **Step 2: Implement `packhash.zig`** — keep a 20-byte trailer window; move displaced bytes into `pending` and call `sha1Update` with `pending[0..pending_len]` when full (and once at `packHashFinal`); never hash a byte until it is >20 bytes from the current stream end. Then wire `httpgit.zig` `PackSink` to it and make `packVerify` call `packHashFinal`.
- [ ] **Step 3: Implement** `copyU8` in delta/pack window copies.
- [ ] **Step 4: Verify** — `sh examples/z98/z9git/tests/unit_store.sh` (new packhash entry), `sh examples/z98/z9git/tests/tier_git.sh`, `sh examples/z98/z9git/tests/profile_small.sh` before/after.
- [ ] **Step 5: Commit.**

---

## Phase 6 — Closeout

### Task 11: Verification sweep + evidence log

**Files:**
- Modify: `docs/superpowers/plans/2026-11-17-example-performance-baselines.md` (after column)
- Modify: each changed example's `NOTES.md`/`README.md` recorded `--dump-c89` md5 (re-baseline only that example's own value) and `KNOWN_GAPS.md` status

- [ ] **Step 1: Full tier sweep, sequential:**

```bash
ZIG=/tmp/perf_seed/zig1_5_clean
for t in examples/z98/z9play/tests/tier_{math,setup,info,decode,stream,audio,flac,cli,console,tui,win9x}.sh; do sh "$t"; done
for t in examples/z98/z9gb/tests/tier_{smoke,dmg,cgb,audio,dynarec,win32,perf}.sh; do sh "$t"; done
sh examples/z98/z9edit/tests/tier_edit.sh; sh examples/z98/z9edit/tests/tier_edit_gui.sh
for t in examples/z98/z9torr/tests/tier{1,2,3_encrypted,4_wine,stall,fallback,safe}.sh; do sh "$t"; done
sh examples/z98/z9git/tests/tier_git.sh; sh examples/z98/z9git/tests/unit_store.sh
```

- [ ] **Step 2: Re-measure Phase 0 metrics and write the after column.** Expected: z9play decode-rate ≥3× baseline; z9gb headless fps well past 59; z9torr idle CPU ≪100%; z9git clone time down; z9edit frame work down by ~rows×.
- [ ] **Step 3: Operator hardware verification** (not automatable): P4/Win98 — z9play CPU meter (target ≪20%), z9gb `--dynarec` boots a ROM without fault, z9edit typing/scrolling responsiveness, z9torr idle CPU.
- [ ] **Step 4: Commit closeout docs.**

---

## Notes / Open Decisions

- **Ordering:** z9play (Task 1-3) → z9gb dynarec (Task 4) → z9gb perf (5-6) → z9edit (7-8) → z9torr/z9git (9-10). Adjust only if the operator rules differently.
- Task 12 (diagnostic) runs after Task 2; Task 3+ are blocked until the operator rules on its report. It is investigation-only and commits nothing.
- Task 13 (tier-harness fix) runs after Task 12 and before Task 3; it unblocks Task 2's `tier_flac` green gate evidence (58/0 current inventory). Tier scripts only.
- **Not in scope:** compiler/emitter codegen changes (e.g. automatic slice→`memcpy` lowering) — that would move `--dump-c89` pins. `std_mem.copyU8` already exists; the example tasks adopt it.
- **z9gb perf depth:** top-3 structural wins only (timer batching, dirty PPU sync, single-pass line render). KNOWN_GAPS §3.2 future work (dynarec block lengthening, negative cache, PPU-read block enders) stays out.
- **z9gb dynarec fallback:** if Task 4 cannot establish a safe fix within this program, the acceptable closeout is fail-closed dynarec on Win9x with a clear diagnostic and the interpreter as the default — documented in KNOWN_GAPS, with a follow-up defect for the ABI fix.
