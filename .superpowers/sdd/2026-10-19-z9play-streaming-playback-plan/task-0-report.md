# M9 Task 0 report — preflight (report-only)

**Status:** READY — no STOP condition.

**Base:** branch `zig1_improvements`, HEAD `3c9659ddc43fbf01c33dac0543c33612366d7287`
(`docs(plan): M9 precision — stream FLAC selector and buffered-file close semantics`).

**Seed:** `/tmp/m7_t5_seed2/zig1_5_clean`
(md5 `b299b4b435e624d0ddbd2edde681cbc3`, seed v102 fixed point).

**Scope:** report-only. No source, plan, spec, compiler, stdlib, or seed edits.
All probes/builds/tier runs used `/tmp`. `git status --short` after the work was
only the pre-existing untracked `lin_bin/` and `run.err`.

**Authorities:** `task-0-brief.md`, M9 plan lines 43–57, M9 spec lines 1–244.

Two brief wording points resolved without changing the work:

- The brief says “both `FILE_ARENA_SIZE` declarations”. The tree has exactly one
  symbol named `FILE_ARENA_SIZE` (`examples/z98/z9play/ui.zig:38`); the other
  4 MiB media-file arena is the unnamed `arena_buf`
  (`examples/z98/z9play/main.zig:78`). Both are recorded in §5.
- The brief says “from `repro`/testdata”. The repository-root `repro/` contains
  **zero** `.ogg`/`.flac`/`.wav`/`.pcm` media files; all committed media fixtures
  are under `examples/z98/z9play/testdata/`. The census in §4 covers every
  committed OGG fixture there. (`lin_bin/` was not read or touched.)

---

## 1. `std_file` reality check

### 1.1 Public surface (as implemented)

| Item | Anchor | Observed shape |
|---|---|---|
| `FileError` | `sf/src/std_file.zig:35` | includes `OpenFailed`, `ReadFailed`, `SeekFailed`, `SizeFailed`, `OutOfMemory` |
| `Mode` | `sf/src/std_file.zig:37` | `Read`, `Write`, `Append`, `ReadWrite` |
| `SeekWhence` | `sf/src/std_file.zig:38` | `Set`, `Cur`, `End` |
| `File` | `sf/src/std_file.zig:42-46` | `handle: *void`, `size_cache: i64`, `arena: *Arena` |
| `open` | `sf/src/std_file.zig:319-322` | `open(arena, path, Mode) FileError!File` |
| `close` | `sf/src/std_file.zig:324-326` | `close(*File) void` |
| `read` | `sf/src/std_file.zig:328-330` | `read(*File, []u8) FileError!usize` |
| `seek` | `sf/src/std_file.zig:336-341` | `seek(*File, i64, SeekWhence) FileError!i64` |
| `size` | `sf/src/std_file.zig:343-347` | `size(*File) FileError!i64` |
| `readAll` | `sf/src/std_file.zig:405-431` | whole-file allocation + read loop |

The seed’s stdlib copy is byte-identical to the repository copy:

```
$ md5sum sf/src/std_file.zig /tmp/m7_t5_seed2/lib/std_file.zig
35e1ceb15ef35686a8db6aafcfb5cdb2  sf/src/std_file.zig
35e1ceb15ef35686a8db6aafcfb5cdb2  /tmp/m7_t5_seed2/lib/std_file.zig
$ cmp -s sf/src/std_file.zig /tmp/m7_t5_seed2/lib/std_file.zig; echo $?
0
```

### 1.2 Semantics Task 1 depends on

- **Open:** POSIX opens `O_RDONLY | O_LARGEFILE` (`sf/src/std_file.zig:167`);
  `O_LARGEFILE` is `0100000` (`sf/src/std_file.zig:75-77`). Win32 uses
  `CreateFileA` (`sf/src/std_file.zig:151-165`). `open` stores the caller arena
  but does not allocate (`sf/src/std_file.zig:319-322`).
- **Read:** one OS read per call (`sf/src/std_file.zig:185-196`). It returns the
  OS count; `0` means EOF, and a short count is returned verbatim. `readAll`
  loops on it and stops at `r == 0`, returning `raw[0..got]`
  (`sf/src/std_file.zig:420-430`).
- **Seek:** POSIX uses the `_llseek` syscall and a full 64-bit split of the
  `i64` offset (`sf/src/std_file.zig:217-231`, `233-244`). i386’s 32-bit
  `off_t` is therefore not the limit. Win32 uses `pal_file_seek64`
  (`sf/src/std_file.zig:233-237`). The public argument is `i64`.
- **Size:** POSIX queries current and end offsets, then restores the current
  offset (`sf/src/std_file.zig:246-265`). It writes `File.size_cache` but does
  **not** read that cache on later calls (`sf/src/std_file.zig:343-347`).
