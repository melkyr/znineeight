const std = @import("std");
const filemod = @import("std_file");
const ogg = @import("ogg.zig");
const vi = @import("vorbis_info.zig");
const vs = @import("vorbis_setup.zig");
const dec = @import("decode.zig");
const audio = @import("platform/audio.zig");
const wav = @import("platform/audio_wavfile.zig");
const oss = @import("platform/audio_oss.zig");
const awin = @import("platform/audio_win9x.zig");
const con = @import("platform/console_linux.zig");
const cwin = @import("platform/console_win9x.zig");
const contract = @import("platform/console.zig");
const fmt = @import("fmt.zig");
const decoder = @import("decoder.zig");
const flac = @import("flac.zig");
const player = @import("player.zig");

const WIDTH: usize = 80;
const HEIGHT: usize = 25;
const SEP_COL: usize = 44;
const RIGHT_START: usize = 45;
const LIST_FIRST_ROW: usize = 2;
const LIST_ROWS: usize = 19;
const PANE_LAST_ROW: usize = 20;
const SEP_ROW: usize = 21;
const HELP1_ROW: usize = 22;
const HELP2_ROW: usize = 23;
const BOTTOM_ROW: usize = HEIGHT - 1;

const PATH_BUF: usize = 4096;
const MAX_ENTRIES: usize = 512;
const PLAYLIST_MAX: usize = 256;
const MIX_MAX: usize = 88200;

const UI_ARENA_SIZE: usize = 1024 * 1024;
const DIR_ARENA_SIZE: usize = 1024 * 1024;
const FILE_ARENA_SIZE: usize = 4 * 1024 * 1024;
const DEC_ARENA_SIZE: usize = 16 * 1024 * 1024;
const SCRATCH_ARENA_SIZE: usize = 8 * 1024 * 1024;
const PLAYER_ARENA_SIZE: usize = 2 * 1024 * 1024;

var g_ui_buf: [UI_ARENA_SIZE]u8 = undefined;
var g_dir_buf: [DIR_ARENA_SIZE]u8 = undefined;
var g_file_buf: [FILE_ARENA_SIZE]u8 = undefined;
var g_dec_buf: [DEC_ARENA_SIZE]u8 = undefined;
var g_scratch_buf: [SCRATCH_ARENA_SIZE]u8 = undefined;
var g_player_buf: [PLAYER_ARENA_SIZE]u8 = undefined;

var g_ui_arena: std.arena.Arena = undefined;
var g_dir_arena: std.arena.Arena = undefined;
var g_file_arena: std.arena.Arena = undefined;
var g_dec_arena: std.arena.Arena = undefined;
var g_scratch_arena: std.arena.Arena = undefined;
var g_player_arena: std.arena.Arena = undefined;

var g_path_buf: [PATH_BUF]u8 = undefined;
var g_path_len: usize = 0;
var g_current_buf: [PATH_BUF]u8 = undefined;
var g_current_len: usize = 0;

var g_entries: []filemod.DirEntry = undefined;
var g_entry_count: usize = 0;
var g_cursor: usize = 0;
var g_scroll: usize = 0;
var g_has_parent: bool = false;

var g_status_buf: [128]u8 = undefined;
var g_status: []const u8 = "";

var g_playlist: [PLAYLIST_MAX][]const u8 = undefined;
var g_playlist_len: usize = 0;
var g_playlist_index: usize = 0;
var g_playlist_has_current: bool = false;

var g_has_track: bool = false;
var g_volume: u8 = 80;
var g_base_ticks: u32 = 0;
var g_paused_accum: u64 = 0;
var g_pause_began: u32 = 0;

var g_mix_buf: [MIX_MAX]i16 = undefined;
var g_mix_vol: u8 = 80;
var g_real: audio.AudioOut = undefined;
var g_mix_ao: audio.AudioOut = undefined;
var g_decoder: player.Decoder = undefined;
var g_flac: flac.StreamFlacDecoder = undefined;
var g_flac_open: bool = false;
var g_player: player.Player = undefined;

fn fillSpaces(buf: []u8) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = ' ';
    }
}

fn putAt(buf: []u8, x: usize, s: []const u8) usize {
    if (x >= buf.len) return 0;
    var n: usize = s.len;
    if (n > buf.len - x) n = buf.len - x;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[x + i] = s[i];
    }
    return n;
}

fn putAtClip(buf: []u8, x: usize, limit: usize, s: []const u8) usize {
    if (x >= buf.len) return 0;
    if (x >= limit) return 0;
    var n: usize = s.len;
    var max: usize = limit - x;
    if (max > buf.len - x) max = buf.len - x;
    if (n > max) n = max;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[x + i] = s[i];
    }
    return n;
}

