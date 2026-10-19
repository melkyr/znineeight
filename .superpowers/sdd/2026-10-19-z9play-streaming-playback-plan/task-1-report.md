# M9 Task 1 report — bounded buffered file stream

**Status:** READY — gate PASS, no STOP condition.

**Base:** branch `zig1_improvements`, pre-task HEAD `64503da5`
(`docs(sdd): M9 T0 ledger`).

**Seed:** `/tmp/m7_t5_seed2/zig1_5_clean`
(md5 `b299b4b435e624d0ddbd2edde681cbc3`, seed v102 fixed point).

**Scope:** only the two Task 1 files were added:

- `examples/z98/z9play/stream.zig`
- `examples/z98/z9play/tests/stream_test.zig`

No frontend, compiler, stdlib, seed, plan, spec, `run.err`, `lin_bin/`, or
`progress.md` changes.

**Commit:** `ecf2bcdd` `example(z9play): bounded buffered file stream`
(2 files, 343 insertions).

---

## 1. Interface and semantics implemented

`stream.zig` matches M9 spec §4.1 exactly:

```zig
pub const STREAM_BUF_SIZE: usize = 64 * 1024;
pub const StreamError = error{ OpenFailed, ReadFailed, SeekFailed, SizeFailed, OutOfMemory };
pub const BufferedFile = struct {
    file: std_file.File,
    arena: *std.arena.Arena,
    buf: []u8,
    start: u64,
    len: usize,
    pos: usize,
    closed: bool,
};
pub fn bufferedFileOpen(arena, path) StreamError!BufferedFile
pub fn bufferedFileClose(bf) void
pub fn bufferedFileReadByte(bf) StreamError!?u8
pub fn bufferedFileRead(bf, out) StreamError!usize
pub fn bufferedFileSeek(bf, offset) StreamError!void
pub fn bufferedFileTell(bf) u64
pub fn bufferedFileSize(bf) u64
```

Decisions required by the brief:

- **Ownership:** `BufferedFile` owns `std_file.File` **by value**.
- **Arena lifetime:** `BufferedFile` borrows the caller arena. The arena and the
  64 KiB backing storage must **outlive** the `BufferedFile`; documented at the
  top of `stream.zig`.
- **Allocation:** `bufferedFileOpen` allocates exactly one `STREAM_BUF_SIZE`
  buffer from the caller arena. Reads, read-byte, seek, tell, and size never
  allocate. `readAll` is not used anywhere.
- **Open:** `std_file.open(arena, path, .Read)`; the file is closed on a size or
  buffer-allocation failure. `std_file.size` is called at open and its result is
  cached in `std_file.File.size_cache`; `bufferedFileSize` reads that cache.
- **Refill:** refills only when `pos == len`; advances `start` by the old `len`,
  then loops `std_file.read` until the 64 KiB buffer is full or a read returns 0.
  The OS cursor therefore always equals `start + len`.
- **Read:** copies available bytes, refills, and continues until `out` is full or
  true EOF. It returns a short count only when fewer bytes remain than requested;
  the next call returns 0. Zero-length `out` returns 0 without reading.
- **ReadByte:** returns `null` at true EOF; otherwise consumes one byte.
- **Seek:** `std_file.seek(..., @intCast(i64, offset), .Set)`, then resets
  `start = offset`, `len = 0`, `pos = 0` (buffer discarded).
- **Tell:** `start + pos` — the file offset of `buf[pos]`.
- **Close:** guarded on `file.handle`; closes once, clears the handle to null,
  and sets `closed`. A second close is a no-op.

---

## 2. Test coverage

`tests/stream_test.zig` creates a deterministic 4,206,649-byte
(>4 MiB) file in `/tmp`, with every byte equal to `offset & 255`, then checks:

- open allocates exactly 64 KiB (`arena.used == 65536`; arena capacity is
  exactly 64 KiB, so any extra allocation would fail);
- `size == 4,206,649` and initial `tell == 0`;
- a 65,530-byte read followed by a 20-byte read crosses the 64 KiB boundary
  with every byte matching its file offset;
- forward seek to `4 MiB + 100` and read-byte at that offset;
- backward seek to 12,345 and a 40,000-byte read, with `tell` tracking;
- seek to `FILE_SIZE - 200,000` and a full 200,000-byte read across three
  buffer boundaries, ending with `tell == FILE_SIZE`;
- seek to `FILE_SIZE - 10`: `read(100)` returns 10, then `read(100)` returns 0;
- `readByte` at EOF returns `null`;
- `arena.used` is still exactly 64 KiB after all stream operations;
- `bufferedFileClose` twice succeeds and clears `file.handle`.

The temp file is removed at the end.

---

## 3. Build and test evidence

Seed identity:

```
$ md5sum /tmp/m7_t5_seed2/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed2/zig1_5_clean
$ gcc --version | head -1
gcc (Debian 12.2.0-14+deb12u1) 12.2.0
```

Exact commands (from repo root; emitted binding recipe):

```
$ rm -rf /tmp/m9_t1_stream && mkdir -p /tmp/m9_t1_stream
$ timeout 300 /tmp/m7_t5_seed2/zig1_5_clean -fsafe \
    -o /tmp/m9_t1_stream examples/z98/z9play/tests/stream_test.zig
$ sh /tmp/m9_t1_stream/build_target.sh linux /tmp/m9_t1_stream/prog
$ /tmp/m9_t1_stream/prog
```

Exact results:

```
zig_rc=0
build_rc=0
stream_test: PASS size=4206649 arena_used=65536
test_rc=0
```

The emitted binary is a 32-bit i386 Linux executable. `build.log` contains only
the standard seed-runtime unused-function warnings; no warnings or errors from
`stream.zig` or `stream_test.zig`. The temp file was removed after the run.

---

## 4. Concerns / notes

- **Cached size:** per the brief/spec, `bufferedFileSize` uses the `File`
  size cache populated at open. A file that grows or shrinks after open is not
  re-stat'ed.
- **`SizeFailed` path:** if the initial `std_file.size` fails, open closes the
  handle and returns `SizeFailed`; buffer-allocation failure returns
  `OutOfMemory` after closing.
- **Seek conversion:** `u64` offsets are passed through the specified
  `@intCast(i64, offset)`; offsets above `i64` max are outside the intended
  range.
- **No frontend behavior changed** in this task; `stream.zig` is not imported
  by production code yet.
