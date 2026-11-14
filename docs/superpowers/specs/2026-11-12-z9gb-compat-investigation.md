# z9gb commercial-ROM compatibility investigation (Task 8-I)

Status: **DONE / STOP for operator approval** — investigation only. No product source,
test, gate, seed, or plan changes were made. No ROM bytes were copied into the repo.

- Repo: `/workspace/znineeight`, branch `zig1_improvements`, HEAD `3b2e85f7`
- Binary under test: `lin_bin/z9gb_o2.exe` (−O2) under Wine 8.0
- Scratch artifacts: `/tmp/z9gb_compat/`
- Report copies: this file and
  `.superpowers/sdd/2026-11-10-phase4-p5-dynarec-plan/task-8-i-report.md`

## 1. Reproduction matrix

Commands were run from `/workspace/znineeight/lin_bin` as
`wine ./z9gb_o2.exe --headless --turbo --frames N --rom ROM [--cgb] [--dynarec] --fb-out FILE`.
`--frames` defaults to 1 (`main.zig:7,270`), so every run explicitly sets it.

| ROM / mode | frames | engine | rc | trap | framebuffer |
|---|---:|---|---:|---|---|
| `p_cry.gbc --cgb` | 120 | interp | 0 | no | uniform white `0x00FFFFFF` (1 unique pixel value) |
| `p_cry.gbc --cgb` | 1200 | interp | 0 | no | uniform white `0x00FFFFFF` |
| `p_cry.gbc --cgb` | 120 | dynarec | 0 | no | uniform white `0x00FFFFFF` |
| `p_cry.gbc --cgb` | 1200 | dynarec | 0 | no | uniform white `0x00FFFFFF` |
| `p_pin.gbc --cgb` | 120 | interp | 0 | no | uniform white `0x00FFFFFF` |
| `p_pin.gbc --cgb` | 1200 | interp | 0 | no | uniform white `0x00FFFFFF` |
| `p_pin.gbc --cgb` | 120 | dynarec | 3 | **yes, `int3`** | not written (process died) |
| `p_pin.gbc --cgb` | 1200 | dynarec | 3 | **yes, `int3`** | not written |
| `p_pin.gbc` (DMG) | 120 | interp | 0 | no | uniform green `0x009BBC0F` |
| `p_pin.gbc` (DMG) | 1200 | interp | 0 | no | uniform green `0x009BBC0F` |
| `p_pin.gbc` (DMG) | 120 | dynarec | 3 | **yes, `int3`** | not written |
| `p_pin.gbc` (DMG) | 1200 | dynarec | 3 | **yes, `int3`** | not written |
| `k_dl.gb` | 120 | interp | 0 | no | uniform green `0x009BBC0F` |
| `k_dl.gb` | 1200 | interp | 0 | no | uniform green `0x009BBC0F` |
| `k_dl.gb` | 120 | dynarec | 0 | no | uniform green `0x009BBC0F` |
| `k_dl.gb` | 1200 | dynarec | 0 | no | uniform green `0x009BBC0F` |
| `k_tt.gbc --cgb` | 1 | interp | 2 | no | loader reject: `z9gb: cannot read ROM` |

The dynarec Pinball trap is **not** an immediate startup failure. `--frames 1..10`
exits 0; `--frames 12` and above trap. The trap occurs during translation of a block
that is first reached around frame 11.

## 2. Root cause #1 — VBlank interrupt request (IF bit 0) is never raised

**Severity: critical. This is the white/green-screen root cause.**

### 2.1 Instrumented probe

A /tmp-only copy of `examples/z98/z9gb` was instrumented with:

- a 256-entry page histogram `hist[pc >> 8]`,
- a 65536-entry exact-PC histogram (accepted once the bad `[_]u32{0} ** 65536`
  initializer was replaced with an explicit zeroing loop),
- a 64-entry ring of the most recent executed PCs,
- per-IO-register read counts plus a 64-entry IO-read ring `(pc, addr, value)`,
- per-vector interrupt service counters.

Build recipe (no repo files touched):

