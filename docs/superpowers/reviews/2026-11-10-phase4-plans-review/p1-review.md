# P1 Review — Platform Abstraction and Headless Backend Plan

**Reviewer:** independent plan reviewer
**Date:** 2026-11-10
**Plan under review:** `docs/superpowers/plans/2026-11-10-phase4-p1-platform-headless-plan.md`
**Spec (authority):** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`
**Mode:** REVIEW-ONLY. No plan/spec/source edits. Findings appended incrementally.

## Status Table

| # | Dimension | Status | Section |
|---|---|---|---|
| 1 | Objective coverage | DONE | §1 |
| 2 | Interface consistency | DONE | §2 |
| 3 | Win9x soundness | DONE | §3 |
| 4 | Achievability under pure Z98 | DONE | §4 |
| 5 | Test evidence quality | DONE | §5 |
| 6 | Memory model | DONE | §6 |
| 7 | Dependencies/ordering | DONE | §7 |
| 8 | Plan structure quality | DONE | §8 |
| 9 | Fact table | DONE | §9 |
| 10 | Caveat list | DONE | §10 |

---
## 1. Objective coverage (spec → P1 task mapping)

Spec requirement → P1 coverage:

| Spec item | P1 coverage | Verdict |
|---|---|---|
| §8.1 layout `platform/backend.zig`, `platform/headless.zig`, `testdata/`, `tests/`, `main.zig`, `emu.zig` | Tasks 1–2 create all | MAPPED |
| §8.2 `EmuConfig`/`EmuError`/`Emu` facade | Task 2 (subset) | MAPPED WITH DRIFT (see §2) |
| §8.3 `InputState`, `Platform` 5-field table, `platformHeadless()` | Task 1 | MAPPED |
| §9 P1 gate "deterministic headless self-test" | Tasks 2–3, 5 | MAPPED |
| §9 P1 deliverable "RSS harness" | Task 3 `measure_rss.sh` | MAPPED (weak, see §6) |
| §5.2 memory model (1 MiB stack vs 1 MiB cache vs 8 MiB ROM vs 12 MiB RSS) | Global Constraints echo; Task 3 measures RSS only | PARTIAL: no stack measurement; spec §5.2 "report stack, cache, static, and driver surfaces separately" is not met (P1 has no cache/driver, but stack/static breakdown is unaddressed) |
| §5.3 test-asset policy (`testdata/roms/README.md`, `manifest.sha256`, `.gitignore` for `*.gb/*.gbc/*.sav/*.rtc`, synth ROMs tracked) | Task 1 `.gitignore` only | PARTIAL: `roms/README.md` + `manifest.sha256` not created in P1 (deferred to P2 Task 0 implicitly), and the `.gitignore` breaks the synth-ROM tracking rule (see §5/§7) |
| §5.3 "Missing ROMs are SKIP, never PASS" | Global Constraints state it; no test in P1 can exercise it (no ROM support yet) | MAPPED as policy |
| §5.1 pure-Z98 / no Win32 in headless | Global Constraints + Task 1 Step 4 dump check | MAPPED |
| §8.11 tier script set | `tier_smoke.sh` only | MAPPED (other tiers are P2–P5 artifacts) |
| §8.11 build recipes (`zig1 -ffast -o …`, `build_target.sh linux`, `check_win9x_imports.sh`) | Task 4 Step 4 (Linux only) | MAPPED (no `-osw` build in P1; acceptable, P1 gate is headless) |
| §5.1 "`dinput8.dll` DX8 fallback" / DirectDraw / DirectSound (§8.4 std modules) | Out of P1 scope (P3) | correctly deferred |
| §8.5–§8.10 CPU/MMU/PPU/APU/cart/serial/dynarec | Out of P1 scope ("No emulator logic yet") | correctly deferred |

**Unmapped spec items for P1 scope:**
1. §5.3 `testdata/roms/README.md` (provenance) and `manifest.sha256` — no task creates them. If P2 Task 0 "Check `testdata/roms/manifest.sha256` paths" runs before any task creates the manifest, that step has nothing to read. P1 should either create a stub manifest or P2's plan must create it (cross-plan gap).
2. §5.2 "Report stack … separately" — no stack-use measurement or review step in P1 (plan Review Focus 4 says the 1 MiB stack is respected, but no step proves it beyond "no large stack locals" by construction).

## 2. Interface consistency (plan ↔ spec ↔ later plans)

Exact-match items (PROVED consistent with spec):
- `InputState = struct { buttons: u8, quit: bool }` — spec §8.3 verbatim.
- `Platform` 5-field table — spec §8.3 verbatim, incl. `open_fn: fn (*void, u32, u32, u32) bool` and `present_fn: fn (*void, []const u32) void`.
- `platformHeadless() *Platform` — spec §8.3.
- `emuInit(e: *Emu, cfg: EmuConfig) void`, `emuRunFrame(e: *Emu) u32`, `emuFramebuffer(e: *const Emu) []const u32` — spec §8.2 verbatim.
- File layout (`platform/backend.zig`, `platform/headless.zig`, `testdata/`, `tests/`) — spec §8.1 verbatim.

**DRIFT (Important):**
1. **`EmuConfig` is missing `dynarec: bool`.** Spec §8.2 defines `{cgb, serial_log, turbo, dynarec}` (4 fields); plan Task 2 "Produces" `{cgb, serial_log, turbo}` (3 fields). P5 explicitly consumes `EmuConfig.dynarec: bool` (`...p5-dynarec-plan.md:202`), and the spec already declares the field, so P1 is editing a spec-defined type without an amendment. Spec §11: "Anything that changes a public API in this spec is a spec amendment and needs operator approval." Fix: include `dynarec: bool` now (P1 can ignore it).
2. **`EmuError` is missing `CgbRequired`.** Spec §8.2 lists `CgbRequired`; plan Task 2 omits it. P4 depends on it (`...p4-cgb-plan.md:76`: "a CGB-only ROM with `cfg.cgb=false` returns `CgbRequired`"). Same amendment rule applies.
3. **`pub fn emuSelfTestPattern(e: *Emu) void`** is a public facade function not present in spec §8.2's API list. Adding it is an API addition; either mark it test-internal or route it through operator approval. (Low risk, but spec §11 is explicit.)

**Deferred-but-noted contract items (acceptable):** `emuLoadRom`, `emuReset`, `emuAudioSamples`, `emuSetButtons`, `emuTakeSerial`, `emuSetSavePath`, `emuSaveBattery`, `emuLoadBattery` are spec §8.2 API that P1 does not produce; P2/P3 own them. P1 pre-allocates `serial_log`/`save_path` storage for them — fine.

**Button bit order gap (Minor):** Spec §8.2 pins "0 right, 1 left, 2 up, 3 down, 4 a, 5 b, 6 select, 7 start". P1's `InputState.buttons` comment says only "same bit order as emuSetButtons", and `emuSetButtons` does not exist yet. The plan should restate the bit order so P3's Win32 poll mapping has a local contract.

**Later-plan consumption check:** P3 "Consumes: … P1 `Platform`" and produces `platformWin32() *Platform` (`...p3-playable-dmg-plan.md:220-222`) — consistent with spec §8.3. P2 consumes "P1 `Emu`" / "`Emu` fixed ROM buffer" (`...p2-dmg-core-plan.md:43,67`) — but P1's `Emu` contains **no ROM buffer** (`fb`, `serial_log`, `cfg`, `save_path` only), and P2 Task 0 Step 1 says "Run the P1 loader stub" — P1 ships no loader and `--rom` is explicitly "stored, not loaded in P1". Contract gap (see §7).

## 3. Win9x soundness

P1 produces no Win9x binary; this section judges whether the foundation is sound for P3.

- **Import whitelist impact:** P1 adds no imports at all (headless is Linux-only). The whitelist in `scripts/win32_cross/check_win9x_imports.sh` (KERNEL32/WINMM/WSOCK32/DDRAW/GDI32/USER32; `msvcrt.dll` banned on 9x) is untouched by P1. `LoadLibraryA`/`GetProcAddress`/`FreeLibrary` are whitelisted (check_win9x_imports.sh KERNEL32_9X), so spec §5.1's dynamic `dsound`/`dinput8` loading strategy remains gate-compatible. PROVED.
- **No-CRT compatibility:** P1 never runs the `-osw`/no-CRT recipe; nothing in P1 forces CRT symbols. The emitted mingw recipe is no-CRT by default (`sf/src/c89_emit.zig:9752` template: `-nostdlib`, `zig_nocrt.c`/`c_exit.c`). Sound.
- **COM/vtable ABI:** The `Platform` table uses bare `fn` types — an entirely in-Z98 callback table; no ABI crossing. P3's COM vtables use `extern "stdcall"` fn pointers (spec §5.1, pattern `sf/src/std_gfx_pal.zig`). Z98 fn-pointer signature matching distinguishes calling conventions (`docs/reference/Language_Spec_Z98.md:41`), so the two worlds cannot be silently mixed. Sound.
- **Timer:** Spec §8.8 frame pacing uses QPC + `Sleep`; `QueryPerformanceCounter`/`QueryPerformanceFrequency`/`Sleep`/`GetTickCount` are all whitelisted (check_win9x_imports.sh KERNEL32_9X). `timeBeginPeriod` is absent from `std_time` (spec §6) and **not** in the WINMM whitelist (only `waveOut*` — check_win9x_imports.sh WINMM_ALL). If P3 ever wants 1 ms multimedia resolution it must change the gate script; P1 is not affected. Caveat only.
- **DirectX reality (flagged here because P1 fixes the table shape):** spec §5.1/§10 handles DX5-era Win98 without DX8 (`dinput8.dll` → `GetAsyncKeyState` fallback). **But `GetAsyncKeyState` is NOT in the USER32 whitelist** (check_win9x_imports.sh USER32_ALL has `GetKeyState`, not `GetAsyncKeyState`), and the spec never says the fallback is dynamically loaded. As spec'd, the P3 fallback path will FAIL `check_win9x_imports.sh` on a static import. Fix belongs to P3 (use `GetKeyState`, `GetProcAddress` the symbol, or amend the whitelist), but the spec-level contradiction should be resolved before P3 starts. `dsound`/`dinput8` static imports are correctly forbidden by the whitelist (unknown-DLL FAIL), matching spec's dynamic-load requirement.
- **32-bit/32 MB:** P1's statics are ~188 KB (see §6); nothing in P1 pressures the 32 MB machine. The 12 MiB RSS + 1 MiB stack + 1 MiB cache budget is structurally separate per spec §5.2. P1 does not harm it.
- **Verdict for P1:** foundation is sound; no unsound Win9x commitment is made by P1. The `GetAsyncKeyState` whitelist contradiction is a pre-existing spec defect that P3 must not inherit silently.

## 4. Achievability under pure Z98

Constructs P1 needs, checked against `docs/reference/Language_Spec_Z98.md`:

- Struct with `fn`-pointer fields (`Platform`) — legal; fn-pointer fields are established (`Language_Spec_Z98.md:41`, vtable precedent `:486`). PROVED.
- `*void` opaque state pointer — legal (`void` is a type `:20`; `@asyncInit` returns `*void` `:359`). PROVED.
- Module-scope `var rom: [8 * 1024 * 1024]u8` / `[160 * 144]u32` statics — array-size evaluator accepts `0..0xFFFFFFFE` (`:703`); 8 MiB and 23040 both fit. Task 0 Step 2 probes this at runtime — good practice. PROVED feasible.
- Error sets (`EmuError`), slices (`[]const u32`, `[]const i16`), `*const Emu` params — all core type system. PROVED.
- No generics/`anytype` (`:112` rejects `anytype`), no methods (`:131`), mandatory `switch` `else` (`:215`), no tagged-union payload-member stores (`:55`), shifts non-wrapping/checked (`:463`, `:700`) — P1's code (pattern fill, arg parse, table dispatch) uses none of the forbidden shapes. The plan's Global Constraints list matches the real language limits. PROVED.
- D16 remains the only open parity defect (`:467` "Switch / assignment parity boundary (D16, open)") — nothing in P1 touches mixed statement switches/assignment parity. No exposure.
- zig1 recipe: `zig1 -ffast -o <dir> <entry>` emits a self-contained dir incl. `build_target.sh` (README.md:493 confirms `-o`/`--output-dir` alias; `sf/src/c89_emit.zig:9752` the template). The emitted script `cd "$(dirname "$0")"` so `sh /tmp/z9gb/build_target.sh linux /tmp/z9gb/z9gb` is CWD-safe (c89_emit.zig:9755). Plan's recipes are buildable exactly as written. PROVED.
- `--dump-c89` + `-o` combination (Task 1 Step 4) is the documented corpus recipe shape (QUICK_REF.md:420 `--dump-c89 --output-dir DIR`; `-o` is the same flag family, main.zig:2088). PROVED.

**One broken probe (Important):** Task 0 Step 1 runs `"$ZIG1" --version` expecting a "version banner; no lib error". zig1 has **no `--version` flag** — unrecognized dash-args fall through to `cli.input_file` (`sf/src/main.zig:2167-2168`), so the run treats `--version` as a source path and fails to compile it (banner "Z98 Compiler 2026" prints to stderr first, `main.zig:189-193`, so the probe may half-pass while rc != 0). Use `"$ZIG1" --help` (exits 0, `main.zig:2068-2071`) or a one-line hello compile instead.

**Verdict:** all P1 constructs exist and compile; the documented zig1 recipe works; one probe expectation is factually wrong.

## 5. Test evidence quality (can an executor fake a pass?)

**Arithmetic recomputation (all verified):**
- Framebuffer size: 160 × 144 × 4 = **92,160 B** — matches plan (`stat -c %s … = 92160`), spec §5.2, and `static_bytes=92160`. PROVED.
- Pattern `fb[y*160+x] = 0x00010000 | (x & 0xFF) | ((y & 0xFF) << 8)`:
  - first pixel (x=0,y=0) = `0x00010000` ✓ (plan Task 2 Step 5).
  - middle (x=80,y=72): `0x00010000 | 0x50 | (72<<8=0x4800)` = **`0x00014850`** ✓; byte offset `(72*160+80)*4 = 46,400` ✓.
  - last (x=159,y=143): `0x00010000 | 0x9F | (143<<8=0x8F00)` = **`0x00018F9F`** ✓; offset `(143*160+159)*4 = 92,156`, +4 = 92,160 ✓.
- `emuRunFrame` returns **70,224** = 456 T-cycles/line × 154 lines ✓ (spec §8.6).
- Matrix counts 28/28 → 29/29: `examples/z98/` has **32** immediate subdirs (counted at HEAD); 32 − 4 = 28 and 33 − 4 = 29. The live corpus universe (`bash scripts/corpus/list_corpus_dirs.sh`) emits **31** `examples/z98/` entries (every dir except `demo`, which has no depth-1 `*.zig`); the maintained matrix excludes 3 more (`gfx_demo`, `z9dbg`, `z9edit`) per the frozen reconstruction (`scripts/corpus/frozen_1124.txt` lists 26 entries — no gfx_demo/z9dbg/z9edit/demo; +`z9git`+`z9zstddecomp` = 28). **28→29 arithmetic PROVED**; the "four exclusions (demo, gfx_demo, z9dbg, z9edit)" attribution is numerically right but nowhere documented as policy (INCOMPLETE provenance).
- 12 MiB RSS vs the plan's `rss_kb < 12000`: 12 MiB = 12,288 KiB; the plan's bound is *tighter* than the spec target. Fine, but note it is asserted on a no-ROM build (see §6).

**Evidence strength per gate:**
- Size check (92160) — strong, exact.
- Three-word `od` spot checks — **weak**. Spec §8.11 defines `tier_smoke.sh` as "build, headless self-test, **deterministic framebuffer hash**", and §8.6/§5.3 use full-image hashes as goldens. Three words can pass while the rest of the buffer is wrong. The repo already has MD5 golden conventions (README.md:190-193). **Fix: hash the whole 92,160-byte file (md5) and pin the expected digest; keep the 3 word-checks as diagnostics.**
- Three-run `cmp -s` determinism — strong for repeatability, but it is self-consistency only; it cannot catch a deterministically wrong buffer. Complementary to a pinned hash, not a substitute.
- `measure_rss.sh` — an executor could trivially "pass" by measuring a different binary; the script builds the program itself (Task 3 Step 1 "builds the program"), which is the right shape. Asserting `0 < rss_kb < 12000` is precise. `static_bytes=92160` is hard-coded — see §6.

**SKIP-vs-FAIL policy:** `exit 77` + `SKIP:` line for missing `/usr/bin/time` matches the established pattern (`examples/z98/z9torr/tests/tier4_wine.sh:24,42-52` documents "SKIP-with-reason (exit 77, distinct from PASS=0 / FAIL=1)"; `examples/z98/z9git/tests/tier_git.sh:1769` already SKIPs RSS tiers when `/usr/bin/time` is absent). PROVED consistent. Missing-external-ROM SKIP cannot appear in P1 (no ROM support) — correctly left to P2 (`tier_dmg.sh … exits 77`, p2:357).

**Verifiability nits (Minor):**
- Task 1 Step 1's test "checks that `platform/backend.zig` and `platform/headless.zig` appear in the dump" — no dump command is defined at that point (no entry file exists until Task 2); step is ambiguous about *which* dump. Unverifiable as written.
- Task 2 Step 4 "presents the final frame" has no observable assertion in the test (headless present writes an internal snapshot that nothing checks).
- `open_fn` "returns true for 160x144" is never tested in the negative (e.g. 161×144 must return false).
- `stat -c %s` is GNU coreutils, not POSIX (`od -An -tx4` is POSIX but host-endian). Acceptable on the pinned Linux host; the plan claims "POSIX shell test tiers" (Tech Stack) — slightly overstated.

**Overall:** precise enough that a fake pass is hard, **except** the framebuffer-content gate, which is materially weaker than the spec's own gate definition.

## 6. Memory model

Regions (spec §5.2): stack 1 MiB | dynarec cache 1 MiB (P5, `VirtualAlloc`, separate) | ROM 8 MiB static | fb 92,160 B | DDraw offscreen 1,474,560 B (P3) | provisional 12 MiB RSS.

**What P1 measures:** peak RSS of the headless binary via `/usr/bin/time -f '%M'` over 60 frames, asserted `< 12000` KiB, plus a hard-coded `static_bytes=92160`.

**Sound?** Partly.
1. `'%M'` (GNU time, max RSS in KiB) is a real, standard measurement and the repo has precedent (tier_git.sh:1769). The gate cannot be faked without editing the script. OK.
2. **`static_bytes=92160` under-reports.** P1's actual static footprint is framebuffer 92,160 + headless snapshot **another 92,160** (Task 1 Step 3 "present_fn copies the 160x144 frame into a static headless snapshot") + `serial_log` 4,096 + `save_path` 260 + `cfg` ≈ **188.6 KB**, not 92 KB. If the number is meant as an accounting probe for spec §5.2's "report … static … separately", it is wrong by ~2×.
3. **No stack reporting.** Spec §5.2: "Report stack, cache, static, and driver surfaces separately." P1 reports none of stack/cache/driver (cache and driver genuinely don't exist yet; stack does). Review Focus 4 asserts the 1 MiB stack is respected "by construction" but no step verifies it (no canary, no `-fstack-usage`, no review step). For P1's trivial code this is low-risk but unproven.
4. **The 12 MiB gate is nearly free at P1.** With no 8 MiB ROM loaded, a passing P1 RSS number says almost nothing about the real budget (8 MiB ROM + 1.4 MB DDraw surface + 1 MiB cache + state will consume ~10.5 MiB of the 12 MiB before the emulator's own tables). The plan does say "no ROM yet", which is honest; but the closeout evidence must not be cited later as "12 MiB verified". Spec §5.2 already frames P1 as one of several measurement points (P1 headless, P3 windowed+audio, P4/P5 re-measure) — consistent.
5. ROM 8 MiB static: P1 deliberately has no ROM buffer. But P2 "Consumes: `Emu` fixed ROM buffer" (p2:67) — the buffer must materialize in P2 and the RSS math must be re-derived there (8 MiB static alone is 2/3 of the budget). Not a P1 defect; a cross-plan risk.

**Verdict:** methodology is honest for what it measures, but the `static_bytes` figure is wrong and the spec's stack/static reporting split is unmet; the P1 number must be labeled "no-ROM baseline".

## 7. Dependencies / ordering (P1 outputs → P2 inputs)

| P2 expectation | P1 produces | Status |
|---|---|---|
| `Emu` fixed ROM buffer (p2:67) | `Emu{fb, serial_log, cfg, save_path}` — **no ROM buffer** | MISMATCH — P2 must add it; P2 Task 0 Step 2 probes the 8 MiB boundary before any P2 task adds the buffer |
| "Run the P1 loader stub" (p2:43, Task 0 Step 1) | **No loader**; `--rom` is "stored, not loaded in P1" | MISMATCH — probe cannot run as written; either P1 ships a size-checking `emuLoadRom` stub (spec §8.2 has `emuLoadRom`) or P2 Task 0 moves after its Task 1 |
| `emuFramebuffer` 160×144 RGB32 (p2:294) | yes, `[]const u32`, 0x00RRGGBB | OK |
| `EmuError` incl. `RomTooLarge`/`BadHeader`/`UnsupportedMbc`/`SaveCorrupt`/`Io` | yes (minus `CgbRequired`) | OK except drift (§2) |
| `EmuConfig.cgb` (p4:76), `EmuConfig.dynarec` (p5:202) | `cgb` yes; `dynarec` **missing** | MISMATCH (§2) |
| test harness / tier conventions (exit 77 SKIP, `tests/tier_*.sh`) | `tier_smoke.sh`, `measure_rss.sh` | OK |
| serial hook | fields `serial_log`/`serial_len` allocated; `emuTakeSerial` deferred to P2 | OK (storage handed over) |
| button enum | `InputState.buttons: u8`, bit order only by reference | OK with doc gap (§2) |
| `testdata/.gitignore` + synth ROM tracking (p2:92 commits `testdata/synth/minimal.gb`) | `.gitignore` with bare `*.gb` | **BREAKS P2** — `*.gb` under `testdata/.gitignore` applies recursively and will make `git add testdata/synth/minimal.gb` fail (ignored). Needs `!synth/` (or `!synth/*.gb`) negation. Spec §5.3 explicitly requires synth ROMs tracked. |
| `platformHeadless()` consumed by P2 tests via the built binary | yes | OK |

**Ordering verdict:** P1 delivers the facade/table/harness P2 needs, but three contract holes (ROM buffer, loader stub, `.gitignore` negation) will bite P2 Task 0/Task 1 immediately.

## 8. Plan structure quality

Template compliance per task (Files / Interfaces / TDD steps + Expected / commit):

| Task | Files | Interfaces | TDD + Expected | Commit | Notes |
|---|---|---|---|---|---|
| 0 Feasibility probes | yes (temp) | yes | steps have expectations | n/a (no commits) | Step 1 probe is factually wrong (`--version`, §4); Step 4 corpus expectation wrong (below) |
| 1 Table + headless | yes | yes | Step 1-2 FAIL expectations OK | yes | Step 1's "appear in the dump" is undefined (§5); `platformNoop` appears in Step 3 but has **no signature** in the Interfaces block |
| 2 Emu facade | yes | yes (with drift §2) | Steps 1-2 FAIL, Steps 3-5 exact values | yes | strongest task; pixel values pinned and correct |
| 3 RSS + determinism | yes | yes | exact assertion bounds | yes | `static_bytes=92160` hard-coded and wrong (§6) |
| 4 Register + matrix | yes | yes | count-1 + build rc 0 + size | yes | "Update every live count and the build recipe" does not enumerate the 4 README sites (README.md:57,208,519,598) + QUICK_REF.md:570; executor must find them |
| 5 Closeout | yes | yes | PASS + rc 0 + no windows.h | yes | fine |

**Vague/unverifiable steps (flagged):**
1. Task 0 Step 4: "Expected: absent before Task 1; **after Task 1 it must appear exactly once**" — DISPROVED. `scripts/corpus/list_corpus_dirs.sh` resolves only depth-1 entry files (`main.zig`, `<basename>.zig`, or first `*.zig` directly under the dir; `emit_dir`, list_corpus_dirs.sh). Task 1 creates only `platform/*.zig` (depth 2), `tests/`, `testdata/`. The entry appears after **Task 2** (`main.zig`), not Task 1. As written, the executor will hit a false failure.
2. Task 1 Step 1: "checks that … appear in the dump" — no dump command at that point; no main exists. Ambiguous.
3. Task 1 Step 3: `platformNoop` "null-safe helper" — no signature; also absent from the Produces list.
4. Task 4 Step 3: "Update every live count and the build recipe" — which recipe lines (README.md:461-467 build recipe block vs QUICK_REF.md:570)? Acceptable with care, but not pinned.
5. Task 2 Step 4 "presents the final frame" — no checkable output.

**Positive structure notes:** TDD ordering is real (each task's Step 1-2 is a failing test before implementation); Expected outputs are concrete (rc, byte sizes, exact hex words, counts); commit blocks are scoped; Global Constraints and Review Focus sections give the executor clear invariants; "no seed rotation in P1" is explicit.

## 9. Fact table

| # | Claim (location in plan) | Verdict | Evidence |
|---|---|---|---|
| 1 | `main.zig` makes `z9gb` a corpus entry automatically (Global Constraints) | PROVED | `scripts/corpus/list_corpus_dirs.sh` rule C + `emit_dir` (`<dir>/main.zig` first) |
| 2 | No `scripts/stdlib/expected_dirs.txt` entry needed (Global Constraints) | PROVED | `scripts/stdlib/expected_dirs.txt` contains no `examples/` rows (381 lines, stdlib fixtures only) |
| 3 | Corpus entry "absent before Task 1; after Task 1 appears exactly once" (Task 0 Step 4) | DISPROVED | depth-1 resolution; Task 1 creates no depth-1 `*.zig`; entry appears only after Task 2 |
| 4 | `"$ZIG1" --version` prints a version banner (Task 0 Step 1) | DISPROVED | no `--version` flag; unknown dash-arg becomes `input_file` (`sf/src/main.zig:2167-2168`); `--help` is the supported probe (`main.zig:2068`) |
| 5 | Build recipe `zig1 -ffast -o <dir> …; sh <dir>/build_target.sh linux <out>` (Task 4, spec §8.11) | PROVED | `-o`≡`--output-dir` (README.md:493, `sf/src/main.zig:2054`); emitted script usage `sh build_target.sh [TARGET] [OUT]` with `cd "$(dirname "$0")"` (`sf/src/c89_emit.zig:9752-9755`) |
| 6 | `--dump-c89` + `-o` dump recipe (Tasks 1, 5) | PROVED | QUICK_REF.md:420 (`--dump-c89 --output-dir DIR`); flag family in `sf/src/main.zig:2030-2054` |
| 7 | Exit-77 SKIP convention for missing tools (Task 3 Step 2) | PROVED | `examples/z98/z9torr/tests/tier4_wine.sh:24,42-52`; `/usr/bin/time` SKIP precedent `examples/z98/z9git/tests/tier_git.sh:1769` |
| 8 | 160×144×4 = 92,160 B; pattern words `0x00010000`/`0x00014850`/`0x00018F9F`; offsets 46,400 / 92,156; frame 70,224 T (Task 2 Steps 3-5) | PROVED | recomputed (§5); spec §5.2/§8.6 |
| 9 | Matrix 28/28 over 32 dirs → 29/29 (Task 4 Step 3) | PROVED numerically / INCOMPLETE provenance | 32 subdirs counted; README.md:57,208,519,598 + QUICK_REF.md:570 say 28/28; exclusions list matches `frozen_1124.txt` reconstruction but is not documented policy |
| 10 | `check_win9x_imports.sh` allows KERNEL32/WINMM/WSOCK32/DDRAW/GDI32/USER32; `dsound`/`dinput8` static imports fail the gate (spec §6, echoed implicitly) | PROVED | `scripts/win32_cross/check_win9x_imports.sh` (unknown-DLL FAIL; `msvcrt.dll` banned on 9x) |
| 11 | `LoadLibraryA`/`GetProcAddress` available for dynamic DirectX loading (spec §5.1 strategy) | PROVED | KERNEL32_9X whitelist includes both |
| 12 | `GetAsyncKeyState` keyboard fallback (spec §5.1/§8.4) is gate-compatible | DISPROVED | USER32_ALL whitelist has `GetKeyState` only, not `GetAsyncKeyState` (check_win9x_imports.sh) |
| 13 | Z98 limits: no generics/`anytype`/methods; mandatory `switch` `else`; no tagged-union payload stores; non-wrapping shifts; D16 open (Global Constraints) | PROVED | `docs/reference/Language_Spec_Z98.md:112,131,215,55,463,700,467` |
| 14 | `Platform` fn-pointer fields and `*void` compile in Z98 (Task 1) | PROVED | `Language_Spec_Z98.md:41,20,359`; vtable precedent `:486` |
| 15 | Module-scope `[8 MiB]u8` + `[160*144]u32` statics are legal (Task 0 Step 2) | PROVED (probe covers runtime) | `Language_Spec_Z98.md:703` array-size evaluator window |
| 16 | Existing tier-script patterns under `examples/z98/*/tests/` (Tech Stack) | PROVED | 7 examples carry `tests/` (gfx_demo, z9dbg, z9edit, z9git, z9play, z9torr, z9zstddecomp); SKIP/exit-77 and `/usr/bin/time` patterns exist (fact 7) |
| 17 | `std.os`/`std.io`/`std.file`/`std.time` available (Tech Stack) | PROVED | `sf/src/std_os.zig`, `std_io.zig`, `std_file.zig`, `std_time.zig` exist |
| 18 | `testdata/.gitignore` with `*.gb, *.gbc, *.sav, *.rtc` satisfies spec §5.3 | DISPROVED (as complete) | pattern matches spec list but recursively blocks tracked `testdata/synth/*.gb` that spec §5.3 requires tracked and P2:92 commits; `!expected.txt` negation is dead weight |
| 19 | "Test runs are sequential; spill files collide in one CWD" (Global Constraints) | PROVED | spec §8.11; QUICK_REF.md:288 area (`.zig1_*.tmp` spills left in CWD) |
| 20 | Task 5 dump check "no windows.h/ddraw.h" in Linux dumps | PROVED plausible | Linux target emits no Win32 headers; gate is a grep the executor can run |

## 10. Caveat list (Win9x-focused and general)

1. **`GetAsyncKeyState` vs import whitelist** — spec's DInput8-absent fallback (spec §5.1, §8.4) is not import-gate-legal (check_win9x_imports.sh USER32_ALL). P3 must resolve (whitelist amendment, `GetKeyState`, or `GetProcAddress`) or the fallback will fail the 9x gate.
2. **WINMM whitelist is `waveOut*`-only** — no `timeBeginPeriod`/`timeEndPeriod`. If frame pacing on Win98 ever wants 1 ms timer resolution, the gate script changes (spec currently says QPC+`Sleep` only — keep it that way or plan a whitelist edit).
3. **DX5-era Win98 reality** — `dinput8.dll`/`dsound.dll` are DX8+ components; spec handles fallbacks, but P1's `Platform.audio_fn`/`poll_fn` signatures assume success paths that on real hardware may permanently be in fallback (waveOut / keyboard-only). The table shape is fine; do not let later plans claim DirectInput8/DirectSound8 "on Win98" without the operator's hardware sign-off (spec §5.3 already says hardware sign-off is the operator's).
4. **`.gitignore` blocks synth ROMs** — bare `*.gb` under `testdata/` recursively ignores `testdata/synth/*.gb`, breaking P2's committed synthetic ROM and spec §5.3's "synth ROMs are tracked". Add `!synth/` negation in P1 Task 1.
5. **`EmuConfig`/`EmuError` drift** — spec §11 requires operator approval for public-API changes; the omissions (`dynarec`, `CgbRequired`) will otherwise be silently "added" by P5/P4 mid-stream.
6. **P2 Task 0 depends on a P1 ROM loader that does not exist** — the 8 MiB boundary probe ("Run the P1 loader stub") cannot run; and `Emu` has no ROM buffer though P2 "Consumes: Emu fixed ROM buffer". Either P1 adds a stub `emuLoadRom` (spec §8.2 has it in the facade!) or P2 reorders.
7. **P1 RSS evidence must stay labeled "no-ROM baseline"** — 8 MiB ROM + 1.4 MiB DDraw surface + 1 MiB cache will eat ~10.5 of the 12 MiB budget; a green P1 RSS number proves little about the real target.
8. **`static_bytes=92160` under-reports** — actual P1 static ≈ 188.6 KB (fb + headless snapshot + serial + save_path). Don't propagate the wrong number into P3+ accounting.
9. **Framebuffer content gate is 3 word-checks** — weaker than spec §8.11's "deterministic framebuffer hash". Pin a full-buffer MD5 (repo convention, README.md:190-193).
10. **Corpus gate impact** — once `main.zig` exists, `z9gb` is automatically in the corpus universe (31→32 entries); any dump/gcc warning or failure in `z9gb` now perturbs the corpus gate run. Plan says "must dump and gcc clean" but no step runs the corpus classifier over the new entry.
11. **`stat -c` GNUism / `od -tx4` host endianness** — fine on the pinned Linux host; do not treat the tier scripts as portable POSIX.
12. **Probe path `/tmp/z9gb_seed/zig1_5_clean`** — deviates from the documented `/tmp/z9_seed/zig1_5_clean` (QUICK_REF.md:259 recipe via `scripts/seed/build_from_seed.sh`); harmless but the Task 0 instruction should reference the documented build-from-seed command so the executor isn't left guessing where the binary comes from.

---

## VERDICT

**APPROVE WITH FIXES**

The plan's architecture, layout, table signatures, TDD shape, and arithmetic are sound and spec-aligned. The fixes below are small but must land before execution because two of them break P2 and two are spec-API drift requiring operator approval.

### Caveats / risks by severity

**Critical** — none.

**Important:**
1. `EmuConfig` missing `dynarec: bool` and `EmuError` missing `CgbRequired` (spec §8.2 drift; consumed by P5:202 and P4:76). Spec §11 needs operator approval or exact restoration.
2. `testdata/.gitignore` `*.gb` recursively blocks tracked `testdata/synth/*.gb` (spec §5.3; P2:92 commit will fail). Add `!synth/` negation.
3. Task 0 Step 4 corpus expectation DISPROVED — entry appears after Task 2 (`main.zig`), not Task 1.
4. Task 0 Step 1 `zig1 --version` DISPROVED — use `--help` or a trivial compile.
5. P1 ships no ROM loader/ROM buffer but P2 Task 0 "Runs the P1 loader stub" and "Consumes: `Emu` fixed ROM buffer" — contract hole.
6. Framebuffer content gate (3 word-checks) is weaker than spec §8.11's deterministic framebuffer hash — pin a full-buffer MD5.

**Minor:**
7. `static_bytes=92160` under-reports static (~188.6 KB actual); no stack reporting per spec §5.2.
8. `emuSelfTestPattern` is a public API addition beyond spec §8.2 (operator approval or test-internal).
9. Task 1 Step 1 "appear in the dump" undefined; `platformNoop` has no signature; Task 4 "update every live count" doesn't enumerate the 4 README + 1 QUICK_REF sites.
10. Matrix "four exclusions" attribution undocumented (counts correct: 28→29).
11. Button bit order not restated in the plan.
12. `GetAsyncKeyState`/`timeBeginPeriod` whitelist gaps (P3-era; flagged now per review mandate).

### Top questions for the operator

1. Approve `EmuConfig`/`EmuError` as spec'd (add `dynarec`, `CgbRequired` in P1), or formally amend the spec to defer those members?
2. Should P1 include a size-validating `emuLoadRom` stub (spec §8.2 facade member) so P2 Task 0's 8 MiB probe has a subject — or should P2 Task 0 be reordered after P2 Task 1?
3. Full-buffer MD5 golden for the P1 self-test pattern: commit the expected digest in `tests/`, or compute-and-record only?
4. For P3 planning: resolve the `GetAsyncKeyState` import-gate contradiction now (whitelist amendment vs `GetKeyState` vs dynamic `GetProcAddress`)?
