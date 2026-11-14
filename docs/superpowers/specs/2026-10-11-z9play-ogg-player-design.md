# z9play — OGG Vorbis Music Player — Design

**Status:** Approved (operator, 2026-10-11)
**Goal:** A **native-Z98** OGG Vorbis music player with a **CLI** and a **TUI** frontend, running on **Linux** and **Windows 9x**, that decodes OGG Vorbis in **pure Z98** (no vendored decoder, no C decoder library) and plays it through a small platform audio layer.
**Blueprint:** `examples/z9play.txt` (revision 1).
**Sequence:** Independent example; lives under `examples/z98/z9play/`. Not tied to any compiler plan. Base seed at authoring: v97.

## §1 Scope

**In scope (v1):** single-file OGG Vorbis; native Z98 decode of the three Vorbis headers + audio packets to interleaved signed-16-bit PCM; a shared `Player` core with a double-buffer PCM ring; a CLI frontend; a TUI frontend; an **application-level** platform layer (`platform/audio`, `platform/console`) with Linux and Win9x backends; hermetic tests using generated fixtures + golden PCM.

**Out of scope (v1):** FLAC (optional **M8**); ALSA/Pulse (OSS `/dev/dsp` + a WAV/null sink only); MP3/AAC/Opus; network streaming; playlists persisted to disk; tag editing; mouse; color in the TUI; sample rates other than 44100/48000 (rejected with a clear error); multi-file/chained OGG (rejected).

## §2 Compiler requirements (from blueprint §1)

**Confirmed present and used as-is:** `extern "c" fn`, `@cInclude`, slices `[]T`/`[*]T`, `defer`/`errdefer`, error unions + `try`/`catch`, optionals + `orelse`/`if (o) |v|`, tagged unions `union(enum)` + `switch` (with `else`), function pointers, `@sizeOf`/`@alignOf`/`@offsetOf`/`@bitSizeOf`, `@ptrCast`/`@intCast`/`@bitCast`/`@as`, `@isWindows()`, `std.async`, `std.arena`.

**Moot for this project:** the blueprint's `VERIFY-1` (struct-by-value C ABI) and `VERIFY-2` (function-pointer ABI to C) were framed for a **stb_vorbis** decoder. The operator ruled the decoder is **native Z98**, so no C decoder is linked and these do not gate the decoder. They remain relevant only for the OS externs in §5, which use scalars and small fixed structs (pointer-passed) — verified per the milestone that first calls them (M4 audio, M6/M7 console).

**Deferred/optional:** `VERIFY-3` coroutine frame size — the v1 player core uses **no coroutines** (blueprint §3.3), so this is not a blocker; it returns only if the TUI demonstrates a need. `VERIFY-4` `inline fn` and `VERIFY-5` `@setRuntimeSafety` are nice-to-have, non-blocking.

## §3 Standard library

**Existing (confirmed) and reused:** `std_file` (`open`/`read`/`write`/`seek`/`size`/`readAll`/`exists`/`mtime`; `Mode`; `SeekWhence`; `FileError`), `std_mem`, `std_str`, `std_time` (`ticksMs`/`highRes`), `std_arena`, `std_async`, `std_io.print`, `std_crypto` (SHA-1, for golden PCM hashing), `std_buf`.

**Additions — only where a milestone cannot exist otherwise (operator rule: prefer native Z98; expand std minimally):**
- **`std_math` f64** (`sqrt`, `sin`, `cos`, plus any additional function the decoder needs) — **M2**. Pure Z98 algorithms (ported from fdlibm/musl-style implementations), **no externs**, Win9x-safe, reusable. This mirrors real Zig's approach (Zig implements these without C `libm`).
- **Directory iteration** (`openDir`/`readDir`/`closeDir`) — **M7** only (the TUI browser). Linux `opendir`/`readdir`/`closedir`; Win9x `FindFirstFileA`/`FindNextFileA`/`FindClose`. Exact API decided in the M7 plan.

**Deliberately NOT added to std:** `std.fmt.bufPrint` — the CLI/TUI format with a **player-local minimal formatter** (integers + fixed strings) rather than growing std; revisit only if M5 shows a genuine need. C-string bridges (`span`/`toCStr`) — avoided by staying native; `std_str.copyZ` covers the few NUL-terminated OS-API arguments.

## §4 Player core (shared by CLI and TUI)

A library that knows nothing about display. One job: decode the next chunk when the ring has room, and expose state.

- **State:** `PlayerState = enum(u8) { stopped, playing, paused, ended, error_state }`; fields per blueprint §3.1 (`decoder`, `audio`, `arena`, `ring`, `state`, `volume`, `position_ms`, `started_ms`, `duration_ms`, `sample_rate`, `channels`, optional `title`/`artist`/`album`).
- **Ring buffer:** 2 × 0.5 s @ 44.1 kHz stereo s16 = **176,400 bytes**, allocated from the player arena. Because OSS/`waveOut` consume synchronously, v1 is a **double buffer** (naming stays "ring" for future flexibility).
- **No coroutines in v1:** a blocking loop — decode into the ring; when full, write to audio (blocks until consumed); poll input non-blockingly between writes.
- **Position:** `position_ms` derived from samples written ÷ (sample_rate × channels); pause records an offset and resets `started_ms` on resume.

## §5 Frontends and the platform layer