- **Close:** no idempotence check in `std_file`; `close` unconditionally calls
  the OS close (`sf/src/std_file.zig:324-326`). The spec’s idempotent close must
  therefore be implemented by `stream.BufferedFile` with its `closed` field
  (spec lines 68-70, 83).
- **`readAll`:** allocates the exact file size (`sf/src/std_file.zig:415-419`).
  That is the 4 MiB-arena failure described in the M9 spec lines 9-13: a
  `readAll` of a file larger than the arena returns `OutOfMemory`, and a
  premature `0` read would silently return a shorter slice
  (`sf/src/std_file.zig:421-430`).

### 1.3 Planned APIs that do not exist yet

`examples/z98/z9play/stream.zig`, `examples/z98/z9play/ogg_stream.zig`, the
`OGG_PAGE_MAX`/`OGG_PACKET_MAX` constants, and `flac.StreamFlacDecoder` are
absent:

```
$ ls examples/z98/z9play/stream.zig examples/z98/z9play/ogg_stream.zig
ls: cannot access 'examples/z98/z9play/stream.zig': No such file or directory
ls: cannot access 'examples/z98/z9play/ogg_stream.zig': No such file or directory
```

This is expected: they are Tasks 1–3 deliverables. The primitives they need are
present: `std_file` (above), the existing page parser/CRC
(`examples/z98/z9play/ogg.zig:50-74`, `140-147`), and the byte-slice FLAC
oracle (`examples/z98/z9play/flac.zig:488-565`).

---

## 2. >4 MiB `std_file` probe

### 2.1 Input and identity

```
$ dd if=/dev/zero of=/tmp/m9_t0_big.bin bs=1048576 count=8 status=none
$ stat -c '%n %s bytes' /tmp/m9_t0_big.bin
/tmp/m9_t0_big.bin 8388608 bytes
$ md5sum /tmp/m9_t0_big.bin
96995b58d4cbf6aaa9041b4f00c7f6ae  /tmp/m9_t0_big.bin
$ md5sum /tmp/m7_t5_seed2/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed2/zig1_5_clean
$ gcc --version | head -1
gcc (Debian 12.2.0-14+deb12u1) 12.2.0
```

The probe imports the seed’s `std_file` module and links through the emitted
binding recipe. It reads 65,536-byte blocks, seeks with a `u64` converted to
`i64`, and never calls `readAll`.

### 2.2 Exact commands

```
$ rm -rf /tmp/m9_t0_probe_out && mkdir -p /tmp/m9_t0_probe_out
$ timeout 300 /tmp/m7_t5_seed2/zig1_5_clean -fsafe \
    -o /tmp/m9_t0_probe_out /tmp/m9_t0_probe.zig
$ sh /tmp/m9_t0_probe_out/build_target.sh linux /tmp/m9_t0_probe_out/prog
$ /tmp/m9_t0_probe_out/prog
```

`zig` rc=0, `build_target.sh` rc=0, probe rc=0. Host: `x86_64`; emitted binary
is `ELF 32-bit LSB pie executable, Intel 80386`.

### 2.3 Exact output

```
open=OK
size=8388608
read_start_65536=65536
seek_u64_gt4m=4206649
read_after_seek_65536=65536
seek_tail=8388598
read_tail_100=10
seek_eof=8388608
read_at_eof_100=0
seek_u64_2pow32=4294967296
size_after_huge_seek=8388608
close=OK
```

### 2.4 Interpretation

- A file **8,388,608 bytes** (>4 MiB) opens, reports its exact size, and can be
  read from the start and from offsets above 4 MiB
  (`seek_u64_gt4m=4206649`, `read_after_seek_65536=65536`).
- Reads before EOF filled the requested 65,536 bytes. At 10 bytes remaining a
  100-byte read returned exactly 10; at EOF it returned 0. No other short read
  occurred for this regular file.
- A `u64` value **4,294,967,296** (2³², above the 32-bit range) converted to
  `i64` and sought successfully (`seek_u64_2pow32=4294967296`), and a later
  `size` still reported 8,388,608 (the size query’s CUR/END/restore path works
  after a huge seek).
- **STOP condition not triggered**: `std_file` can read, seek, and size a
  >4 MiB file on seed v102.

Caveat for Task 1: `std_file.read` performs one OS read and does not itself
guarantee a full fill. `BufferedFile` must treat any short count as “refill /
continue until `out` is full or true EOF”, exactly as M9 spec lines 82–83
require. The probe establishes that a regular-file read in this environment
fills normally and is short only at EOF.

Probe source is reproduced in Appendix A.

---

## 3. Call-site census

### 3.1 Production media call sites (exhaustive)