```
cp -a examples/z98/z9gb /tmp/z9gb_compat/probe
cd /tmp/z9gb_compat/probe
/tmp/z9gb_p2_seed/zig1_5_clean -o out probe.zig -I /workspace/znineeight/sf/src
sh out/build_target.sh linux prog
./out/prog
```

The probe ran each ROM for 300 frames (interpreter).

### 2.2 Observed wait loops and awaited conditions

**Pokemon Crystal (`p_cry.gbc --cgb`), main-thread loop at `0x045A..0x0467`:**

```
045A  3E 01        LD   A,$01
045C  EA B3 CF     LD   ($CFB3),A     ; set "please VBlank" flag
045F  76           HALT
0460  00           NOP              ; wake-up PC after HALT
0461  FA B3 CF     LD   A,($CFB3)
0464  A7           AND  A
0465  20 F8        JR   NZ,$045F     ; repeat until ($CFB3)==0
0467  C9           RET
```

Awaited condition: **WRAM `0xCFB3 == 0`**. It is cleared by the VBlank handler
reached from vector `0x0040 -> 0x0283`, whose dispatched handlers contain
`XOR A; LD ($CFB3),A` (for example at `0x0334`, `0x0353`, `0x0415`, `0x044E`).

Actual: `0xCFB3` stays `1`. The VBlank vector is **never serviced**. Crystal's
per-300-frame probe shows:

```
STATE pc=0x0460 ... halted=1 ... ie=0x0F if=0x00 ...
irq=[0 41623 77 0 0]          ; VBlank, STAT, timer, serial, joypad
VEC40 n=0 VEC48 n=41623 VEC50 n=77 VEC58 n=0 VEC60 n=0
```

So the CPU wakes from HALT only on STAT (audio updater at `0x0552`) and timer,
then immediately re-HALTs. The main thread never passes `0x045F`.

**Pokemon Pinball (`p_pin.gbc`, CGB and DMG), main-thread loop at `0x0468..0x0476`:**

```
0468  F0 40        LDH  A,(LCDC)     ; LCDC bit 7 must be on to enter wait
046A  CB 7F        BIT  7,A
046C  C8           RET  Z
046D  21 B2 FF     LD   HL,$FFB2      ; HRAM flag
0470  AF           XOR  A
0471  77           LD   (HL),A        ; clear flag
0472  7E           LD   A,(HL)        ; poll
0473  A7           AND  A
0474  28 FC        JR   Z,$0472       ; repeat until (HRAM $FFB2)!=0
0476  C9           RET
```

Awaited condition: **HRAM `0xFFB2 != 0`**. The VBlank handler
(`0x0040 -> 0x02F2`) increments it at `0x035A`:
`LD HL,$FFB2; LD A,(HL); INC (HL); ...`.

Actual: `0xFFB2` stays `0`; the VBlank handler never runs. Pinball's 300-frame
probe shows:

```
STATE pc=0x0472 ... ie=0x01 if=0x00 ...
irq=[0 0 0 0 0]
VEC40 n=0 VEC48 n=0 VEC50 n=0 VEC58 n=0 VEC60 n=0
HOT pc=0x0472 n=837796, 0x0473 n=837796, 0x0474 n=837796
```

The IO ring contains **no** reads of `FF00/FF41/FF44/FF55` from this loop; the
poll is plain HRAM memory. The same loop and the same zero-interrupt state occur
in DMG mode.

**Kirby's Dream Land (`k_dl.gb`)** shows the same class of failure: IE is `0x05`
(VBlank + timer), but the 300-frame probe records `VEC40 n=0`, no interrupt
service, `vram[0]=0`, and a uniform green frame. With a VBlank request injected
(see §2.4) KDL reaches `vram[0]=1`, timer IRQs, and a 4-colour frame.

### 2.3 Expected vs actual and Pan Docs

Pan Docs: the PPU requests the **VBlank interrupt** (IF bit 0) when the display
enters VBlank, i.e. when LY advances from 143 to 144 (only while the LCD is on).
The VBlank interrupt vector is `0x0040`. STAT interrupts are a separate source
(IF bit 1).