**`platform/audio`** (app-level vtable, blueprint §2.2): `open_fn`/`write_fn`/`close_fn`/`drain_fn` + `state`. Backends: Linux **OSS `/dev/dsp`** and a **null/WAV-file sink** (hermetic tests); Win9x **`waveOut*`**.
**`platform/console`** (app-level vtable): `clear_fn`/`setCursor_fn`/`writeStr_fn`/`readKey_fn`/`enterRaw_fn`/`leaveRaw_fn`/`width_fn`/`height_fn`/`cursorShow_fn` + `state` (the `cursorShow_fn` operation is the 2026-10-16 M5b extension). Backends: Linux **termios + ANSI**; Win9x **`SetConsoleCursorPosition`/`ReadConsoleInput`/`SetConsoleMode`**.

The vtables live under `examples/z98/z9play/platform/` (not std), so they can be tested with mock backends and reused by other programs.

**CLI** (blueprint §4): `z9play <file.ogg> [--volume N|--start SEC|--loop|--quiet|--version|--help]`; one startup metadata line; per-second `\r` status `00:42 / 03:15  vol 80%  [####----]` unless `--quiet`; exit codes 0 ok / 1 arg / 2 open / 3 decoder / 4 audio / 5 internal; keys space / `+` / `-` / `q` / Ctrl-C.
**TUI** (blueprint §5): directory pane + now-playing pane + status bar (80×25); playlist in memory (v1); needs `Console` positioning, screen clear, non-echoed keys, and `std.fs` directory iteration.

## §6 Milestones

Each milestone is a separate plan. Milestone boundaries follow the blueprint's staging but split it into testable, independently reviewable units. **Every milestone plan ends with a task that reviews the NEXT milestone's plan for required amendments.**

| M | Plan | Deliverable | Gate |
|:--|:--|:--|:--|
| **M0** | `2026-10-11-z9play-m0-ogg-container-plan.md` | OGG container pages + packet reassembly; Vorbis id + comment headers; `z9play --info` (rate/channels/tags/duration) | `tests/tier_info.sh` green (metadata vs golden) |
| **M1** | `2026-10-11-z9play-m1-setup-codebooks-plan.md` | setup header parse + codebook construction; `z9play --dump-setup` | `tests/tier_setup.sh` green (codebook invariants) |
| **M2** | `2026-10-11-z9play-m2-native-math-plan.md` | `std_math` f64 `sqrt`/`sin`/`cos` (pure Z98; no externs) | `verify_stdlib` green + `tests/tier_math.sh` vs known identities |
| **M3** | `2026-10-11-z9play-m3-audio-decode-plan.md` | floor1/residue/mapping/MDCT/overlap-add → PCM; `z9play --pcm out.wav` + SHA-1 | `tests/tier_decode.sh` green (PCM SHA-1 vs `vorbis-tools` golden) |
| **M4** | `2026-10-11-z9play-m4-audio-out-plan.md` | audio vtable + OSS + WAV/null sink; `Player` core + ring buffer | `tests/tier_audio.sh` green (WAV sink bytes == golden) |
| **M5** | `2026-10-11-z9play-m5-cli-plan.md` | CLI frontend (status line, keys, exit codes) on Linux | `tests/tier_cli.sh` green |
| **M6** | `2026-10-11-z9play-m6-win9x-plan.md` | Win9x audio (`waveOut`) + console; Wine smoke | `tests/tier_win9x.sh` green (Wine + PARITY) |
| **M7** | `2026-10-11-z9play-m7-tui-plan.md` | `std.fs` directory iteration + `Console` vtable + TUI | `tests/tier_tui.sh` green |
| **M8** | `2026-10-11-z9play-m8-flac-plan.md` | *(optional)* FLAC decoder behind the decoder vtable | `tests/tier_flac.sh` green |

Sequence: M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7 → (M8 optional).

## §7 Risks

1. **No float math in Z98** (`std_math` integer-only; no `@sqrt`/`@sin`/`@cos`) — mitigated by native `std_math` f64 in **M2** (pure algorithms, no externs).
2. **Native Vorbis decode complexity** (codebooks, floor1, residue, mapping/coupling, MDCT, overlap-add) — staged: container → setup/codebooks → math → decode; each gated by golden PCM.
3. **No audio device in CI** — the OSS backend is host-dependent; the **WAV/null sink** is the hermetic gate.
4. **Win9x console codepage** — v1 sanitizes metadata to ASCII on Win9x; UTF-8 later.
5. **Sample rate ∉ {44100, 48000}** — rejected in v1 with a clear error.
6. **OS extern ABI** (audio/console) — scalar/small-struct pointer calls; verified in the milestone that first calls them.
7. **Win9x raw console left set on crash** — restore mode in `defer` + an exit/console-control handler.

## §8 Out of scope

As §1 deliberately. Additionally: no C decoder linked; no vendored third-party source (fixtures are *generated* by `vorbis-tools`, not linked); no compiler changes without an explicit operator amendment (the only anticipated compiler-adjacent work is the **std** additions in M2/M7).

## §9 Milestone index and the amendment rule

The milestone table in §6 is authoritative. **Each milestone plan MUST contain a final task "Next-milestone amendment review"** whose job is to: (1) read the next milestone's plan; (2) judge whether the current milestone's implementation invalidates any assumption in it (API shape, std additions, data layout, build recipe, gate); (3) if so, STOP and present the required amendment to the operator before that milestone executes; (4) if not, record "no amendment needed". This keeps the multi-milestone plan honest as the earlier stages reveal reality.