Search terms: `filemod.readAll`, `ogg.reassemble`, `ogg.lastGranule`,
`flac.open`, `flac.decode`, `player.vorbisCreate`, `decoder.detectKind`.

| Symbol | Call site | Mode / path | Note |
|---|---|---|---|
| `filemod.readAll` | `examples/z98/z9play/main.zig:303` | all CLI modes | reads the entire media file into `arena` |
| `filemod.readAll` | `examples/z98/z9play/ui.zig:487` | TUI `playTrack` | reads the entire media file into `g_file_arena` |
| `ogg.reassemble` | `examples/z98/z9play/main.zig:325` | every non-FLAC mode | copies every packet into `arena` |
| `ogg.reassemble` | `examples/z98/z9play/ui.zig:507` | TUI OGG | copies every packet into `g_file_arena` |
| `ogg.lastGranule` | `examples/z98/z9play/main.zig:439` | `--pcm` | trim to audio granule |
| `ogg.lastGranule` | `examples/z98/z9play/main.zig:518` | `--wav` OGG | duration/trim |
| `ogg.lastGranule` | `examples/z98/z9play/main.zig:652` | interactive OGG, metadata | duration |
| `ogg.lastGranule` | `examples/z98/z9play/main.zig:808` | interactive OGG, per-loop decode | duration |
| `ogg.lastGranule` | `examples/z98/z9play/main.zig:972` | `--info` | duration |
| `ogg.lastGranule` | `examples/z98/z9play/ui.zig:523` | TUI OGG | duration |
| `flac.open` | `examples/z98/z9play/main.zig:489` | `--wav` FLAC | slices the whole file |
| `flac.open` | `examples/z98/z9play/main.zig:630` | interactive FLAC metadata | slices the whole file |
| `flac.open` | `examples/z98/z9play/main.zig:794` | interactive FLAC per-loop decode | slices the whole file |
| `flac.open` | `examples/z98/z9play/ui.zig:499` | TUI FLAC | slices the whole file |
| `flac.decode` | `examples/z98/z9play/decoder.zig:75` | `flacNext` adapter | only production call; used by `--wav`, interactive, TUI via `decoderOpenFlac` |
| `player.vorbisCreate` | `examples/z98/z9play/main.zig:524` | `--wav` OGG | passes `packets` array and `first_packet=3` |
| `player.vorbisCreate` | `examples/z98/z9play/main.zig:812` | interactive OGG, per-loop | passes `packets` array and `first_packet=3` |
| `player.vorbisCreate` | `examples/z98/z9play/ui.zig:535` | TUI OGG | passes `packets` array and `first_packet=3` |
| `decoder.detectKind` | `examples/z98/z9play/main.zig:310` | all CLI modes | `data` is the whole-file slice |
| `decoder.detectKind` | `examples/z98/z9play/ui.zig:491` | TUI | `data` is the whole-file slice |

Related selector call sites (not separately requested, but they carry the
same media contexts):

- `decoder.decoderOpenFlac`: `main.zig:497`, `main.zig:798`, `ui.zig:505`.
- `decoder.decoderOpenVorbis`: `main.zig:532`, `main.zig:816`, `ui.zig:542`.

### 3.2 Definitions / anchors

| Symbol | Definition anchor | Current behavior relevant to M9 |
|---|---|---|
| `ogg.pageAt` | `examples/z98/z9play/ogg.zig:50-74` | parses one in-memory page; `Page.body_start`/`body_len` are `u32` |
| `ogg.nextPage` | `examples/z98/z9play/ogg.zig:77-80` | in-memory page advance |
| `ogg.crcOk` | `examples/z98/z9play/ogg.zig:140-147` | OGG CRC over page with CRC field zeroed |
| `ogg.reassemble` | `examples/z98/z9play/ogg.zig:157-221` | two passes; allocates `[]Packet` (`185-186`) and a full packet blob (`187`) |
| `ogg.lastGranule` | `examples/z98/z9play/ogg.zig:252-277` | full-file scan; arena argument currently unused (`253`) |
| `ogg.durationMs` | `examples/z98/z9play/ogg.zig:240-243` | granule → ms |
| `flac.FlacDecoder` | `examples/z98/z9play/flac.zig:37-49` | owns `data: []const u8` (whole file) |
| `flac.open` | `examples/z98/z9play/flac.zig:488-558` | slices `bytes`, parses metadata, allocates `samples` (`540`) |
| `flac.decode` | `examples/z98/z9play/flac.zig:562-565` | byte-slice `decodeFrame` |
| `flac.BitReader` | `examples/z98/z9play/flac.zig:52-56` | byte-slice MSB-first reader |
| `player.VorbisCtx` | `examples/z98/z9play/player.zig:290-302` | holds `packets: []ogg.Packet` and `next_packet` |
| `player.vorbisCreate` | `examples/z98/z9play/player.zig:309-336` | stores the packet array; `first_packet` cursor |
| `player.vorbisNext` | `examples/z98/z9play/player.zig:341-359` | resets scratch per packet (`347`), decodes `packets[idx]` (`348`) |
| `player.playerInit` | `examples/z98/z9play/player.zig:135-174` | ring + block scratch allocated from player arena (`140-146`) |
| `decoder.detectKind` | `examples/z98/z9play/decoder.zig:46-56` | 4-byte signature; requires `data.len >= 4` |
| `decoder.decoderOpenVorbis` | `examples/z98/z9play/decoder.zig:61-70` | fills caller-owned `*player.Decoder` (D8 discipline) |
| `decoder.flacNext` | `examples/z98/z9play/decoder.zig:73-80` | calls byte-slice `flac.decode` |
| `decoder.decoderOpenFlac` | `examples/z98/z9play/decoder.zig:84-93` | takes `*flac.FlacDecoder` (currently byte-slice) |