Actual implementation:

- `ppu.zig:606-623` (`enterLine`): for `line >= 144` it sets `mode = 1` but never
  calls `mmumod.busRaiseIrq(bus, 0x01)`.
- `ppu.zig:89-93` (`updateStatLine`) is the only PPU IRQ producer and raises
  **only** mask `0x02` (STAT).
- A repository-wide search finds `busRaiseIrq(...)` only at `ppu.zig:91` and
  `ppu.zig:219`, both mask `0x02`. No code raises mask `0x01`.
- `mmu.zig:473-475` (`busRaiseIrq`) and the FF0F read/write plumbing are correct;
  the caller is missing.

Expected register behavior vs actual:

| Register / condition | Expected (Pan Docs) | Actual in z9gb |
|---|---|---|
| `IF` bit 0 (`0xFF0F`) at LY 143→144 | set to 1 once per frame | never set (0 always) |
| VBlank vector `0x0040` | runs ~59.7×/s | 0 services in 300 frames |
| Crystal `0xCFB3` | cleared by VBlank ISR, then main continues | stays 1; HALT loop forever |
| Pinball `0xFFB2` | incremented by VBlank ISR | stays 0; HRAM poll loop forever |
| VRAM/CRAM after init | game data uploaded | default white/green only |

Ruled out: the wait loops do not poll `STAT` (`FF41`), `LY` (`FF44`), `HDMA5`
(`FF55`), joypad (`FF00`), or an MBC readback. The probe's IO histogram for
Pinball contains only a handful of early `FF40/FF44` reads; the steady-state poll
is entirely WRAM/HRAM driven by the missing VBlank ISR.

### 2.4 Confirmation experiment (in /tmp only)

A second /tmp-only copy added exactly one line at the VBlank transition:

```
if (line == VISIBLE_LINES) mmumod.busRaiseIrq(bus, 0x01);
```

Rebuilt both the instrumented probe and a full headless emulator and ran 600 frames:

| Build / ROM | unique framebuffer colours | notes |
|---|---:|---|
| baseline Crystal, 1200 frames | **1** (white) | no progress |
| baseline Pinball CGB, 1200 frames | **1** (white) | no progress |
| baseline Pinball DMG, 1200 frames | **1** (green) | no progress |
| baseline KDL, 1200 frames | **1** (green) | no progress |
| VBlank-patched Crystal, 600 frames | **3** | VEC40=107 in 120 frames; HDMA becomes active |
| VBlank-patched Pinball CGB, 600 frames | **8** | VEC40=107 in 120 frames |
| VBlank-patched Pinball DMG, 600 frames | **4** | VEC40=100 in 120 frames |
| VBlank-patched KDL, 600 frames | **4** | VEC40=98, timer IRQs in 120 frames |

This isolates the missing VBlank request as the cause of the uniform-screen hang.
(Pinball still spends most time in the `0x0472..0x0474` loop between VBlanks, which
is expected for a per-frame wait; with VBlank it exits once per frame and advances.)

Non-blocking secondary observation: `enterLine` sets visible lines to mode 0 for
the first 4 dots of the line before switching to mode 2, whereas hardware starts
in mode 2. This could skew STAT timing but was not the cause of these hangs and was
not changed.

## 3. Root cause #2 — dynarec `pal_trap` from `labelPatchAt`

**Severity: critical for `--dynarec` on Pinball. Confirmed by the operator's mapping
and re-verified here.**

Reproduction (`p_pin --cgb --dynarec`) gives
`wine: Unhandled exception 0x80000003` (`int3`) at `0x0043B376` inside `_pal_trap`
(`0x0043b330..0x0043b37a`). `lin_bin/backtrace.txt` has only the trap site. Using
`winedbg` and continuing past the first-chance breakpoint produced the caller stack:

| frame | return address | symbol | offset |
|---:|---|---|---|
| 0 | `0x0043B377` | `_pal_trap` | +0x47 (after `int3`) |
| 1 | `0x00432705` | `labelPatchAt` | +0x1a5 |
| 2 | `0x00435CBB` | `emitMemWrite` | +0x53b |
| 3 | `0x0043836C` | `emitPushImm16` | +0x18c |
| 4 | `0x004393B1` | `emitCallInsn` | +0x91 |
| 5 | `0x0043973C` | `emitInsn` | +0x2bc |
| 6 | `0x0043A927` | `emitBlock` | +0x327 |
| 7 | `0x00411A0D` | `translate` | +0x3cd |
| 8 | `0x004126E4` | `dynarecRunBlock` | +0x294 |
| 9 | `0x00413B6C` | `emuRunFrame` | +0x10c |
| 10 | `0x0041724F` | `main` | +0xaef |

Disassembly at the trap site confirms the failing runtime check:

```
00432560 <labelPatchAt>:
...
0043263f: test %eax,%eax              ; _zig_overflow_flag_sub_u(target, at+4)
00432645: ...
00432700: call 0043b330               ; call _pal_trap
00432705: ...                         ; return address seen in frame 1
```

The source is `examples/z98/z9gb/dynarec/x86.zig:149-157`:

```
fn labelPatchAt(e: *Emit, l: *Label, target: usize) void {
    ...
    const at: usize = l.at[i];
    const rel: usize = target - (at + 4);   // x86.zig:153
    writeU32At(e, at, rel);
}
```

Mechanism: a label entry whose offset is at/after `target - 4` makes
`target - (at + 4)` wrap below zero. In the safe (`-fsafe`) build this is a checked
unsigned subtraction and calls `pal_trap()`; the trap has no handler and executes
`int3`, killing the process. A backward reference is being patched during
translation. Under `-ffast` the subtraction wraps, producing the intended two's
complement x86 `rel32`, so the same code path is harmless there. The interpreter
never calls `emitBlock`, so it is unaffected.

Dynarec-only evidence:

- interpreter Pinball CGB/DMG: rc 0, no trap;
- dynarec Crystal: rc 0, no trap;
- dynarec KDL: rc 0, no trap;
- dynarec Pinball: rc 3, trap; `--frames 1..10` rc 0, `--frames 12+` rc 3.

Thus the trap is reached during translation of a Pinball block first encountered
around frame 11 (via a CALL instruction -> `emitCallInsn` -> `emitPushImm16` ->
`emitMemWrite` -> `labelPatchAt`).

## 4. Interpreter vs dynarec audio divergence

**Verdict: no evidence of a real APU semantic divergence. The reported difference
is trap timing / process lifetime.**

Both engines share `bus`, `ppu`, and `apu`. The dynarec Pinball process dies at the
`int3` during translation around frame 11, so its audio output stops there; the
interpreter has no `pal_trap` and keeps running, continuing to produce the early
init/STAT-driven sounds. The "single tum" is therefore the last short burst before
the translation trap, not a different audio path. After fixing the trap, the audio
comparison should be repeated; no separate APU defect is supported by this
investigation.

## 5. Kirby Tilt (`0x22`) and MBC5 rumble assessment

### Kirby Tilt `0x22`

Confirmed reject path:

- `cart.zig:144-150` `mbcKnown` accepts only `0x00`, `0x01..0x03`, `0x0F..0x13`,
  `0x19..0x1E`; `0x22` is not accepted.
- `cart.zig:214` therefore returns `error.UnsupportedMbc`.
- `main.zig:360-370` maps every non-`RomTooLarge`/non-`CgbRequired` loader error to
  the generic `"z9gb: cannot read ROM\n"` (`main.zig:367`).
- Running `k_tt.gbc --cgb` exits rc 2 with exactly that message.

Note `typeIncludesRam` lists `0x22` at `cart.zig:140`, but the `mbcKnown` check runs
first, so it has no effect.

Proposed clearer diagnostic (do not implement yet):

```
z9gb: unsupported cartridge type 0x22 (MBC3+accelerometer); Kirby Tilt 'n' Tumble is not supported
```