fn putU64(buf: []u8, x: usize, v_in: u64) usize {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var v: u64 = v_in;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (v > 0) {
            tmp[n] = @intCast(u8, v % 10) + '0';
            v = v / 10;
            n += 1;
        }
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (x + i < buf.len) buf[x + i] = tmp[n - 1 - i];
    }
    return n;
}

fn setStatus(s: []const u8) void {
    var n: usize = s.len;
    if (n > g_status_buf.len) n = g_status_buf.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        g_status_buf[i] = s[i];
    }
    g_status = g_status_buf[0..n];
}

fn sepChar() u8 {
    if (@isWindows()) return '\\';
    return '/';
}

fn isSep(c: u8) bool {
    if (c == '/') return true;
    if (@isWindows()) {
        if (c == '\\') return true;
    }
    return false;
}

fn isRootPath(p: []const u8) bool {
    if (@isWindows()) {
        if (p.len == 2) {
            if (p[1] == ':') return true;
        }
        if (p.len == 3) {
            if (p[1] == ':' and isSep(p[2])) return true;
        }
        if (p.len == 1) {
            if (isSep(p[0])) return true;
        }
        return false;
    }
    if (p.len == 1 and p[0] == '/') return true;
    return false;
}

fn copyPath(path: []const u8) bool {
    var n: usize = path.len;
    if (n > PATH_BUF) return false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        g_path_buf[i] = path[i];
    }
    g_path_len = n;
    return true;
}

fn buildPath(out: []u8, dir: []const u8, name: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < dir.len and n < out.len) : (i += 1) {
        out[n] = dir[i];
        n += 1;
    }
    if (n > 0) {
        if (!isSep(out[n - 1])) {
            if (n < out.len) {
                out[n] = sepChar();
                n += 1;
            }
        }
    }
    i = 0;
    while (i < name.len and n < out.len) : (i += 1) {
        out[n] = name[i];
        n += 1;
    }
    return n;
}

fn parentPath(out: []u8, path: []const u8) usize {
    var n: usize = path.len;
    while (n > 1 and isSep(path[n - 1])) {
        n -= 1;
    }
    if (n == 0) return 0;
    var i: usize = n;
    while (i > 0 and !isSep(path[i - 1])) {
        i -= 1;
    }
    if (i == 0) return 0;
    var end: usize = i - 1;
    if (end == 0) {
        if (@isWindows()) {
            if (path.len > 0) {
                out[0] = path[0];
                return 1;
            }
            return 0;
        }
        out[0] = '/';
        return 1;
    }
    if (@isWindows()) {
        if (end == 2 and path[1] == ':') {
            out[0] = path[0];
            out[1] = path[1];
            out[2] = '\\';
            return 3;
        }
    }
    var k: usize = 0;
    while (k < end) : (k += 1) {
        out[k] = path[k];
    }
    return end;
}

fn baseName(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0 and !isSep(path[i - 1])) {
        i -= 1;
    }
    return path[i..path.len];
}

fn isDotOrDotDot(name: []const u8) bool {
    if (name.len == 1) {
        if (name[0] == '.') return true;
    }
    if (name.len == 2) {
        if (name[0] == '.' and name[1] == '.') return true;
    }
    return false;
}

fn suffixIgnoreCase(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    var off: usize = s.len - suffix.len;
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        var a: u8 = s[off + i];
        var b: u8 = suffix[i];
        if (a >= 'A' and a <= 'Z') a += 32;
        if (b >= 'A' and b <= 'Z') b += 32;
        if (a != b) return false;
    }
    return true;
}

fn isAudioName(name: []const u8) bool {
    if (suffixIgnoreCase(name, ".ogg")) return true;
    if (suffixIgnoreCase(name, ".flac")) return true;
    return false;
}

fn strLess(a: []const u8, b: []const u8) bool {
    var n: usize = a.len;
    if (b.len < n) n = b.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (a[i] < b[i]) return true;
        if (a[i] > b[i]) return false;
    }
    return a.len < b.len;
}

fn entryLess(a: filemod.DirEntry, b: filemod.DirEntry) bool {
    if (a.is_dir != b.is_dir) return a.is_dir;
    return strLess(a.name, b.name);
}

fn sortEntries(items: []filemod.DirEntry) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        var j: usize = i;
        while (j > 0) {
            if (entryLess(items[j], items[j - 1])) {
                var t: filemod.DirEntry = items[j];
                items[j] = items[j - 1];
                items[j - 1] = t;
                j -= 1;
            } else {
                break;
            }
        }
    }
}