### 3.3 Test-only oracle call sites (allowed by the M9 plan)

These are not production media paths; Tasks 2–3 keep them as oracles. Listed so
the census is exhaustive.

- `filemod.readAll`: `tests/audio_test.zig:101`; `tests/decode_test.zig:101,105`;
  `tests/flac_test.zig:86,90`; `tests/floor_test.zig:118`;
  `tests/info_test.zig:69,122`; `tests/ogg_test.zig:72,87,223`;
  `tests/player_test.zig:87,179,234,238,269`;
  `tests/setup_test.zig:83,266,302`.
- `ogg.reassemble`: `tests/decode_test.zig:109`; `tests/floor_test.zig:122`;
  `tests/info_test.zig:73,126`; `tests/ogg_test.zig:95,175,211,249`;
  `tests/player_test.zig:91,183`; `tests/setup_test.zig:87,270,306`.
- `ogg.lastGranule`: `tests/ogg_test.zig:91`; `tests/player_test.zig:111,213`.
- `flac.open`: `tests/flac_test.zig:95`.
- `flac.decode`: `tests/flac_test.zig:108`.
- `player.vorbisCreate`: `tests/player_test.zig:116`.
- `decoder.detectKind`: none.

### 3.4 Mode-by-mode summary

- `--info` (`main.zig:966-1002`): whole-file `data` → `readAll` (`303`),
  `reassemble` (`325`), `lastGranule` (`972`), comment parse (`966`).
- `--dump-setup` (`main.zig:346-377`): whole-file `data` → `readAll` (`303`),
  `reassemble` (`325`), `parseSetup` from packet 2 in `arena` (`353`).
- `--pcm` (`main.zig:379-468`): whole-file `data` → `readAll` (`303`),
  `reassemble` (`325`), `lastGranule` (`439`); additionally allocates the full
  decoded PCM (`frames_cap * ch`, `401-419`) and the full output WAV buffer
  (`443-451`) in `darena`.
- `--wav` (`main.zig:475-605`): whole-file `data` → `readAll` (`303`);
  `flac.open` (`489`) or `lastGranule` (`518`) + `vorbisCreate` (`524`).
- Interactive play (`main.zig:615-964`): whole-file `data` → `readAll` (`303`);
  FLAC `flac.open` (`630`, `794`) or `lastGranule` (`652`, `808`) +
  `vorbisCreate` (`812`); loop resets `darena`/`scratch`/`par` (`787-789`).
- TUI (`ui.zig:479-591`): `readAll` (`487`) → `detectKind` (`491`) →
  `flac.open` (`499`) or `reassemble` (`507`) + `lastGranule` (`523`) +
  `vorbisCreate` (`535`).

---

## 4. OGG fixture page and packet census

### 4.1 Command

```
$ python3 - <<'PY'
import glob, os
files = sorted(glob.glob('examples/z98/z9play/testdata/*.ogg'))
all_max_page = 0
all_max_pkt = 0
for path in files:
    data = open(path, 'rb').read()
    i = 0
    pages = 0
    page_sizes = []
    packets = []
    cur = bytearray()
    while i < len(data):
        assert data[i:i+4] == b'OggS', (path, i)
        nseg = data[i+26]
        segs = data[i+27:i+27+nseg]
        body = i+27+nseg
        size = 27+nseg+sum(segs)
        page_sizes.append(size)
        off = body
        for s in segs:
            cur += data[off:off+s]
            off += s
            if s < 255:
                packets.append(len(cur))
                cur = bytearray()
        i = body + sum(segs)
        pages += 1
    assert i == len(data), (path, i, len(data))
    assert not cur, (path, len(cur))
    mx_page = max(page_sizes)
    mn_page = min(page_sizes)
    mx_pkt = max(packets)
    all_max_page = max(all_max_page, mx_page)
    all_max_pkt = max(all_max_pkt, mx_pkt)
    print(f"{os.path.basename(path)}: bytes={len(data)} pages={pages} page_min={mn_page} page_max={mx_page} packets={len(packets)} packet_max={mx_pkt}")
print(f"ALL: page_max={all_max_page} packet_max={all_max_pkt}")
print(f"OGG_PAGE_MAX={27+255+65025} OGG_PACKET_MAX={1024*1024}")
print(f"page_ok={all_max_page <= 27+255+65025} packet_ok={all_max_pkt <= 1024*1024}")
PY
```

