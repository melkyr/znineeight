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
const udptracker = @import("udp_tracker.zig");
const dhtmod = @import("dht.zig");
const pexmod = @import("pex.zig");
const schedmod = @import("scheduler.zig");
const ratelimit = @import("ratelimit.zig");
const statsmod = @import("stats.zig");
const logmod = @import("log.zig");
const consolemod = @import("console.zig");

// One torrent arena (spec §9), backed by a static buffer. Never reset.
var g_arena_buf: [4194304]u8 = undefined;

// M3 multi-peer download state. A fixed cap on live peer coroutines bounds the
// coroutine frame pools and the scheduler's per-peer `Peer` slots (each embeds a
// 64 KiB `read_buf`); `--max-peers` is clamped to it. Every coroutine's mutable
// state lives in file-scope storage (spec §12 risk 1) so its pointers stay
// stable across suspensions.
// `sizeof(Peer)` is ~64.4 KiB (the embedded 64 KiB `read_buf`), so 16 peers
// need ~1.03 MiB of the 4 MiB scheduler arena; the frame pools add 768 KiB.
// Static arenas total 10 MiB (torrent 4 + work 1 + save 0.25 + ctx/frame 0.75 +
// scheduler 4), under the 16 MB target.
const MAX_RUNTIME_PEERS: usize = 16;
// M4: bounded merge pool for tracker + DHT candidate addresses (spawn cap is
// still MAX_RUNTIME_PEERS).
const MAX_CANDIDATES: usize = 64;
const PEER_CTX_U64: usize = 4096;       // 32 KiB child-frame pool per peer
const PEER_CTX_BYTES: usize = PEER_CTX_U64 * 8;
const PEER_FRAME_U64: usize = 2048;     // 16 KiB root frame per peer
const PEER_FRAME_BYTES: usize = PEER_FRAME_U64 * 8;
// Give up (spec §8 exit 4) when no piece verifies for this long (no usable peer).
const STALL_MS: u32 = 60000;

// The context/frame buffers are `[N]u64` so `contextInit`/`@asyncInit` get the
// 8-aligned storage they require (a bare `[N]u8` is 1-aligned and traps).
var g_ctx_buf: [MAX_RUNTIME_PEERS * PEER_CTX_U64]u64 = undefined;
var g_frame_buf: [MAX_RUNTIME_PEERS * PEER_FRAME_U64]u64 = undefined;
var g_work_buf: [1048576]u8 = undefined;
var g_save_buf: [262144]u8 = undefined;
// M4: scratch arena for BEP 10/11 extended-message decoding (reset per message).
var g_pex_buf: [131072]u8 = undefined;
// Dedicated scheduler arena. `schedulerInit` carves three per-piece arrays
// (PieceStatus: 8 B/piece; piece_rarest + piece_owner: 4 B each) plus
// `max_peers * sizeof(Peer)` (≈64 KiB each). At the parser's `MAX_PIECES`
// (157286) that is ≈ 157286*(8+4+4) ≈ 2.4 MiB plus ≈ 1.0 MiB of peers ≈ 3.4 MiB,
// so 4 MiB fits the largest torrent the parser accepts (M3 final-review fix 4).
var g_sched_buf: [4194304]u8 = undefined;
var g_work_arena: std.arena.Arena = undefined;
var g_save_arena: std.arena.Arena = undefined;
var g_sched_arena: std.arena.Arena = undefined;
var g_pex_arena: std.arena.Arena = undefined;
var g_pctx: peermod.RunCtx = undefined;
var g_sched: schedmod.Scheduler = undefined;
var g_down_bucket: ratelimit.TokenBucket = undefined;
var g_up_bucket: ratelimit.TokenBucket = undefined;