fn loadDir(path: []const u8) void {
    if (!copyPath(path)) {
        setStatus("path too long");
        return;
    }
    std.arena.reset(&g_dir_arena);
    g_entry_count = 0;
    g_cursor = 0;
    g_scroll = 0;
    g_has_parent = !isRootPath(g_path_buf[0..g_path_len]);

    var raw: [*]u8 = std.arena.alloc(&g_dir_arena, MAX_ENTRIES * @sizeOf(filemod.DirEntry)) catch {
        setStatus("out of memory");
        return;
    };
    g_entries = @ptrCast([*]filemod.DirEntry, raw)[0..MAX_ENTRIES];

    var d: filemod.Dir = filemod.openDir(&g_dir_arena, g_path_buf[0..g_path_len]) catch {
        setStatus("cannot open directory");
        return;
    };

    var reading: bool = true;
    while (reading) {
        var maybe: ?filemod.DirEntry = filemod.readDir(&g_dir_arena, &d) catch null;
        if (maybe) |e| {
            if (!isDotOrDotDot(e.name)) {
                var keep: bool = e.is_dir;
                if (!keep) keep = isAudioName(e.name);
                if (keep) {
                    if (g_entry_count < MAX_ENTRIES) {
                        g_entries[g_entry_count] = e;
                        g_entry_count += 1;
                    }
                }
            }
        } else {
            reading = false;
        }
    }
    filemod.closeDir(&d);
    sortEntries(g_entries[0..g_entry_count]);
    setStatus("");
}

fn selectedEntryIndex() ?usize {
    var idx: usize = g_cursor;
    if (g_has_parent) {
        if (idx == 0) return null;
        idx -= 1;
    }
    if (idx >= g_entry_count) return null;
    return idx;
}

fn cursorDown() void {
    var total: usize = g_entry_count;
    if (g_has_parent) total += 1;
    if (g_cursor + 1 < total) g_cursor += 1;
}

fn cursorUp() void {
    if (g_cursor > 0) g_cursor -= 1;
}

fn mixOpen(rate: u32, channels: u8) audio.AudioError!*void {
    return g_real.open_fn(rate, channels);
}

fn mixWrite(state: *void, samples: []const i16) audio.AudioError!usize {
    var off: usize = 0;
    while (off < samples.len) {
        var n: usize = samples.len - off;
        if (n > MIX_MAX) n = MIX_MAX;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var s: i32 = @intCast(i32, samples[off + i]);
            s = s * @intCast(i32, g_mix_vol) / 100;
            g_mix_buf[i] = @intCast(i16, s);
        }
        var w: usize = g_real.write_fn(state, g_mix_buf[0..n]) catch return error.WriteFailed;
        if (w != n) return error.WriteFailed;
        off += n;
    }
    return samples.len;
}

fn mixClose(state: *void) void {
    g_real.close_fn(state);
}

fn mixDrain(state: *void) audio.AudioError!void {
    g_real.drain_fn(state) catch return error.DeviceError;
}

fn openBackend(rate: u32, channels: u8) bool {
    var wav_env: []const u8 = "Z9PLAY_WAV_OUT";
    var use_wav: bool = false;
    var env_path: []const u8 = "";
    if (std.os.env(wav_env)) |e| {
        use_wav = true;
        env_path = e;
    }
    if (use_wav) {
        wav.setOutputPath(env_path);
        var ctx: *void = wav.open(rate, channels) catch return false;
        g_real = audio.AudioOut{
            .open_fn = wav.open,
            .write_fn = wav.write,
            .close_fn = wav.close,
            .drain_fn = wav.drain,
            .state = ctx,
        };
        return true;
    } else if (@isWindows()) {
        var wctx: *void = awin.open(rate, channels) catch return false;
        g_real = audio.AudioOut{
            .open_fn = awin.open,
            .write_fn = awin.write,
            .close_fn = awin.close,
            .drain_fn = awin.drain,
            .state = wctx,
        };
        return true;
    } else {
        var octx: *void = oss.open(rate, channels) catch return false;
        g_real = audio.AudioOut{
            .open_fn = oss.open,
            .write_fn = oss.write,
            .close_fn = oss.close,
            .drain_fn = oss.drain,
            .state = octx,
        };
        return true;
    }
}

fn stopPlayback() void {
    if (g_flac_open) {
        flac.closeStream(&g_flac);
        g_flac_open = false;
    }
    if (!g_has_track) return;
    g_player.audio.drain_fn(g_player.audio.state) catch {};
    g_player.audio.close_fn(g_player.audio.state);
    g_has_track = false;
}

