const std = @import("std");
const cli = @import("cli.zig");
const filemod = @import("std_file.zig");
const torrentlib = @import("torrent.zig");
const diskmod = @import("disk.zig");
const resumemod = @import("resume.zig");
const hexmod = @import("std_hex.zig");
const parse = @import("std_parse.zig");
const std_net = @import("std_net");
const piecemod = @import("piece.zig");
const peermod = @import("peer.zig");
const trackerlib = @import("tracker.zig");

// One torrent arena (spec §9), backed by a static buffer. Never reset.
var g_arena_buf: [4194304]u8 = undefined;

// M2 Task 4 — single-peer download state. The async frame pool and the root
// frame buffer are 8-aligned (`[N]u64`); the two scratch arenas are reset per
// use (work: per `onBlock` verify; save: per resume sidecar write). The peer,
// ctx, args record and Task are file-scope globals so the coroutine holds
// stable pointers across suspensions (spec §12 risk 1).
var g_async_storage: [32 * 1024]u64 = undefined;
var g_frame_storage: [2048]u64 = undefined;
var g_work_buf: [1048576]u8 = undefined;
var g_save_buf: [262144]u8 = undefined;
var g_work_arena: std.arena.Arena = undefined;
var g_save_arena: std.arena.Arena = undefined;
var g_peer: peermod.Peer = undefined;
var g_pctx: peermod.RunCtx = undefined;

const PeerArgs = struct { ctx: *peermod.RunCtx, peer: *peermod.Peer };
var g_peer_args: PeerArgs = undefined;
var g_task: std.async.Task = undefined;

fn writeText(s: []const u8) void {
    std.io.write(s);
}

fn writeU64(v: u64) void {
    var buf: [24]u8 = undefined;
    var n = parse.itoa64(buf[0..], @intCast(i64, v));
    std.io.write(n);
}

fn zeroStats() trackerlib.Stats {
    return trackerlib.Stats{
        .downloaded = 0,
        .uploaded = 0,
        .left = 0,
        .peer_count = 0,
        .down_rate = 0,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = [5]u32{ 0, 0, 0, 0, 0 },
        .window_up = [5]u32{ 0, 0, 0, 0, 0 },
        .window_idx = 0,
    };
}

fn parseSeed(sv: []const u8) u32 {
    var v: u64 = 0;
    var ok: bool = sv.len > 0;
    var j: usize = 0;
    while (j < sv.len) : (j += 1) {
        var c: u8 = sv[j];
        if (c < '0' or c > '9') {
            ok = false;
        } else {
            v = v * 10 + @intCast(u64, c - '0');
        }
    }
    if (!ok) return 0;
    return @intCast(u32, v & @intCast(u64, 0xFFFFFFFF));
}

