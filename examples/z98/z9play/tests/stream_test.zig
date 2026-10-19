// stream_test.zig — BufferedFile unit gate for z9play M9 Task 1.
//
// Creates a deterministic file larger than 4 MiB in /tmp, then asserts:
//   - size/tell/open allocate exactly one 64 KiB buffer (the arena has exactly
//     that capacity, so any extra stream allocation would fail);
//   - reads cross 64 KiB buffer boundaries and match every file byte;
//   - reads near EOF return a short count, then 0;
//   - readByte at EOF returns null;
//   - seek backwards/forwards resets the buffer and tell tracks the offset;
//   - close is idempotent.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/stream_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const stream = @import("../stream.zig");

const FILE_SIZE: usize = 4 * 1024 * 1024 + 12345;
const BLOCK: usize = 64 * 1024;

var arena_buf: [stream.STREAM_BUF_SIZE]u8 = undefined;
var write_block: [BLOCK]u8 = undefined;
var read_block: [200000]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "stream_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
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
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = tmp[n - 1 - i];
    }
    std.io.write(buf[0..n]);
}

fn expected(off: u64) u8 {
    return @intCast(u8, off & 255);
}

fn checkBytes(buf: []const u8, off: u64) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (buf[i] != expected(off + @intCast(u64, i))) {
            fail("byte mismatch");
        }
    }
}

fn createFile(path: []const u8) void {
    var io = std.arena.init(arena_buf[0..]);
    var f = filemod.open(&io, path, .Write) catch {
        fail("cannot create temp file");
        return;
    };
    var off: usize = 0;
    while (off < FILE_SIZE) {
        var n: usize = BLOCK;
        if (FILE_SIZE - off < n) n = FILE_SIZE - off;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            write_block[i] = expected(@intCast(u64, off + i));
        }
        var w: usize = 0;
        while (w < n) {
            var got: usize = filemod.write(&f, write_block[w..n]) catch {
                fail("cannot write temp file");
                return;
            };
            if (got == 0) fail("temp file write returned 0");
            w += got;
        }
        off += n;
    }
    filemod.close(&f);
}

pub fn main() void {
    var path: []const u8 = "/tmp/z9play_stream_test.bin";
    createFile(path);

    var arena = std.arena.init(arena_buf[0..]);
    std.arena.reset(&arena);
    var bf = stream.bufferedFileOpen(&arena, path) catch {
        fail("bufferedFileOpen failed");
        return;
    };
    if (arena.used != stream.STREAM_BUF_SIZE) fail("open did not allocate exactly one buffer");
    if (bf.buf.len != stream.STREAM_BUF_SIZE) fail("buffer length is not 64 KiB");
    if (stream.bufferedFileSize(&bf) != @intCast(u64, FILE_SIZE)) fail("size != file size");
    if (stream.bufferedFileTell(&bf) != 0) fail("initial tell != 0");

    var n1: usize = stream.bufferedFileRead(&bf, read_block[0..65530]) catch {
        fail("read before boundary failed");
        return;
    };
    if (n1 != 65530) fail("short read before boundary");
    checkBytes(read_block[0..n1], 0);
    if (stream.bufferedFileTell(&bf) != 65530) fail("tell after first read != 65530");

    var n2: usize = stream.bufferedFileRead(&bf, read_block[0..20]) catch {
        fail("read across boundary failed");
        return;
    };
    if (n2 != 20) fail("short read across boundary");
    checkBytes(read_block[0..n2], 65530);
    if (stream.bufferedFileTell(&bf) != 65550) fail("tell after boundary read != 65550");

    var mid: u64 = 4 * 1024 * 1024 + 100;
    stream.bufferedFileSeek(&bf, mid) catch {
        fail("forward seek failed");
        return;
    };
    if (stream.bufferedFileTell(&bf) != mid) fail("tell after forward seek != mid");
    var mb: ?u8 = stream.bufferedFileReadByte(&bf) catch {
        fail("readByte after forward seek failed");
        return;
    };
    if (mb) |b| {
        if (b != expected(mid)) fail("readByte after forward seek mismatch");
    } else {
        fail("readByte after forward seek returned EOF");
    }

    var back: u64 = 12345;
    stream.bufferedFileSeek(&bf, back) catch {
        fail("backward seek failed");
        return;
    };
    var n3: usize = stream.bufferedFileRead(&bf, read_block[0..40000]) catch {
        fail("read after backward seek failed");
        return;
    };
    if (n3 != 40000) fail("short read after backward seek");
    checkBytes(read_block[0..n3], back);
    if (stream.bufferedFileTell(&bf) != back + 40000) fail("tell after backward read wrong");

    var tail: u64 = @intCast(u64, FILE_SIZE - 200000);
    stream.bufferedFileSeek(&bf, tail) catch {
        fail("seek near EOF failed");
        return;
    };
    var n4: usize = stream.bufferedFileRead(&bf, read_block[0..200000]) catch {
        fail("read near EOF failed");
        return;
    };
    if (n4 != 200000) fail("read near EOF not full");
    checkBytes(read_block[0..n4], tail);
    if (stream.bufferedFileTell(&bf) != @intCast(u64, FILE_SIZE)) fail("tell at EOF wrong");

    var short_off: u64 = @intCast(u64, FILE_SIZE - 10);
    stream.bufferedFileSeek(&bf, short_off) catch {
        fail("seek for short read failed");
        return;
    };
    var ns: usize = stream.bufferedFileRead(&bf, read_block[0..100]) catch {
        fail("short read failed");
        return;
    };
    if (ns != 10) fail("read near EOF did not return 10");
    checkBytes(read_block[0..ns], short_off);
    var ne: usize = stream.bufferedFileRead(&bf, read_block[0..100]) catch {
        fail("read at EOF failed");
        return;
    };
    if (ne != 0) fail("read at EOF did not return 0");

    var eb: ?u8 = stream.bufferedFileReadByte(&bf) catch {
        fail("readByte at EOF failed");
        return;
    };
    if (eb) |b| {
        fail("readByte at EOF did not return null");
    }

    if (arena.used != stream.STREAM_BUF_SIZE) fail("stream allocated beyond the fixed buffer");

    stream.bufferedFileClose(&bf);
    stream.bufferedFileClose(&bf);
    if (@ptrToInt(bf.file.handle) != 0) fail("close did not clear the handle");

    filemod.remove(path) catch {};
    var ok: []const u8 = "stream_test: PASS size=";
    std.io.write(ok);
    writeU64(@intCast(u64, FILE_SIZE));
    var used: []const u8 = " arena_used=";
    std.io.write(used);
    writeU64(@intCast(u64, arena.used));
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(0);
}