fn tagValue(tags: []vi.Tag, key: []const u8) []const u8 {
    var i: usize = 0;
    while (i < tags.len) : (i += 1) {
        if (std.str.eql(tags[i].key, key)) return tags[i].value;
    }
    var empty: []const u8 = "";
    return empty;
}

fn playTrack(path: []const u8) bool {
    stopPlayback();

    std.arena.reset(&g_file_arena);
    std.arena.reset(&g_dec_arena);
    std.arena.reset(&g_scratch_arena);
    std.arena.reset(&g_player_arena);

    var data: []u8 = filemod.readAll(&g_file_arena, path) catch {
        setStatus("cannot open track");
        return false;
    };
    var kind: u8 = decoder.detectKind(data);
    var sr: u32 = 0;
    var chn: u8 = 0;
    var title_val: []const u8 = "";
    var artist_val: []const u8 = "";
    var album_val: []const u8 = "";

    if (kind == decoder.KIND_FLAC) {
        g_flac = flac.openStream(&g_dec_arena, path) catch {
            setStatus("corrupt or unsupported FLAC stream");
            return false;
        };
        g_flac_open = true;
        sr = g_flac.sample_rate;
        chn = g_flac.channels;
        decoder.decoderOpenFlac(&g_decoder, &g_flac);
    } else {
        var packets: []ogg.Packet = ogg.reassemble(&g_file_arena, data) catch {
            setStatus("not an OGG Vorbis stream");
            return false;
        };
        if (packets.len < 3) {
            setStatus("missing Vorbis headers");
            return false;
        }
        var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
            setStatus("bad Vorbis identification header");
            return false;
        };
        var comment: vi.Comment = vi.parseComment(&g_file_arena, packets[1].bytes) catch {
            setStatus("bad Vorbis comment header");
            return false;
        };
        var last: u64 = ogg.lastGranule(&g_file_arena, data) catch {
            setStatus("cannot locate the audio granule");
            return false;
        };
        var setup: vs.Setup = vs.parseSetup(&g_dec_arena, packets[2].bytes, @intCast(u32, id.channels)) catch {
            setStatus("bad Vorbis setup header");
            return false;
        };
        var state: dec.DecoderState = dec.initDecoderState(&g_dec_arena, setup, id.channels, id.blocksize_0, id.blocksize_1) catch {
            setStatus("cannot initialize the decoder");
            return false;
        };
        var vc: *player.VorbisCtx = player.vorbisCreate(&g_dec_arena, &g_scratch_arena, packets, setup, state, 3, id.sample_rate, id.channels, last) catch {
            setStatus("cannot initialize the player decoder");
            return false;
        };

        sr = id.sample_rate;
        chn = id.channels;
        decoder.decoderOpenVorbis(&g_decoder, vc);

        var k_title: []const u8 = "TITLE";
        var k_artist: []const u8 = "ARTIST";
        var k_album: []const u8 = "ALBUM";
        title_val = tagValue(comment.tags, k_title);
        artist_val = tagValue(comment.tags, k_artist);
        album_val = tagValue(comment.tags, k_album);
    }

    if (!openBackend(sr, chn)) {
        if (g_flac_open) {
            flac.closeStream(&g_flac);
            g_flac_open = false;
        }
        setStatus("cannot open audio output");
        return false;
    }
    g_mix_ao = audio.AudioOut{
        .open_fn = mixOpen,
        .write_fn = mixWrite,
        .close_fn = mixClose,
        .drain_fn = mixDrain,
        .state = g_real.state,
    };
    var title_opt: ?[]const u8 = null;
    if (title_val.len > 0) title_opt = title_val;
    var artist_opt: ?[]const u8 = null;
    if (artist_val.len > 0) artist_opt = artist_val;
    var album_opt: ?[]const u8 = null;
    if (album_val.len > 0) album_opt = album_val;
    var meta: player.Meta = player.Meta{ .title = title_opt, .artist = artist_opt, .album = album_opt };

    player.playerInit(&g_player, &g_player_arena, &g_decoder, &g_mix_ao, meta) catch {
        g_real.close_fn(g_real.state);
        if (g_flac_open) {
            flac.closeStream(&g_flac);
            g_flac_open = false;
        }
        setStatus("cannot initialize the player");
        return false;
    };

    g_mix_vol = g_volume;
    g_player.volume = g_volume;
    g_has_track = true;
    g_current_len = path.len;
    if (g_current_len > PATH_BUF) g_current_len = PATH_BUF;
    var i: usize = 0;
    while (i < g_current_len) : (i += 1) {
        g_current_buf[i] = path[i];
    }
    g_base_ticks = std.time.ticksMs();
    g_paused_accum = 0;
    g_pause_began = 0;
    setStatus("");
    return true;
}