const PeerArgs = struct { ctx: *peermod.RunCtx, peer: *peermod.Peer };
var g_peer_args: [MAX_RUNTIME_PEERS]PeerArgs = undefined;
var g_tasks: [MAX_RUNTIME_PEERS]std.async.Task = undefined;
var g_task_ptrs: [MAX_RUNTIME_PEERS]*std.async.Task = undefined;
var g_cand: [MAX_CANDIDATES]tracker.PeerAddr = undefined;
// M4: per-slot "a coroutine task exists" flag, so PEX-learned peers added mid-
// run can be spawned with the same code path as the startup candidates.
var g_started: [MAX_RUNTIME_PEERS]bool = undefined;

fn writeText(s: []const u8) void {
    std.io.write(s);
}

fn writeU64(v: u64) void {
    var buf: [24]u8 = undefined;
    var n = parse.itoa64(buf[0..], @intCast(i64, v));
    std.io.write(n);
}

// Log the exit code + a short reason, then close the log file and exit. Placed
// at every `main` exit site so a `Z9TORR_LOG` run records why it stopped; the
// logging itself is a strict no-op when the env var is unset.
fn logExitAnd(code: i32, reason: []const u8) void {
    logmod.s("exit code=");
    logmod.i32v(code);
    logmod.s(" reason=");
    logmod.s(reason);
    logmod.nl();
    logmod.end();
    std.os.exit(code);
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

fn startsWithPrefix(s: []const u8, p: []const u8) bool {
    if (s.len < p.len) return false;
    var i: usize = 0;
    while (i < p.len) : (i += 1) {
        if (s[i] != p[i]) return false;
    }
    return true;
}

// M4: the first `udp://` announce (primary URL, then the announce-list tiers),
// or null so the caller falls back to the M0 HTTP tracker.
fn findUdpAnnounce(t: torrentlib.Torrent) ?[]const u8 {
    var pre: []const u8 = "udp://";
    if (startsWithPrefix(t.announce, pre)) return t.announce;
    var i: u32 = 0;
    while (i < t.announce_count) : (i += 1) {
        var u: []const u8 = t.announce_list[@intCast(usize, i)];
        if (startsWithPrefix(u, pre)) return u;
    }
    return null;
}

// Announce through the UDP tracker (BEP 15) when the torrent lists one, else the
// existing HTTP tracker. Both yield the same `AnnounceResult` for the scheduler.
fn announceTracked(arena: *std.arena.Arena, t: torrentlib.Torrent, peer_id: [20]u8, port: u16, event: trackerlib.AnnounceEvent, stats: trackerlib.Stats) trackerlib.TrackerError!trackerlib.AnnounceResult {
    if (findUdpAnnounce(t)) |url| {
        return udptracker.announceUdp(arena, url, t.info_hash[0..20], peer_id[0..20], port, event, stats);
    }
    return trackerlib.announce(arena, t, peer_id, port, event, stats);
}

// Index of the first inactive scheduler peer slot (== `peers.len` if full).
fn firstInactiveSlot() usize {
    var j: usize = 0;
    while (j < g_sched.peers.len) : (j += 1) {
        if (!g_sched.peers[j].active) return j;
    }
    return g_sched.peers.len;
}

// Create + register the peer coroutine for an already-active scheduler `slot`.
// Shared by the startup candidate loop and the mid-run PEX dynamic-spawn path,
// so PEX-learned peers are dialed by exactly the same mechanism as DHT/tracker
// peers. The client's real peer_id is copied into the slot for `makeHandshake`.
fn spawnPeerAt(slot: usize, peer_id: [20]u8) void {
    var pid_i: usize = 0;
    while (pid_i < 20) : (pid_i += 1) {
        g_sched.peers[slot].peer_id[pid_i] = peer_id[pid_i];
    }
    g_peer_args[slot] = PeerArgs{ .ctx = &g_pctx, .peer = &g_sched.peers[slot] };
    var ctx_slice: []u8 = @ptrCast([*]u8, &g_ctx_buf)[slot * PEER_CTX_BYTES .. (slot + 1) * PEER_CTX_BYTES];
    var async_ctx: *std.async.Context = std.async.contextInit(ctx_slice);
    var frame_ptr: [*]u8 = @ptrCast([*]u8, &g_frame_buf) + slot * PEER_FRAME_BYTES;
    g_tasks[slot].frame = @asyncInit(async_ctx, frame_ptr, peermod.peerRun, @ptrCast(*const void, &g_peer_args[slot]));
    g_tasks[slot].ctx = async_ctx;
    g_tasks[slot].arg = @ptrCast(*void, &g_peer_args[slot]);
    g_tasks[slot].result = @ptrCast(*void, &g_peer_args[slot]);
    g_tasks[slot].state = std.async.TaskState.ready;
    g_tasks[slot].cancel_requested = false;
    g_tasks[slot].waiting_on = &g_tasks[slot];
    g_tasks[slot].has_waiting_on = false;
    g_task_ptrs[slot] = &g_tasks[slot];
}

// Bytes covered by the verified pieces in `bits` (for the progress line).
fn verifiedBytes(t: torrentlib.Torrent, bits: []u8, n: u32) u64 {
    var total: u64 = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        if (piecemod.bitGet(bits, i)) total += @intCast(u64, diskmod.pieceLength(t, i));
    }
    return total;
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
        st = st *% @intCast(u32, 1664525) +% @intCast(u32, 1013904223);
        out[i] = @intCast(u8, (st >> 16) & @intCast(u32, 0xFF));
    }
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    // M4 Task 4: in-process DHT/PEX self-tests, gated by env so they never run
    // in normal operation. They exit before any torrent/arg processing.
    if (std.os.env("Z9TORR_DHT_SELFTEST")) |_| {
        std.os.exit(dhtmod.selfTest());
    }
    if (std.os.env("Z9TORR_PEX_SELFTEST")) |_| {
        std.os.exit(pexmod.selfTest());
    }
    var args: cli.Args = cli.parseArgs(argc, argv);
    logmod.begin();
    // M5 T3b: probe once whether stdout is an interactive console, so the 1 Hz
    // progress line can pick the in-place '\r' (console) or a redirected '\n'.
    var stdout_console: bool = consolemod.stdoutIsConsole();
    if (!filemod.exists(args.torrent_path)) {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "cannot read torrent file: missing");
    }

    var arena: std.arena.Arena = std.arena.init(g_arena_buf[0..]);

    // E2 (M1a): cap the .torrent metadata before reading it into the arena.
    // The downloaded payload (`total_length`) is unbounded and streamed to
    // disk; only the metadata file is capped (spec §9).
    var szf = filemod.open(&arena, args.torrent_path, filemod.Mode.Read) catch {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "cannot read torrent file: open");
        return;
    };
    var sz: i64 = filemod.size(&szf) catch {
        filemod.close(&szf);
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "cannot read torrent file: size");
        return;
    };
    filemod.close(&szf);
    if (sz < 0) {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "cannot read torrent file: bad size");
        return;
    }
    if (@intCast(usize, sz) > torrentlib.MAX_TORRENT_BYTES) {
        var msg: []const u8 = "z9torr: torrent too large\n";
        std.io.write(msg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "torrent too large");
        return;
    }

    var bytes: []u8 = filemod.readAll(&arena, args.torrent_path) catch {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "cannot read torrent file: readAll");
        return;
    };

    const t: torrentlib.Torrent = torrentlib.load(&arena, bytes) catch {
        var msg: []const u8 = "z9torr: malformed torrent\n";
        std.io.write(msg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "malformed torrent: parse");
        return;
    };


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
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)), "malformed torrent: info_hash encode");
        return;
    };
    writeText(hex);
    writeText(nl);

    // ---- M3: multi-peer download ------------------------------------------
    // The metadata above is always printed (M1 contract). The client always
    // attempts the tracker: an announce failure is a tracker/network error
    // (spec §8 exit 3); a tracker that yields no peers is a peer error (exit 4).
    _ = std_net.init();
    var peer_id: [20]u8 = undefined;
    makePeerId(&peer_id);
    var stats = zeroStats();
    stats.left = t.total_length;
    var ann = announceTracked(&arena, t, peer_id, @intCast(u16, 6881), trackerlib.AnnounceEvent.started, stats) catch {
        std_net.cleanup();
        var tmsg: []const u8 = "z9torr: tracker error\n";
        std.io.write(tmsg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.tracker)), "tracker error");
        return;
    };
    logmod.s("announce peers=");
    logmod.u32v(@intCast(u32, ann.peers.len));
    logmod.s(" interval=");
    logmod.u32v(ann.interval);
    logmod.nl();
    if (ann.peers.len == 0) {
        std_net.cleanup();
        var nmsg: []const u8 = "z9torr: peer error\n";
        std.io.write(nmsg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.peer)), "peer error: tracker returned no peers");
        return;
    }

    var out = diskmod.openTarget(&arena, t) catch {
        var dmsg: []const u8 = "z9torr: disk error\n";
        std.io.write(dmsg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.disk)), "disk error: open target");
        return;
    };
    var rstate = resumemod.load(&arena, t, &out);
    resumemod.rehash(&arena, t, &out, rstate) catch {
        filemod.close(&out);
        var dmsg2: []const u8 = "z9torr: disk error\n";
        std.io.write(dmsg2);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.disk)), "disk error: rehash");
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
    g_pex_arena = std.arena.init(g_pex_buf[0..]);

    // Global token buckets (spec §6/§9 M3). `0` = unlimited; `last_refill_ms`
    // starts at "now" so the first refill credits no startup burst.
    var now0: u32 = std.time.ticksMs();
    g_down_bucket = ratelimit.bucketInit(args.max_down);
    g_up_bucket = ratelimit.bucketInit(args.max_up);
    ratelimit.refill(&g_down_bucket, now0);
    ratelimit.refill(&g_up_bucket, now0);

    // Scheduler slot capacity = the configured concurrent-peer cap (clamped),
    // NOT the startup candidate count: PEX peers discovered mid-run must have
    // free slots to claim. `want` limits only how many startup candidates are
    // spawned (clamped to the merged candidate count below). Seed `piece_state`
    // from the resume bits so rarest-first never re-picks a verified piece.
    var sched_slots: u32 = args.max_peers;
    if (sched_slots == 0) sched_slots = 1;
    if (sched_slots > @intCast(u32, MAX_RUNTIME_PEERS)) sched_slots = @intCast(u32, MAX_RUNTIME_PEERS);
    var want: u32 = sched_slots;

    g_sched_arena = std.arena.init(g_sched_buf[0..]);
    g_sched = schedmod.schedulerInit(&g_sched_arena, t, sched_slots) catch {
        filemod.close(&out);
        std_net.cleanup();
        var omsg: []const u8 = "z9torr: disk error\n";
        std.io.write(omsg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.disk)), "disk error: scheduler init");
        return;
    };
    var seed_i: u32 = 0;
    while (seed_i < n_pieces) : (seed_i += 1) {
        if (piecemod.bitGet(rstate.completed_bits, seed_i)) {
            g_sched.piece_state[@intCast(usize, seed_i)].state = piecemod.BlockState.verified;
        }
    }

    // M4: zero every slot's byte counters and clear the started flags. Idle
    // slots are otherwise undefined (schedulerInit leaves nested `Peer` fields
    // undefined), and PEX may activate them mid-run; zeroing keeps the run-wide
    // byte sums well-defined.
    var zs: usize = 0;
    while (zs < g_sched.peers.len) : (zs += 1) {
        g_sched.peers[zs].down_bytes = 0;
        g_sched.peers[zs].up_bytes = 0;
        g_started[zs] = false;
    }

    // M4: ephemeral MSE key seed. Deterministic under Z9TORR_SEED, else the
    // millisecond clock (same convention as `makePeerId`).
    var mse_seed: u32 = std.time.ticksMs();
    if (std.os.env("Z9TORR_SEED")) |sv| {
        var s = parseSeed(sv);
        if (s != 0) mse_seed = s;
    }

    g_pctx = peermod.RunCtx{
        .arena = &arena,
        .work_arena = &g_work_arena,
        .save_arena = &g_save_arena,
        .t = t,
        .f = &out,
        .verified_bits = rstate.completed_bits,
        .partial = rstate.partial,
        .n_pieces = n_pieces,
        .verified_count = verified_count,
        .ok = false,
        .exit_class = 4,
        .down_bucket = &g_down_bucket,
        .up_bucket = &g_up_bucket,
        .peers = g_sched.peers,
        .mse_seed = mse_seed,
        .pex_arena = &g_pex_arena,
    };

    if (std.os.env("Z9TORR_CLAIM_LOG")) |ev| {
        _ = ev;
        peermod.log_claims = true;
    }

    // M4: merge the tracker peers with optional bootstrap DHT peers into one
    // bounded candidate list. `Z9TORR_DHT` is a comma-separated `host[:port]`
    // bootstrap list; unset it to keep the M3 tracker-only behavior. DHT is
    // best-effort: a failed lookup simply contributes no candidates.
    var n_cand: usize = 0;
    var ci: usize = 0;
    while (ci < ann.peers.len and n_cand < MAX_CANDIDATES) : (ci += 1) {
        g_cand[n_cand] = ann.peers[ci];
        n_cand += 1;
    }
    if (std.os.env("Z9TORR_DHT")) |boot| {
        var nd: u32 = dhtmod.dhtDiscover(&arena, boot, peer_id, t.info_hash[0..20], g_cand[n_cand..]);
        if (@intCast(usize, nd) > MAX_CANDIDATES - n_cand) nd = @intCast(u32, MAX_CANDIDATES - n_cand);
        n_cand += @intCast(usize, nd);
        logmod.s("dht peers=");
        logmod.u32v(nd);
        logmod.nl();
    }
    if (@intCast(usize, want) > n_cand) want = @intCast(u32, n_cand);
    if (want == 0) {
        filemod.close(&out);
        std_net.cleanup();
        var zmsg0: []const u8 = "z9torr: peer error\n";
        std.io.write(zmsg0);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.peer)), "peer error: no candidate peers");
        return;
    }

    // Spawn one peer coroutine per candidate address (capped). `addPeer` picks
    // the first free slot and rejects duplicate/recent addresses; the slot it
    // uses is the first inactive slot found immediately before the call.
    var n_spawned: u32 = 0;
    var ai: usize = 0;
    while (ai < n_cand and n_spawned < want) : (ai += 1) {
        var slot: usize = firstInactiveSlot();
        if (slot >= g_sched.peers.len) break;
        if (!schedmod.addPeer(&g_sched, g_cand[ai])) continue;
        spawnPeerAt(slot, peer_id);
        g_started[slot] = true;
        n_spawned += 1;
    }
    logmod.s("spawn=");
    logmod.u32v(n_spawned);
    logmod.nl();
    if (n_spawned == 0) {
        filemod.close(&out);
        std_net.cleanup();
        var zmsg: []const u8 = "z9torr: peer error\n";
        std.io.write(zmsg);
        logExitAnd(@intCast(i32, cli.exitCodeFor(cli.FailureClass.peer)), "peer error: no peers spawned");
        return;
    }

    // The async scheduler is sized to the full slot capacity so PEX dynamic
    // spawns can register new tasks later; only started slots are added now.
    var sched = std.async.schedulerInit(g_task_ptrs[0..g_sched.peers.len]);
    var ti: usize = 0;
    while (ti < g_sched.peers.len) : (ti += 1) {
        if (g_started[ti]) _ = std.async.addTask(&sched, g_task_ptrs[ti]);
    }

    // Drive the peers. `tick` resumes every live peer once; stop as soon as all
    // pieces verify, no peer is live, or nothing has progressed for `STALL_MS`.
    // A 1 Hz sampled progress line renders through `statsRender`.
    var last_progress_ms: u32 = std.time.ticksMs();
    var last_verified: u32 = g_pctx.verified_count;
    var last_progress_bytes: u64 = 0;
    var line_buf: [statsmod.STATS_LINE_MAX]u8 = undefined;
    var st: trackerlib.Stats = zeroStats();
    var last_sample_ms: u32 = std.time.ticksMs();
    var last_down_bytes: u64 = 0;
    var last_up_bytes: u64 = 0;
    var win_idx: u32 = 0;
    // Global buckets refill on a 100 ms cadence (spec §9); the per-send path
    // only charges, so a low rate is not lost to per-call integer truncation.
    var last_refill_ms: u32 = now0;

    while (true) {
        var nowr: u32 = std.time.ticksMs();
        if (nowr - last_refill_ms >= 100) {
            ratelimit.refill(&g_down_bucket, nowr);
            ratelimit.refill(&g_up_bucket, nowr);
            last_refill_ms = nowr;
        }
        std.async.tick(&sched) catch {};

        // Operator ruling #3: retire every peer whose task has finished so its
        // availability bits stop inflating `piece_rarest` and the stats peer
        // count tracks live peers only. `removePeer` returns early when the
        // slot is already inactive, so repeated calls are safe; a peer whose
        // task is still live is left untouched.
        var rj: usize = 0;
        while (rj < g_sched.peers.len) : (rj += 1) {
            if (!g_started[rj]) continue;
            var rts = g_tasks[rj].state;
            if (rts == std.async.TaskState.done or rts == std.async.TaskState.cancelled) {
                schedmod.removePeer(&g_sched, &g_sched.peers[rj]);
                g_started[rj] = false;
            }
        }

        // M4: PEX adds peers to the scheduler via `scheduler.addPeer` mid-run.
        // Spawn a coroutine for every active slot that has none yet, using the
        // same `spawnPeerAt` path as the startup candidates, so discovered peers
        // are actually dialed (not merely added).
        var ds: usize = 0;
        while (ds < g_sched.peers.len) : (ds += 1) {
            if (g_sched.peers[ds].active and !g_started[ds]) {
                spawnPeerAt(ds, peer_id);
                g_started[ds] = true;
                _ = std.async.addTask(&sched, g_task_ptrs[ds]);
                logmod.s("dyn spawn slot=");
                logmod.u32v(@intCast(u32, ds));
                logmod.s(" port=");
                logmod.u32v(@intCast(u32, g_sched.peers[ds].addr.port));
                logmod.nl();
            }
        }

        if (g_pctx.verified_count != last_verified) {
            last_verified = g_pctx.verified_count;
            last_progress_ms = std.time.ticksMs();
        }
        // Fix 2: a slow/throttled run that is still receiving bytes must not
        // trip the stall detector. Sum received payload across every slot (idle
        // slots are zero; a PEX-reused slot restarts at zero, so the sum can
        // drop) and treat any change as progress. The `!=` test keeps the u64
        // math underflow-safe.
        var dnow: u64 = 0;
        var dj: usize = 0;
        while (dj < g_sched.peers.len) : (dj += 1) {
            dnow += g_sched.peers[dj].down_bytes;
        }
        if (dnow != last_progress_bytes) {
            last_progress_bytes = dnow;
            last_progress_ms = std.time.ticksMs();
        }
        if (g_pctx.verified_count >= n_pieces) break;
        if (std.time.ticksMs() - last_progress_ms > STALL_MS) break;

        var live: bool = false;
        var lt: usize = 0;
        while (lt < g_sched.peers.len) : (lt += 1) {
            if (!g_started[lt]) continue;
            var ts = g_tasks[lt].state;
            if (ts != std.async.TaskState.done and ts != std.async.TaskState.cancelled) live = true;
        }
        if (!live) break;

        var nowm: u32 = std.time.ticksMs();
        if (nowm - last_sample_ms >= 1000) {
            var dsum: u64 = 0;
            var usum: u64 = 0;
            var pc: u32 = 0;
            var pj: usize = 0;
            while (pj < g_sched.peers.len) : (pj += 1) {
                if (g_sched.peers[pj].active) {
                    dsum += g_sched.peers[pj].down_bytes;
                    usum += g_sched.peers[pj].up_bytes;
                    pc += 1;
                }
            }
            // Clamp to zero: `removePeer` (ruling #3) drops a retired peer's
            // bytes out of the active-only sum, and a reused slot starts at
            // zero, so the new sample can fall below the previous one. An
            // unsigned subtraction would underflow into a garbage rate.
            var ddelta: u64 = 0;
            if (dsum >= last_down_bytes) {
                ddelta = dsum - last_down_bytes;
            }
            var udelta: u64 = 0;
            if (usum >= last_up_bytes) {
                udelta = usum - last_up_bytes;
            }
            last_down_bytes = dsum;
            last_up_bytes = usum;
            st.window_down[@intCast(usize, win_idx)] = @intCast(u32, ddelta);
            st.window_up[@intCast(usize, win_idx)] = @intCast(u32, udelta);
            win_idx = (win_idx + 1) % 5;
            st.window_idx = win_idx;
            st.downloaded = verifiedBytes(t, rstate.completed_bits, n_pieces);
            if (st.downloaded > t.total_length) st.downloaded = t.total_length;
            st.left = t.total_length - st.downloaded;
            st.peer_count = pc;
            st.down_rate = @intCast(u32, ddelta);
            st.up_rate = @intCast(u32, udelta);
            st.started_ms = now0;
            var ln: []const u8 = statsmod.statsRender(&st, line_buf[0..]);
            // Console: rewrite the line in place with '\r'. Redirected: one
            // line per refresh ('\n') so the log is not a stream of raw CRs.
            if (stdout_console) {
                var cr: []const u8 = "\r";
                std.io.write(cr);
                std.io.write(ln);
            } else {
                std.io.write(ln);
                var lf: []const u8 = "\n";
                std.io.write(lf);
            }
            last_sample_ms = nowm;
        }
    }

    filemod.close(&out);

    if (g_pctx.verified_count < n_pieces) {
        std_net.cleanup();
        var emsg: []const u8 = "z9torr: peer error\n";
        std.io.write(emsg);
        logExitAnd(@intCast(i32, g_pctx.exit_class), "peer incomplete");
        return;
    }

    var stats2 = zeroStats();
    stats2.downloaded = t.total_length;
    _ = announceTracked(&arena, t, peer_id, @intCast(u16, 6881), trackerlib.AnnounceEvent.completed, stats2) catch {};
    logmod.s("completed");
    logmod.nl();

    // Redirected stdout ends every progress line with '\n', so the success
    // line needs no leading '\n' (the console path terminates the in-place
    // progress line with one).
    if (stdout_console) {
        var okline: []const u8 = "\nz9torr: download complete\n";
        std.io.write(okline);
    } else {
        var okline2: []const u8 = "z9torr: download complete\n";
        std.io.write(okline2);
    }

    // B3=A: one-line fetch metric for tier2's resume gate. `down_bytes` is the
    // received `piece` payload total; `up_bytes` is 13 bytes per request message
    // (peer.zig sendRequests), so requests = up_bytes / 13. Sum over every slot
    // (idle slots were zeroed at startup; a retired peer's bytes are retained
    // unless its slot was reused).
    var total_down: u64 = 0;
    var total_up: u64 = 0;
    var sj: usize = 0;
    while (sj < g_sched.peers.len) : (sj += 1) {
        total_down += g_sched.peers[sj].down_bytes;
        total_up += g_sched.peers[sj].up_bytes;
    }
    var sline: []const u8 = "summary: fetched=";
    writeText(sline);
    writeU64(total_down);
    var rline: []const u8 = " requests=";
    writeText(rline);
    writeU64(total_up / 13);
    writeText(nl);
    logmod.s("summary fetched=");
    logmod.u64v(total_down);
    logmod.s(" requests=");
    logmod.u64v(total_up / 13);
    logmod.nl();

    std_net.cleanup();
    logExitAnd(0, "ok");
}