// "-Z9T01-" + 12 seeded bytes (spec §6). The seed is Z9TORR_SEED when set
// (deterministic), else the millisecond clock. Out-param: C89 cannot return an
// array from a function.
fn makePeerId(out: *[20]u8) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        out[i] = 0;
    }
    var prefix: []const u8 = "-Z9T01-";
    i = 0;
    while (i < prefix.len and i < 20) : (i += 1) {
        out[i] = prefix[i];
    }
    var seed: u32 = std.time.ticksMs();
    if (std.os.env("Z9TORR_SEED")) |sv| {
        var s = parseSeed(sv);
        if (s != 0) seed = s;
    }
    var st: u32 = seed;
    if (st == 0) st = 1;
    while (i < 20) : (i += 1) {
        st = st * @intCast(u32, 1664525) + @intCast(u32, 1013904223);
        out[i] = @intCast(u8, (st >> 16) & @intCast(u32, 0xFF));
    }
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var args: cli.Args = cli.parseArgs(argc, argv);
    if (!filemod.exists(args.torrent_path)) {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
    }

    var arena: std.arena.Arena = std.arena.init(g_arena_buf[0..]);

    // E2 (M1a): cap the .torrent metadata before reading it into the arena.
    // The downloaded payload (`total_length`) is unbounded and streamed to
    // disk; only the metadata file is capped (spec §9).
    var szf = filemod.open(&arena, args.torrent_path, filemod.Mode.Read) catch {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };
    var sz: i64 = filemod.size(&szf) catch {
        filemod.close(&szf);
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };
    filemod.close(&szf);
    if (sz < 0) {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    }
    if (@intCast(usize, sz) > torrentlib.MAX_TORRENT_BYTES) {
        var msg: []const u8 = "z9torr: torrent too large\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    }

    var bytes: []u8 = filemod.readAll(&arena, args.torrent_path) catch {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };

    const t: torrentlib.Torrent = torrentlib.load(&arena, bytes) catch {
        var msg: []const u8 = "z9torr: malformed torrent\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };

    // M2 Task 3 resume hook. If a previous run left the output file, reconstruct
    // the completed-piece set (sidecar + re-hash). The full download loop (M2
    // Task 4) consumes this state; here it is computed and discarded so M1's
    // metadata-only output is byte-identical (the file is never created when it
    // is absent, so M1's tier1 gate sees no side effects).
    if (filemod.exists(t.name)) {
        var out = diskmod.openTarget(&arena, t) catch {
            var dmsg: []const u8 = "z9torr: disk error\n";
            std.io.write(dmsg);
            std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.disk)));
            return;
        };
        var rstate = resumemod.load(&arena, t, &out);
        resumemod.rehash(&arena, t, &out, rstate) catch {
            filemod.close(&out);
            var dmsg2: []const u8 = "z9torr: disk error\n";
            std.io.write(dmsg2);
            std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.disk)));
            return;
        };
        filemod.close(&out);
    }

    var l_name: []const u8 = "name: ";
    writeText(l_name);
    writeText(t.name);
    var nl: []const u8 = "\n";
    writeText(nl);

    var l_len: []const u8 = "length: ";
    writeText(l_len);
    writeU64(t.total_length);
    writeText(nl);

    var l_pl: []const u8 = "piece length: ";
    writeText(l_pl);
    writeU64(@intCast(u64, t.piece_length));
    writeText(nl);

    var l_pc: []const u8 = "pieces: ";
    writeText(l_pc);
    writeU64(@intCast(u64, t.piece_hashes.len / 20));
    writeText(nl);

    var l_ih: []const u8 = "info_hash: ";
    writeText(l_ih);
    const hex: []u8 = hexmod.encodeLower(&arena, t.info_hash[0..20]) catch {
        var msg: []const u8 = "z9torr: malformed torrent\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };
    writeText(hex);
    writeText(nl);

    // ---- M2 Task 4: single-peer download ----------------------------------
    // The metadata above is always printed (M1 contract; tier1). If a tracker
    // answers the announce, run one peer coroutine to completion; otherwise
    // (no tracker reachable, e.g. the M1 tier1 gate) stop here with exit 0.
    _ = std_net.init();
    var peer_id: [20]u8 = undefined;
    makePeerId(&peer_id);
    var stats = zeroStats();
    var ann = trackerlib.announce(&arena, t, peer_id, @intCast(u16, 6881), trackerlib.AnnounceEvent.started, stats) catch {
        std_net.cleanup();
        return;
    };
    if (ann.peers.len == 0) {
        std_net.cleanup();
        return;
    }

    var out = diskmod.openTarget(&arena, t) catch {
        var dmsg: []const u8 = "z9torr: disk error\n";
        std.io.write(dmsg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.disk)));
        return;
    };
    var rstate = resumemod.load(&arena, t, &out);
    resumemod.rehash(&arena, t, &out, rstate) catch {
        filemod.close(&out);
        var dmsg2: []const u8 = "z9torr: disk error\n";
        std.io.write(dmsg2);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.disk)));
        return;
    };

    var n_pieces: u32 = 0;
    if (t.total_length > 0) {
        var pl: u64 = @intCast(u64, t.piece_length);
        n_pieces = @intCast(u32, (t.total_length + pl - 1) / pl);
    }
    var verified_count: u32 = 0;
    var vi: u32 = 0;
    while (vi < n_pieces) : (vi += 1) {
        if (piecemod.bitGet(rstate.completed_bits, vi)) verified_count += 1;
    }

    g_work_arena = std.arena.init(g_work_buf[0..]);
    g_save_arena = std.arena.init(g_save_buf[0..]);

    g_peer = peermod.Peer{
        .addr = ann.peers[0],
        .sock = @intCast(i32, -1),
        .peer_id = peer_id,
        .am_choking = true,
        .am_interested = false,
        .peer_choking = true,
        .peer_interested = false,
        .last_recv_ms = 0,
        .last_send_ms = 0,
        .down_bytes = 0,
        .up_bytes = 0,
        .read_buf = undefined,
    };
    g_pctx = peermod.RunCtx{
        .arena = &arena,
        .work_arena = &g_work_arena,
        .save_arena = &g_save_arena,
        .t = t,
        .f = &out,
        .verified_bits = rstate.completed_bits,
        .n_pieces = n_pieces,
        .verified_count = verified_count,
        .ok = false,
        .exit_class = 4,
    };
    g_peer_args = PeerArgs{ .ctx = &g_pctx, .peer = &g_peer };

    var async_ctx: *std.async.Context = std.async.contextInit(@ptrCast([*]u8, &g_async_storage)[0 .. 32 * 1024 * 8]);
    var frame_ptr: [*]u8 = @ptrCast([*]u8, &g_frame_storage);
    g_task.frame = @asyncInit(async_ctx, frame_ptr, peermod.peerRun, @ptrCast(*const void, &g_peer_args));
    g_task.ctx = async_ctx;
    g_task.arg = @ptrCast(*void, &g_peer_args);
    g_task.result = @ptrCast(*void, &g_peer_args);
    g_task.state = std.async.TaskState.ready;
    g_task.cancel_requested = false;
    g_task.waiting_on = &g_task;
    g_task.has_waiting_on = false;

    var task_ptrs: [1]*std.async.Task = undefined;
    task_ptrs[0] = &g_task;
    var sched = std.async.schedulerInit(task_ptrs[0..]);
    _ = std.async.addTask(&sched, &g_task);
    std.async.waitFor(&sched, &g_task) catch {};

    filemod.close(&out);

    if (!g_pctx.ok) {
        var emsg: []const u8 = "z9torr: peer error\n";
        std.io.write(emsg);
        std_net.cleanup();
        std.os.exit(@intCast(i32, g_pctx.exit_class));
        return;
    }

    var stats2 = zeroStats();
    stats2.downloaded = t.total_length;
    _ = trackerlib.announce(&arena, t, peer_id, @intCast(u16, 6881), trackerlib.AnnounceEvent.completed, stats2) catch {};

    var okline: []const u8 = "z9torr: download complete\n";
    std.io.write(okline);
    std_net.cleanup();
    std.os.exit(0);
}