### 4.2 Exact output

```
short.ogg: bytes=4141 pages=3 page_min=58 page_max=3298 packets=18 packet_max=3189
sine_mono_44100.ogg: bytes=5223 pages=3 page_min=58 page_max=3298 packets=48 packet_max=3189
sine_stereo_44100.ogg: bytes=10781 pages=4 page_min=58 page_max=4221 packets=91 packet_max=3832
sine_stereo_48000.ogg: bytes=8224 pages=3 page_min=58 page_max=4222 packets=53 packet_max=3832
tagged_unicode.ogg: bytes=7619 pages=3 page_min=58 page_max=4013 packets=48 packet_max=3832
ALL: page_max=4222 packet_max=3832
OGG_PAGE_MAX=65307 OGG_PACKET_MAX=1048576
page_ok=True packet_ok=True
```

### 4.3 Conclusions

- The largest committed page is **4,222 bytes**. The theoretical maximum
  `27 + 255 + 65025 = 65,307` (spec line 44; plan line 85) is 15.5× larger; the
  planned 65,536-byte page buffer covers it with 229 bytes to spare.
- The largest committed Vorbis packet is **3,832 bytes**. The planned 1 MiB
  (`1,048,576`-byte) packet cap is **273.6×** larger. **STOP condition not
  triggered**: no committed packet is anywhere near 1 MiB.
- Note: `OGG_PAGE_MAX` / `OGG_PACKET_MAX` do not yet exist in source; they are
  Task 2 constants. The current parser has no page-size constant and uses
  `u32` body offsets (`ogg.zig:21-28`), which is ample for 65,307-byte pages.

---

## 5. File arenas and media-byte ownership

### 5.1 Declarations

| Arena buffer | Declaration | Size | Arena init | Used for media bytes? |
|---|---|---:|---|---|
| `arena_buf` | `examples/z98/z9play/main.zig:78` | 4 MiB | `main.zig:302` | **yes** — `readAll` whole file (`303`), `reassemble` packet array + blob (`325`; `ogg.zig:185-187`), comment/tag copies (`966`, `646`), `parseSetup` in `--dump-setup` (`353`) |
| `dec_arena_buf` | `examples/z98/z9play/main.zig:84` | 16 MiB | `main.zig:386`, `480`, `618` | **yes, media-scaled** — `--pcm` full PCM (`413`) and full WAV (`445`); setup/state/ctx in `--wav`/play (`506-524`, `800-812`); FLAC decoder struct + `samples` scratch (`489`, `794`); the FLAC `data` slice itself points at the 4 MiB `arena` buffer |
| `wav_scratch_buf` | `examples/z98/z9play/main.zig:90` | 8 MiB | `main.zig:481`, `619` | decoder scratch; reset per packet (`player.zig:347`); bounded |
| `wav_player_buf` | `examples/z98/z9play/main.zig:91` | 2 MiB | `main.zig:482`, `620` | Player ring + block (`player.zig:140-146`); bounded |
| `g_file_buf` (`FILE_ARENA_SIZE`) | `examples/z98/z9play/ui.zig:38`, buffer `45` | 4 MiB | `ui.zig:1038` | **yes** — `readAll` (`487`), `reassemble` (`507`), `lastGranule` (`523`), comment (`519`) |
| `g_dec_buf` | `examples/z98/z9play/ui.zig:39`, buffer `46` | 16 MiB | `ui.zig:1039` | **yes** — FLAC decoder (`499`), setup/state (`527-531`), `vorbisCreate` (`535`) |
| `g_scratch_buf` | `examples/z98/z9play/ui.zig:40`, buffer `47` | 8 MiB | `ui.zig:1040` | decoder scratch; per-packet reset (`player.zig:347`) |
| `g_player_buf` | `examples/z98/z9play/ui.zig:41`, buffer `48` | 2 MiB | `ui.zig:1041` | Player ring + block (`571`) |
| `g_ui_buf` | `examples/z98/z9play/ui.zig:36`, buffer `43` | 1 MiB | `ui.zig:1036` | no — path/playlist copies (`617`) |
| `g_dir_buf` | `examples/z98/z9play/ui.zig:37`, buffer `44` | 1 MiB | `ui.zig:1037` | no — directory listing (`331-350`) |