fn syncPlaylistCurrent() void {
    var i: usize = 0;
    while (i < g_playlist_len) : (i += 1) {
        if (std.str.eql(g_playlist[i], g_current_buf[0..g_current_len])) {
            g_playlist_index = i;
            g_playlist_has_current = true;
            return;
        }
    }
    g_playlist_has_current = false;
}

fn addToPlaylist(path: []const u8) void {
    if (g_playlist_len >= PLAYLIST_MAX) {
        setStatus("playlist full");
        return;
    }
    var i: usize = 0;
    while (i < g_playlist_len) : (i += 1) {
        if (std.str.eql(g_playlist[i], path)) {
            setStatus("already in playlist");
            return;
        }
    }
    var raw: [*]u8 = std.arena.alloc(&g_ui_arena, path.len) catch {
        setStatus("out of memory");
        return;
    };
    i = 0;
    while (i < path.len) : (i += 1) {
        raw[i] = path[i];
    }
    g_playlist[g_playlist_len] = raw[0..path.len];
    g_playlist_len += 1;
    setStatus("added to playlist");
}

fn removeCurrentFromPlaylist() void {
    if (!g_has_track) {
        setStatus("no track");
        return;
    }
    var idx: usize = 0;
    var found: bool = false;
    while (idx < g_playlist_len) : (idx += 1) {
        if (std.str.eql(g_playlist[idx], g_current_buf[0..g_current_len])) {
            found = true;
            break;
        }
    }
    if (!found) {
        setStatus("not in playlist");
        return;
    }
    var j: usize = idx;
    while (j + 1 < g_playlist_len) : (j += 1) {
        g_playlist[j] = g_playlist[j + 1];
    }
    g_playlist_len -= 1;
    if (g_playlist_has_current) {
        if (g_playlist_len == 0) {
            g_playlist_has_current = false;
            g_playlist_index = 0;
        } else if (g_playlist_index > idx) {
            g_playlist_index -= 1;
        } else if (g_playlist_index == idx) {
            if (g_playlist_index >= g_playlist_len) g_playlist_index = g_playlist_len - 1;
        }
    }
    setStatus("removed from playlist");
}

fn playlistStep(forward: bool) void {
    if (g_playlist_len == 0) {
        setStatus("playlist empty");
        return;
    }
    var idx: usize = 0;
    if (!g_playlist_has_current) {
        if (forward) {
            idx = 0;
        } else {
            idx = g_playlist_len - 1;
        }
    } else if (forward) {
        idx = g_playlist_index + 1;
        if (idx >= g_playlist_len) idx = 0;
    } else {
        if (g_playlist_index == 0) {
            idx = g_playlist_len - 1;
        } else {
            idx = g_playlist_index - 1;
        }
    }
    if (playTrack(g_playlist[idx])) {
        g_playlist_index = idx;
        g_playlist_has_current = true;
    }
}

fn togglePause() void {
    if (!g_has_track) return;
    if (g_player.state == player.PlayerState.playing) {
        g_player.state = player.PlayerState.paused;
        g_pause_began = std.time.ticksMs();
    } else if (g_player.state == player.PlayerState.paused) {
        g_player.state = player.PlayerState.playing;
        g_paused_accum += @intCast(u64, std.time.ticksMs() - g_pause_began);
    }
}

fn applyVolume() void {
    g_mix_vol = g_volume;
    if (g_has_track) g_player.volume = g_volume;
}

fn volumeUp() void {
    if (g_volume <= 95) {
        g_volume += 5;
    } else {
        g_volume = 100;
    }
    applyVolume();
}

fn volumeDown() void {
    if (g_volume >= 5) {
        g_volume -= 5;
    } else {
        g_volume = 0;
    }
    applyVolume();
}

fn navigateUp() void {
    if (g_has_parent == false) return;
    var tmp: [PATH_BUF]u8 = undefined;
    var n: usize = parentPath(tmp[0..], g_path_buf[0..g_path_len]);
    if (n == 0) return;
    loadDir(tmp[0..n]);
}

fn navigateInto(name: []const u8) void {
    var tmp: [PATH_BUF]u8 = undefined;
    var n: usize = buildPath(tmp[0..], g_path_buf[0..g_path_len], name);
    loadDir(tmp[0..n]);
}

fn activateSelected() void {
    if (g_has_parent) {
        if (g_cursor == 0) {
            navigateUp();
            return;
        }
    }
    if (selectedEntryIndex()) |idx| {
        var e: filemod.DirEntry = g_entries[idx];
        if (e.is_dir) {
            navigateInto(e.name);
            return;
        }
        var tmp: [PATH_BUF]u8 = undefined;
        var n: usize = buildPath(tmp[0..], g_path_buf[0..g_path_len], e.name);
        if (playTrack(tmp[0..n])) {
            syncPlaylistCurrent();
        }
    }
}