This needs either a distinct loader error carrying the type byte, or a header check
in `main.zig`; keep the reject behavior.

### MBC5 rumble RAM-bank mask (`cart.zig:203`, `cart.zig:505`)

Current code stores `ram_bank = value & 0x0F` (`cart.zig:505`) and computes
`ram_off = (ram_bank & 0x0F) * 0x2000` (`cart.zig:203`). For MBC5+RUMBLE
(types `0x1C..0x1E`) Pan Docs reserve register bit 3 for the rumble motor; the RAM
bank is bits 0-2 only, so the mask should be `0x07` for those types.

Save-safety assessment for Pinball (type `0x1E`, 8 KiB RAM, one bank):

- If the game sets bit 3, current `ram_off` becomes `8 * 0x2000 = 0x10000`, which
  is `>= ram_size (0x2000)`.
- Reads then return `0xFF` and writes are discarded (`cart.zig:507-510`); bank 0
  is not overwritten, so existing save data is not corrupted by this alone.
- However, cart RAM becomes inaccessible while the rumble bit is set, which can
  break save/load logic and any checksum verification.
- On a larger rumble cart with 128 KiB RAM, bit 3 would alias bank 8 and could
  write save data into the wrong bank, which is a real corruption risk.

Proposed (do not implement): mask the RAM bank with `0x07` for types `0x1C..0x1E`
and keep bit 3 as rumble state, e.g. store `ram_bank = value & 0x07` and retain the
raw bit for the rumble output. Apply consistently in `mbc5Write` and
`mbc5Recompute`.

No save file was written during this investigation; the existing `p_pin.sav` was
left untouched.

## 6. Minimal fix proposal, ranked by risk

1. **PPU VBlank request (critical, lowest risk).** In `ppu.zig:enterLine`, on the
   transition to line 144 (and only there), call `mmumod.busRaiseIrq(bus, 0x01)`.
   Regression: 120-frame headless Crystal/Pinball-CGB/Pinball-DMG/KDL must produce
   a framebuffer with more than one unique colour; a focused PPU test should assert
   IF bit 0 is set when LY goes 143 -> 144 and not set while the LCD is off. Do not
   raise it on lines 145-153.
2. **Dynarec label patch underflow (critical for dynarec, low risk).**
   `x86.zig:153`: use `const rel: usize = target -% (at + 4);` (wrapping
   subtraction, matching `-ffast`) or compute a signed displacement and encode its
   two's complement. Regression: translate Pinball's triggering block pattern, or a
   synthetic block with a backward patch, and assert no trap plus correct `rel32`.
3. **MBC5 rumble RAM mask (save correctness, low/medium risk).**
   `cart.zig:203` and `cart.zig:505`: use `& 0x07` for types `0x1C..0x1E`; keep
   bit 3 as rumble state. Regression: rumble-cart RAM-bank writes with bit 3 set
   still address banks 0-7, and Pinball save data round-trips.
4. **Kirby Tilt diagnostic (cosmetic, trivial risk).** Split
   `error.UnsupportedMbc` from the generic `main.zig:367` message and report the
   cartridge type/feature (`0x22` MBC3+accelerometer).

## 7. Artifacts and reproduction commands

All scratch artifacts are under `/tmp/z9gb_compat/`:

- `matrix/` — baseline commands/results, framebuffers, logs; `matrix/pin_dyn_fN.log`
  shows the frame-11 transition (`--frames 10` rc 0, `--frames 12` rc 3).
- `probe/` — instrumented /tmp copy (PC/page/IO/IRQ histograms and rings).
- `probe_vb/` — same probe with the experimental VBlank-IF line.
- `build_vb/` — full headless build with the experimental VBlank-IF line, used for
  the 600-frame framebuffer comparison.
- `winedbg_pin3.log` — winedbg caller stack for the `pal_trap` reproduction.
- `syms.txt` — sorted PE symbols used to map return addresses.

No repository product source, tests, gates, seed, plans, or
`lin_bin/backtrace.txt` were modified. No commits or pushes were made.

**STOP — awaiting operator approval before implementing any fix.**