Both 4 MiB file arenas are used only as backing stores: the TUI arena is reset
per track (`ui.zig:482`), and the CLI arena is initialized once at process start
(`main.zig:302`). Resetting does not make the allocation size file-independent:
`readAll` always requests the whole file size from them
(`std_file.zig:415-419`).

### 5.2 Media-scaled allocations to remove (beyond `readAll`)

- `ogg.reassemble` allocates `count * @sizeOf(Packet)` plus the total packet
  blob (`ogg.zig:185-187`), so it scales with track duration even after the
  file bytes are streamed.
- `--pcm` allocates `frames_cap = audio_count * (n1/2)` samples
  (`main.zig:400-419`) and a `44 + data_bytes` WAV buffer (`main.zig:443-451`).
  Removing `readAll` alone would **not** bound `--pcm`; Task 4 must stream both.
- `flac.FlacDecoder.data` is the full-file slice (`flac.zig:38`, set at `546`);
  `flac.open` never copies, but it keeps the whole file alive. The streaming
  path must not wrap this type (spec §4.4; plan Task 3 lines 103-111).

### 5.3 Non-media arena users

`g_ui_arena` and `g_dir_arena` (`ui.zig:50-51`) hold paths/playlist/listing
copies, not media bytes. `main.zig`’s `g_mix_buf` (`main.zig:109`) and
`ui.zig`’s `g_mix_buf` (`ui.zig:82`) are fixed 88,200-`i16` mixer buffers, not
arenas.

---

## 6. Baseline tiers and dump pins

The values in the brief were independently re-run on seed v102. Every run
exited 0.

### 6.1 Commands

```
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/m9_t0_tier_info timeout 600 sh examples/z98/z9play/tests/tier_info.sh
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/m9_t0_tier_setup timeout 600 sh examples/z98/z9play/tests/tier_setup.sh
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/m9_t0_tier_cli timeout 600 sh examples/z98/z9play/tests/tier_cli.sh
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/m9_t0_tier_audio timeout 600 sh examples/z98/z9play/tests/tier_audio.sh
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/m9_t0_tier_tui timeout 1200 sh examples/z98/z9play/tests/tier_tui.sh
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/m9_t0_tier_flac timeout 1200 sh examples/z98/z9play/tests/tier_flac.sh
```

### 6.2 Results (observed)

```
== tier_info summary: 20 passed, 0 failed ==
TIER_INFO PASS
== tier_setup summary: 21 passed, 0 failed ==
TIER_SETUP PASS
== tier_cli summary: 23 passed, 0 failed ==
TIER_CLI PASS
== tier_audio summary: 27 passed, 0 failed ==
TIER_AUDIO PASS
== tier_tui summary: 40 passed, 0 failed ==
TIER_TUI PASS
== tier_flac summary: 59 passed, 0 failed ==
TIER_FLAC PASS
```

Recorded baseline (matches the brief and `examples/z98/z9play/NOTES.md`):

| Gate | Baseline | Historical citation |
|---|---:|---|
| `tier_info` | 20/0 | `NOTES.md:368`; summary emitted at `tests/tier_info.sh:111` |
| `tier_setup` | 21/0 | `NOTES.md:395`; `tests/tier_setup.sh:114` |
| `tier_cli` | 23/0 | `NOTES.md:738`; `tests/tier_cli.sh:281` |
| `tier_tui` | 40/0 | `NOTES.md:953`, `NOTES.md:965`; `tests/tier_tui.sh:497` |
| `tier_audio` | 27/0 | `NOTES.md:630`; `tests/tier_audio.sh:218` |
| `tier_flac` | 59/0 | `NOTES.md:1000`; `tests/tier_flac.sh:655` |

### 6.3 Dump pins (observed)

```
$ timeout 600 /tmp/m7_t5_seed2/zig1_5_clean --dump-c89 examples/z98/z9play/main.zig > /tmp/m9_t0_dump/main.c89
$ md5sum /tmp/m9_t0_dump/main.c89
e56af7916edd199e796f3ef11d5e49c4  /tmp/m9_t0_dump/main.c89
$ timeout 600 /tmp/m7_t5_seed2/zig1_5_clean --dump-c89 examples/z98/z9play/ui.zig > /tmp/m9_t0_dump/ui.c89
$ md5sum /tmp/m9_t0_dump/ui.c89
22676fd997471df1c4c3a3f04397121d  /tmp/m9_t0_dump/ui.c89
```

`tier_cli`, `tier_tui`, and `tier_flac` independently printed the same two pins.
Recorded baseline (M8 T4, `NOTES.md:9`):