fn addSelected() void {
    if (selectedEntryIndex()) |idx| {
        var e: filemod.DirEntry = g_entries[idx];
        if (e.is_dir) {
            setStatus("select a file");
            return;
        }
        var tmp: [PATH_BUF]u8 = undefined;
        var n: usize = buildPath(tmp[0..], g_path_buf[0..g_path_len], e.name);
        addToPlaylist(tmp[0..n]);
    } else {
        setStatus("select a file");
    }
}

fn handleKey(k: contract.Key, quit: *bool) void {
    switch (k) {
        .char => |c| {
            if (c == 'q') {
                quit.* = true;
            } else if (c == 'j') {
                cursorDown();
            } else if (c == 'k') {
                cursorUp();
            } else if (c == 'a') {
                addSelected();
            } else if (c == 'd') {
                removeCurrentFromPlaylist();
            } else if (c == 'n') {
                playlistStep(true);
            } else if (c == 'p') {
                playlistStep(false);
            } else if (c == ' ') {
                togglePause();
            } else if (c == '+' or c == '=') {
                volumeUp();
            } else if (c == '-') {
                volumeDown();
            }
        },
        .up => {
            cursorUp();
        },
        .down => {
            cursorDown();
        },
        .enter => {
            activateSelected();
        },
        .sigint => {
            quit.* = true;
        },
        .none => {},
        else => {},
    }
}

fn topRow(buf: []u8) void {
    var i: usize = 0;
    while (i < WIDTH) : (i += 1) {
        buf[i] = '-';
    }
    buf[0] = '+';
    buf[WIDTH - 1] = '+';
    _ = putAt(buf, 1, " z9play ");
}

fn contentRow(buf: []u8) void {
    fillSpaces(buf);
    buf[0] = '|';
    buf[SEP_COL] = '|';
    buf[WIDTH - 1] = '|';
}

fn separatorRow(buf: []u8) void {
    var i: usize = 0;
    while (i < WIDTH) : (i += 1) {
        buf[i] = '-';
    }
    buf[0] = '+';
    buf[SEP_COL] = '+';
    buf[WIDTH - 1] = '+';
}

fn helpRow(buf: []u8, text: []const u8) void {
    fillSpaces(buf);
    buf[0] = '|';
    buf[WIDTH - 1] = '|';
    _ = putAtClip(buf, 1, WIDTH - 1, text);
}

fn bottomRow(buf: []u8) void {
    var i: usize = 0;
    while (i < WIDTH) : (i += 1) {
        buf[i] = '-';
    }
    buf[0] = '+';
    buf[WIDTH - 1] = '+';
}

fn drawLine(cs: *contract.Console, row: usize, buf: []const u8) void {
    cs.setCursor_fn(cs.state, @intCast(u16, row), 0);
    cs.writeStr_fn(cs.state, buf);
}

fn putBar(buf: []u8, x: usize, pos_ms: u64, dur_ms: u64) void {
    buf[x] = '[';
    var filled: usize = 0;
    if (dur_ms > 0) {
        if (pos_ms >= dur_ms) {
            filled = 20;
        } else {
            filled = @intCast(usize, (pos_ms * 20) / dur_ms);
        }
    }
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (i < filled) {
            buf[x + 1 + i] = '#';
        } else {
            buf[x + 1 + i] = '-';
        }
    }
    buf[x + 21] = ']';
}