- `main.zig` Linux `--dump-c89` = `e56af7916edd199e796f3ef11d5e49c4`
- `ui.zig` Linux `--dump-c89` = `22676fd997471df1c4c3a3f04397121d`

Both are stable across the tier runs on seed v102
(`b299b4b435e624d0ddbd2edde681cbc3`).

---

## 7. Readiness and STOP conditions

No STOP condition occurred:

- `std_file` reads, seeks, and sizes an 8,388,608-byte file on seed v102, with
  `u64`→`i64` offsets above 4 MiB and above 2³² (§2).
- No committed Vorbis packet exceeds 1 MiB; the maximum is 3,832 bytes (§4).
- All six tier baselines are green and both dump pins match M8 T4 (§6).
- No source/seed/compiler/stdlib change was made.

**Task 0 is READY for Task 1.**

---

## 8. Concerns for the implementer/controller

These are implementation risks, not STOP conditions.

1. **`BufferedFile` must not equate a short read with EOF.** `std_file.read`
   is a single OS read (`std_file.zig:185-196`); the spec’s `bufferedFileRead`
   must keep refilling until `out` is full or the file is exhausted
   (spec lines 82–83). `readAll`’s `if (r == 0) break` pattern
   (`std_file.zig:426`) is not a safe model.
2. **`std_file.close` is not idempotent** (`std_file.zig:324-326`). The stream
   type must implement the spec’s `closed` guard (spec line 69) or a double
   close will close a reused fd.
3. **`File.size_cache` is written but never consulted.** `size` always performs
   the POSIX CUR/END/restore seek sequence (`std_file.zig:246-265`,
   `343-347`). `bufferedFileSize` should call it once at open or accept the
   repeated syscalls; do not assume the field is a cache.
4. **`size` moves the file offset and restores it.** It restores via the saved
   current offset (`std_file.zig:253-263`). `BufferedFile` must not interleave
   `size` with a pending buffered cursor; call size before `start/len/pos` are
   populated.
5. **`--pcm` remains file-scaled after `readAll` removal.** The current
   `big` PCM buffer (`main.zig:401-419`) and whole-WAV buffer (`443-451`) are
   sized from packet count/output size. Task 4’s plan already requires
   streaming these (`plan:126`, `134`); preflight confirms both allocations
   exist today.
6. **`ogg.reassemble` still scales with duration.** Even with a streaming
   frontend, any remaining production call would allocate the packet array and
   blob (`ogg.zig:157-221`). The census found only `main.zig:325` and
   `ui.zig:507`; both must be removed, with test uses retained as oracles.
7. **`ogg.lastGranule` does a full-file scan** (`ogg.zig:252-277`). All six
   production sites in §3.1 must move to the tail-only `oggStreamLastGranule`;
   note its current arena parameter is unused (`253`).
8. **FLAC selector still points at the byte-slice oracle.** `flacNext` calls
   `flac.decode(fd, fd.arena, ...)` (`decoder.zig:73-80`), and
   `decoderOpenFlac` takes `*flac.FlacDecoder` (`84-93`). Task 3 must add the
   streaming type and repoint the selector without violating D8’s caller-owned
   `*player.Decoder` rule.
9. **TUI lifetime:** `g_flac` is a global value (`ui.zig:87`), the stream is not
   yet a separate global, and `stopPlayback` only drains/closes audio
   (`ui.zig:463-468`). Task 5 must add stream open/close lifetime and close on
   every failure path (spec §5, §7).
10. **Interactive loop rebuild:** `main.zig:787-789` resets decode/scratch/player
    arenas on every loop pass, while `data` survives in `arena` (`302-303`).
    The streaming version must reopen or rewind the stream per pass without
    resetting an arena that owns a live stream (plan Task 5 precision, line
    149).
11. **`detectKind` requires at least 4 bytes** (`decoder.zig:46-56`).
    Frontends must read 4 bytes through `BufferedFile` and seek back to 0
    (spec §4.5, lines 183–184). The probe confirms `seek(..., 0)` works.
12. **Page-size assumption is safe but untested by Task 0 for a >64 KiB page.**
    The largest committed page is 4,222 bytes, and the theoretical maximum
    65,307 fits the planned 65,536-byte buffer. Task 2 still needs synthetic
    page-boundary/continuation/CRC tests (plan lines 90–91).
13. **Packet cap is generous but must be enforced cleanly.** Max committed
    packet is 3,832 bytes; the 1 MiB bound is 273.6× larger. A pathological
    packet must surface `PacketTooLarge`, not `OutOfMemory` (spec line 51,
    §7 line 230; plan line 88).
14. **No committed FLAC fixture:** `tier_flac.sh` generates FLAC fixtures from
    the committed PCM goldens at run time. Task 3’s oracle test should follow
    that recipe; there is no `testdata/*.flac` to inspect (search found none).