fn renderRight(buf: []u8, row: usize) void {
    if (!g_has_track) {
        if (row == 10) {
            if (g_status.len > 0) {
                _ = putAtClip(buf, RIGHT_START, WIDTH - 1, "Status: ");
                _ = putAtClip(buf, RIGHT_START + 8, WIDTH - 1, g_status);
            }
        }
        return;
    }
    if (row == 2) {
        var pos_buf: [fmt.MMSS_MAX]u8 = undefined;
        var dur_buf: [fmt.MMSS_MAX]u8 = undefined;
        var pos: []const u8 = fmt.mmss(pos_buf[0..], player.playerPositionMs(&g_player));
        var dur: []const u8 = fmt.mmss(dur_buf[0..], g_player.duration_ms);
        var x: usize = RIGHT_START;
        x += putAtClip(buf, x, WIDTH - 1, pos);
        x += putAtClip(buf, x, WIDTH - 1, " / ");
        _ = putAtClip(buf, x, WIDTH - 1, dur);
    } else if (row == 3) {
        var x: usize = RIGHT_START;
        x += putAtClip(buf, x, WIDTH - 1, "vol ");
        x += putU64(buf, x, @intCast(u64, g_volume));
        _ = putAtClip(buf, x, WIDTH - 1, "%");
    } else if (row == 4) {
        putBar(buf, RIGHT_START, player.playerPositionMs(&g_player), g_player.duration_ms);
    } else if (row == 5) {
        if (g_player.title) |t| {
            _ = putAtClip(buf, RIGHT_START, WIDTH - 1, "Title: ");
            _ = putAtClip(buf, RIGHT_START + 7, WIDTH - 1, t);
        }
    } else if (row == 6) {
        if (g_player.artist) |a| {
            _ = putAtClip(buf, RIGHT_START, WIDTH - 1, "Artist: ");
            _ = putAtClip(buf, RIGHT_START + 8, WIDTH - 1, a);
        }
    } else if (row == 7) {
        if (g_player.album) |a| {
            _ = putAtClip(buf, RIGHT_START, WIDTH - 1, "Album: ");
            _ = putAtClip(buf, RIGHT_START + 7, WIDTH - 1, a);
        }
    } else if (row == 8) {
        var st: []const u8 = "Stopped";
        if (g_player.state == player.PlayerState.playing) {
            st = "Playing";
        } else if (g_player.state == player.PlayerState.paused) {
            st = "Paused";
        } else if (g_player.state == player.PlayerState.ended) {
            st = "Ended";
        } else if (g_player.state == player.PlayerState.error_state) {
            st = "Error";
        }
        var x: usize = RIGHT_START;
        x += putAtClip(buf, x, WIDTH - 1, "State: ");
        _ = putAtClip(buf, x, WIDTH - 1, st);
    } else if (row == 9) {
        var x: usize = RIGHT_START;
        x += putAtClip(buf, x, WIDTH - 1, "Playlist: ");
        _ = putU64(buf, x, @intCast(u64, g_playlist_len));
    } else if (row == 10) {
        if (g_status.len > 0) {
            _ = putAtClip(buf, RIGHT_START, WIDTH - 1, "Status: ");
            _ = putAtClip(buf, RIGHT_START + 8, WIDTH - 1, g_status);
        }
    }
}