---

## Appendix A — probe source (`/tmp/m9_t0_probe.zig`)

```zig
const std = @import("std");
const filemod = @import("std_file");

var arena_buf: [1024 * 1024]u8 = undefined;
var rbuf: [65536]u8 = undefined;

fn writeText(s: []const u8) void {
    std.io.write(s);
}

fn writeNl() void {
    var s: []const u8 = "\n";
    std.io.write(s);
}

fn writeU64(v_in: u64) void {
    var v: u64 = v_in;
    if (v == 0) {
        var z: []const u8 = "0";
        std.io.write(z);
        return;
    }
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    while (v > 0) : (v = v / 10) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        n += 1;
    }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = tmp[n - 1 - i];
    }
    std.io.write(buf[0..n]);
}

fn fail(label: []const u8, code: i32) void {
    writeText(label);
    writeNl();
    std.os.exit(code);
}

pub fn main() void {
    var arena = std.arena.init(arena_buf[0..]);
    var f = filemod.open(&arena, "/tmp/m9_t0_big.bin", filemod.Mode.Read) catch {
        fail("open=FAIL", 1);
        return;
    };
    writeText("open=OK");
    writeNl();

    var sz: i64 = filemod.size(&f) catch {
        fail("size=FAIL", 2);
        return;
    };
    writeText("size=");
    writeU64(@intCast(u64, sz));
    writeNl();

    var n: usize = filemod.read(&f, rbuf[0..]) catch {
        fail("read_start=FAIL", 3);
        return;
    };
    writeText("read_start_65536=");
    writeU64(@intCast(u64, n));
    writeNl();

    var off: u64 = 4 * 1024 * 1024 + 12345;
    var ret: i64 = filemod.seek(&f, @intCast(i64, off), filemod.SeekWhence.Set) catch {
        fail("seek_u64_gt4m=FAIL", 4);
        return;
    };
    writeText("seek_u64_gt4m=");
    writeU64(@intCast(u64, ret));
    writeNl();

    n = filemod.read(&f, rbuf[0..]) catch {
        fail("read_after_seek=FAIL", 5);
        return;
    };
    writeText("read_after_seek_65536=");
    writeU64(@intCast(u64, n));
    writeNl();

    var tail_off: u64 = @intCast(u64, sz) - 10;
    ret = filemod.seek(&f, @intCast(i64, tail_off), filemod.SeekWhence.Set) catch {
        fail("seek_tail=FAIL", 6);
        return;
    };
    writeText("seek_tail=");
    writeU64(@intCast(u64, ret));
    writeNl();
    n = filemod.read(&f, rbuf[0..100]) catch {
        fail("read_tail=FAIL", 7);
        return;
    };
    writeText("read_tail_100=");
    writeU64(@intCast(u64, n));
    writeNl();

    ret = filemod.seek(&f, @intCast(i64, @intCast(u64, sz)), filemod.SeekWhence.Set) catch {
        fail("seek_eof=FAIL", 8);
        return;
    };
    writeText("seek_eof=");
    writeU64(@intCast(u64, ret));
    writeNl();
    n = filemod.read(&f, rbuf[0..100]) catch {
        fail("read_at_eof=FAIL", 9);
        return;
    };
    writeText("read_at_eof_100=");
    writeU64(@intCast(u64, n));
    writeNl();

    var huge: u64 = 4294967296;
    ret = filemod.seek(&f, @intCast(i64, huge), filemod.SeekWhence.Set) catch {
        fail("seek_u64_2pow32=FAIL", 10);
        return;
    };
    writeText("seek_u64_2pow32=");
    writeU64(@intCast(u64, ret));
    writeNl();

    sz = filemod.size(&f) catch {
        fail("size_after_huge_seek=FAIL", 11);
        return;
    };
    writeText("size_after_huge_seek=");
    writeU64(@intCast(u64, sz));
    writeNl();

    filemod.close(&f);
    writeText("close=OK");
    writeNl();
    std.os.exit(0);
}
```

## Appendix B — retained `/tmp` evidence

| Artifact | Path |
|---|---|
| Seed | `/tmp/m7_t5_seed2/zig1_5_clean` |
| Probe source | `/tmp/m9_t0_probe.zig` |
| Probe emit dir | `/tmp/m9_t0_probe_out` |
| Empty 8 MiB input | `/tmp/m9_t0_big.bin` |
| Dump-pin outputs | `/tmp/m9_t0_dump/main.c89`, `/tmp/m9_t0_dump/ui.c89` |
| Tier logs | `/tmp/m9_t0_tier_{info,setup,cli,audio,tui,flac}.log` |

No repository files under `lin_bin/`, `run.err`, or `progress.md` were read or
modified.