fn render(cs: *contract.Console) void {
    var buf: [WIDTH]u8 = undefined;

    topRow(buf[0..]);
    drawLine(cs, 0, buf[0..]);

    contentRow(buf[0..]);
    _ = putAtClip(buf[0..], 1, SEP_COL, g_path_buf[0..g_path_len]);
    if (g_has_track) {
        _ = putAtClip(buf[0..], RIGHT_START, WIDTH - 1, "Now: ");
        _ = putAtClip(buf[0..], RIGHT_START + 5, WIDTH - 1, baseName(g_current_buf[0..g_current_len]));
    } else {
        _ = putAtClip(buf[0..], RIGHT_START, WIDTH - 1, "No track");
    }
    drawLine(cs, 1, buf[0..]);

    var total: usize = g_entry_count;
    if (g_has_parent) total += 1;
    if (g_cursor < g_scroll) g_scroll = g_cursor;
    if (total > 0) {
        if (g_scroll + LIST_ROWS <= g_cursor) {
            g_scroll = g_cursor - LIST_ROWS + 1;
        }
        if (g_scroll + LIST_ROWS > total) {
            if (total >= LIST_ROWS) {
                g_scroll = total - LIST_ROWS;
            } else {
                g_scroll = 0;
            }
        }
    } else {
        g_scroll = 0;
    }

    var r: usize = LIST_FIRST_ROW;
    while (r <= PANE_LAST_ROW) : (r += 1) {
        contentRow(buf[0..]);
        var li: usize = r - LIST_FIRST_ROW;
        var gi: usize = g_scroll + li;
        if (gi < total) {
            if (gi == g_cursor) {
                _ = putAt(buf[0..], 1, "> ");
            } else {
                _ = putAt(buf[0..], 1, "  ");
            }
            if (g_has_parent and gi == 0) {
                _ = putAt(buf[0..], 3, "..");
            } else {
                var off: usize = 0;
                if (g_has_parent) off = 1;
                var ei: usize = gi - off;
                if (ei < g_entry_count) {
                    var e: filemod.DirEntry = g_entries[ei];
                    var cnt: usize = putAtClip(buf[0..], 3, SEP_COL, e.name);
                    if (e.is_dir) {
                        if (3 + cnt < SEP_COL) buf[3 + cnt] = '/';
                    }
                }
            }
        }
        renderRight(buf[0..], r);
        drawLine(cs, r, buf[0..]);
    }

    separatorRow(buf[0..]);
    drawLine(cs, SEP_ROW, buf[0..]);

    helpRow(buf[0..], "[Up/Down] or j/k nav  [Enter] play  [a] add  [d] remove  [Space] pause");
    drawLine(cs, HELP1_ROW, buf[0..]);

    helpRow(buf[0..], "[q] quit  [+/-] volume  [n/p] next/prev");
    drawLine(cs, HELP2_ROW, buf[0..]);

    bottomRow(buf[0..]);
    drawLine(cs, BOTTOM_ROW, buf[0..]);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    g_ui_arena = std.arena.init(g_ui_buf[0..]);
    g_dir_arena = std.arena.init(g_dir_buf[0..]);
    g_file_arena = std.arena.init(g_file_buf[0..]);
    g_dec_arena = std.arena.init(g_dec_buf[0..]);
    g_scratch_arena = std.arena.init(g_scratch_buf[0..]);
    g_player_arena = std.arena.init(g_player_buf[0..]);

    var cwd: []u8 = std.os.cwd(&g_dir_arena) catch {
        var msg: []const u8 = "z9play: cannot get current directory\n";
        std.io.write(msg);
        std.os.exit(1);
        return;
    };
    loadDir(cwd);

    var cs: contract.Console = undefined;
    if (@isWindows()) {
        var st_win: cwin.ConsoleWinState = undefined;
        cs = contract.Console{
            .clear_fn = cwin.clear,
            .setCursor_fn = cwin.setCursor,
            .writeStr_fn = cwin.writeStr,
            .readKey_fn = cwin.readKey,
            .enterRaw_fn = cwin.enterRaw,
            .leaveRaw_fn = cwin.leaveRaw,
            .width_fn = cwin.width,
            .height_fn = cwin.height,
            .cursorShow_fn = cwin.cursorShow,
            .state = @ptrCast(*void, &st_win),
        };
    } else {
        var st_lin: con.ConsoleLinState = undefined;
        cs = contract.Console{
            .clear_fn = con.clear,
            .setCursor_fn = con.setCursor,
            .writeStr_fn = con.writeStr,
            .readKey_fn = con.readKey,
            .enterRaw_fn = con.enterRaw,
            .leaveRaw_fn = con.leaveRaw,
            .width_fn = con.width,
            .height_fn = con.height,
            .cursorShow_fn = con.cursorShow,
            .state = @ptrCast(*void, &st_lin),
        };
    }

    cs.enterRaw_fn(cs.state);
    cs.cursorShow_fn(cs.state, false);
    cs.clear_fn(cs.state);
    render(&cs);

    var quit: bool = false;
    var last_render: u32 = std.time.ticksMs();
    var prev_state: player.PlayerState = player.PlayerState.stopped;
    var have_prev: bool = false;

    while (!quit) {
        var got_key: bool = false;
        while (true) {
            var k: contract.Key = cs.readKey_fn(cs.state);
            var is_none: bool = false;
            switch (k) {
                .none => {
                    is_none = true;
                },
                else => {
                    handleKey(k, &quit);
                    got_key = true;
                },
            }
            if (quit) break;
            if (is_none) break;
        }
        if (quit) break;

        if (g_has_track) {
            if (g_player.state == player.PlayerState.playing) {
                var now: u32 = std.time.ticksMs();
                var elapsed: u64 = @intCast(u64, now - g_base_ticks) - g_paused_accum;
                if (g_player.position_ms <= elapsed + 200) {
                    player.playerPump(&g_player) catch |e| {
                        if (e == error.DecodeFailed) {
                            setStatus("playback decode error");
                        } else if (e == error.AudioFailed) {
                            setStatus("audio output failed");
                        } else {
                            setStatus("playback failed");
                        }
                    };
                } else {
                    std.time.sleepMs(10);
                }
            } else {
                std.time.sleepMs(10);
            }
        } else {
            std.time.sleepMs(10);
        }

        var now2: u32 = std.time.ticksMs();
        var cur_state: player.PlayerState = player.PlayerState.stopped;
        if (g_has_track) cur_state = g_player.state;
        var state_changed: bool = false;
        if (!have_prev or prev_state != cur_state) {
            state_changed = true;
            have_prev = true;
            prev_state = cur_state;
        }
        if (got_key or state_changed or now2 - last_render >= 250) {
            render(&cs);
            last_render = now2;
        }
    }

    stopPlayback();
    cs.cursorShow_fn(cs.state, true);
    cs.clear_fn(cs.state);
    cs.leaveRaw_fn(cs.state);
    std.os.exit(0);
}
