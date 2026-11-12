// input_config.zig — configurable z9gb keyboard map (P4 Task 8A).
//
// Pure Z98 free functions only. `InputConfig` binds the nine logical inputs
// (right, left, up, down, a, b, select, start, quit) to a raw keyboard code
// plus the backend tag that produced it (1 = DirectInput8 DIK, 2 =
// GetAsyncKeyState fallback VK). The default table is exactly the DIK table
// std_dinput_pal.mapKeys has always used.
//
// The ini is the literal cwd-relative "z9gb.ini". A backend-tag mismatch, a
// malformed line set, or a duplicate raw code all fall back to the defaults;
// the caller prints loadWarning(status).

const std = @import("std");
const filemod = @import("std_file");
const strmod = @import("std_str");
const backend = @import("platform/backend.zig");

pub const CONFIG_PATH: []const u8 = "z9gb.ini";

pub const KIND_DINPUT8: u8 = 1;
pub const KIND_FALLBACK: u8 = 2;

pub const MAX_CAPTURE_RETRIES: u8 = 3;

pub const KeyBinding = struct {
    raw: u8,
    kind: u8,
};

pub const InputConfig = struct {
    right: KeyBinding,
    left: KeyBinding,
    up: KeyBinding,
    down: KeyBinding,
    a: KeyBinding,
    b: KeyBinding,
    select: KeyBinding,
    start: KeyBinding,
    quit: KeyBinding,
};

pub const LoadStatus = enum { absent, loaded, invalid, duplicate, backend_mismatch };

pub const CaptureState = struct {
    armed: [256]u8,
    done: bool,
    result: u8,
};

const LOAD_BUF_BYTES: usize = 4096;
const SAVE_BUF_BYTES: usize = 2048;
const MASK: u8 = 0x80;

var g_load_buf: [LOAD_BUF_BYTES]u8 = undefined;
var g_save_buf: [SAVE_BUF_BYTES]u8 = undefined;

pub fn configDefaults(kind: u8) InputConfig {
    return InputConfig{
        .right = KeyBinding{ .raw = 0xCD, .kind = kind },
        .left = KeyBinding{ .raw = 0xCB, .kind = kind },
        .up = KeyBinding{ .raw = 0xC8, .kind = kind },
        .down = KeyBinding{ .raw = 0xD0, .kind = kind },
        .a = KeyBinding{ .raw = 0x2C, .kind = kind },
        .b = KeyBinding{ .raw = 0x2D, .kind = kind },
        .select = KeyBinding{ .raw = 0x0E, .kind = kind },
        .start = KeyBinding{ .raw = 0x1C, .kind = kind },
        .quit = KeyBinding{ .raw = 0x01, .kind = kind },
    };
}

pub fn inputName(i: u8) []const u8 {
    if (i == 0) return "right";
    if (i == 1) return "left";
    if (i == 2) return "up";
    if (i == 3) return "down";
    if (i == 4) return "a";
    if (i == 5) return "b";
    if (i == 6) return "select";
    if (i == 7) return "start";
    return "quit";
}

pub fn inputLabel(i: u8) []const u8 {
    if (i == 0) return "Right";
    if (i == 1) return "Left";
    if (i == 2) return "Up";
    if (i == 3) return "Down";
    if (i == 4) return "A";
    if (i == 5) return "B";
    if (i == 6) return "Select";
    if (i == 7) return "Start";
    return "Quit";
}

pub fn bindingAt(cfg: *const InputConfig, i: u8) KeyBinding {
    if (i == 0) return cfg.right;
    if (i == 1) return cfg.left;
    if (i == 2) return cfg.up;
    if (i == 3) return cfg.down;
    if (i == 4) return cfg.a;
    if (i == 5) return cfg.b;
    if (i == 6) return cfg.select;
    if (i == 7) return cfg.start;
    return cfg.quit;
}

pub fn setBinding(cfg: *InputConfig, i: u8, b: KeyBinding) void {
    if (i == 0) {
        cfg.right = b;
    } else if (i == 1) {
        cfg.left = b;
    } else if (i == 2) {
        cfg.up = b;
    } else if (i == 3) {
        cfg.down = b;
    } else if (i == 4) {
        cfg.a = b;
    } else if (i == 5) {
        cfg.b = b;
    } else if (i == 6) {
        cfg.select = b;
    } else if (i == 7) {
        cfg.start = b;
    } else {
        cfg.quit = b;
    }
}

pub fn setBindingRaw(cfg: *InputConfig, i: u8, raw: u8) void {
    var b = bindingAt(cfg, i);
    b.raw = raw;
    setBinding(cfg, i, b);
}

pub fn isDuplicate(cfg: *const InputConfig, logical: u8, raw: u8) bool {
    var i: u8 = 0;
    while (i < 9) : (i += 1) {
        if (i != logical and bindingAt(cfg, i).raw == raw) return true;
    }
    return false;
}

pub fn legacyFixed(raw: u8) []const u8 {
    if (raw == 0xCD) return "right";
    if (raw == 0xCB) return "left";
    if (raw == 0xC8) return "up";
    if (raw == 0xD0) return "down";
    if (raw == 0x2C) return "a";
    if (raw == 0x2D) return "b";
    if (raw == 0x0E) return "select";
    if (raw == 0x1C) return "start";
    if (raw == 0x01) return "quit";
    return "none";
}

fn backendName(kind: u8) []const u8 {
    if (kind == KIND_DINPUT8) return "dinput8";
    if (kind == KIND_FALLBACK) return "fallback";
    return "unknown";
}

fn parseBackendKind(s: []const u8) u8 {
    if (strmod.eqIgnoreCase(s, "dinput8")) return KIND_DINPUT8;
    if (strmod.eqIgnoreCase(s, "fallback")) return KIND_FALLBACK;
    return 0;
}

fn hexVal(c: u8) i32 {
    if (c >= '0' and c <= '9') return @intCast(i32, c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(i32, c - 'a' + 10);
    if (c >= 'A' and c <= 'F') return @intCast(i32, c - 'A' + 10);
    return -1;
}

fn parseRaw(s: []const u8) ?u8 {
    if (s.len < 3) return null;
    if (s[0] != '0' or (s[1] != 'x' and s[1] != 'X')) return null;
    var v: u32 = 0;
    var i: usize = 2;
    while (i < s.len) : (i += 1) {
        const h = hexVal(s[i]);
        if (h < 0) return null;
        v = v * 16 + @intCast(u32, h);
        if (v > 255) return null;
    }
    return @intCast(u8, v);
}

fn logicalIndex(name: []const u8) i32 {
    if (strmod.eqIgnoreCase(name, "right")) return 0;
    if (strmod.eqIgnoreCase(name, "left")) return 1;
    if (strmod.eqIgnoreCase(name, "up")) return 2;
    if (strmod.eqIgnoreCase(name, "down")) return 3;
    if (strmod.eqIgnoreCase(name, "a")) return 4;
    if (strmod.eqIgnoreCase(name, "b")) return 5;
    if (strmod.eqIgnoreCase(name, "select")) return 6;
    if (strmod.eqIgnoreCase(name, "start")) return 7;
    if (strmod.eqIgnoreCase(name, "quit")) return 8;
    return -1;
}

fn configParse(text: []const u8, runtime_kind: u8, out: *InputConfig) LoadStatus {
    var parsed = configDefaults(runtime_kind);
    var seen: [9]u8 = undefined;
    var i: usize = 0;
    while (i < 9) : (i += 1) seen[i] = 0;

    var backend_seen: bool = false;
    var backend_kind: u8 = 0;
    var invalid: bool = false;

    var pos: usize = 0;
    var line_start: usize = 0;
    while (pos <= text.len) : (pos += 1) {
        if (pos == text.len or text[pos] == '\n') {
            const raw_line = strmod.trim(text[line_start..pos]);
            line_start = pos + 1;
            if (raw_line.len != 0 and raw_line[0] != ';' and raw_line[0] != '#' and raw_line[0] != '[') {
                if (strmod.findChar(raw_line, '=')) |ep| {
                    const key = strmod.trim(raw_line[0..ep]);
                    var val = strmod.trim(raw_line[ep + 1..]);
                    if (strmod.findChar(val, ';')) |cp| val = strmod.trim(val[0..cp]);
                    if (strmod.eqIgnoreCase(key, "backend")) {
                        const bk = parseBackendKind(val);
                        if (bk == 0) {
                            invalid = true;
                        } else {
                            backend_kind = bk;
                            backend_seen = true;
                        }
                    } else {
                        const li = logicalIndex(key);
                        if (li >= 0) {
                            const idx: u8 = @intCast(u8, li);
                            const ui: usize = @intCast(usize, idx);
                            if (seen[ui] != 0) {
                                invalid = true;
                            } else if (parseRaw(val)) |raw| {
                                if (raw == 0) {
                                    invalid = true;
                                } else {
                                    var b = bindingAt(&parsed, idx);
                                    b.raw = raw;
                                    b.kind = runtime_kind;
                                    setBinding(&parsed, idx, b);
                                    seen[ui] = 1;
                                }
                            } else {
                                invalid = true;
                            }
                        }
                    }
                }
            }
        }
    }

    if (invalid) return LoadStatus.invalid;
    if (!backend_seen) return LoadStatus.invalid;
    i = 0;
    while (i < 9) : (i += 1) {
        if (seen[i] == 0) return LoadStatus.invalid;
    }

    var a: u8 = 0;
    while (a < 9) : (a += 1) {
        var b: u8 = a + 1;
        while (b < 9) : (b += 1) {
            if (bindingAt(&parsed, a).raw == bindingAt(&parsed, b).raw) return LoadStatus.duplicate;
        }
    }

    if (backend_kind != runtime_kind) return LoadStatus.backend_mismatch;
    out.* = parsed;
    return LoadStatus.loaded;
}

pub fn configLoad(path: []const u8, runtime_kind: u8, out: *InputConfig) LoadStatus {
    out.* = configDefaults(runtime_kind);
    if (!filemod.exists(path)) return LoadStatus.absent;

    var arena_buf: [1]u8 = undefined;
    var arena = std.arena.init(arena_buf[0..]);
    var f = filemod.open(&arena, path, filemod.Mode.Read) catch return LoadStatus.invalid;
    const sz = filemod.size(&f) catch {
        filemod.close(&f);
        return LoadStatus.invalid;
    };
    if (sz < 0 or sz > @intCast(i64, LOAD_BUF_BYTES)) {
        filemod.close(&f);
        return LoadStatus.invalid;
    }
    const n: usize = @intCast(usize, sz);
    var got: usize = 0;
    while (got < n) {
        const r = filemod.read(&f, g_load_buf[got..n]) catch {
            filemod.close(&f);
            return LoadStatus.invalid;
        };
        if (r == 0) break;
        got += r;
    }
    filemod.close(&f);
    if (got != n) return LoadStatus.invalid;
    return configParse(g_load_buf[0..got], runtime_kind, out);
}

pub fn loadWarning(status: LoadStatus) []const u8 {
    if (status == LoadStatus.invalid) return "z9gb: z9gb.ini is malformed; using default keyboard mapping\n";
    if (status == LoadStatus.duplicate) return "z9gb: z9gb.ini has duplicate key codes; using default keyboard mapping\n";
    if (status == LoadStatus.backend_mismatch) return "z9gb: z9gb.ini backend does not match the active input backend; using default keyboard mapping\n";
    return "";
}

fn append(buf: []u8, pos: *usize, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len and pos.* < buf.len) : (i += 1) {
        buf[pos.*] = s[i];
        pos.* += 1;
    }
}

fn hexChar(v: u8) u8 {
    const n: u8 = v & 0x0F;
    if (n < 10) return '0' + n;
    return 'A' + (n - 10);
}

fn appendHexByte(buf: []u8, pos: *usize, v: u8) void {
    if (pos.* < buf.len) {
        buf[pos.*] = hexChar(v >> 4);
        pos.* += 1;
    }
    if (pos.* < buf.len) {
        buf[pos.*] = hexChar(v);
        pos.* += 1;
    }
}

pub fn configSerialize(buf: []u8, cfg: *const InputConfig) usize {
    var pos: usize = 0;
    append(buf, &pos, "[keys]\nbackend=");
    append(buf, &pos, backendName(cfg.right.kind));
    append(buf, &pos, "\n");

    var i: u8 = 0;
    while (i < 9) : (i += 1) {
        const b = bindingAt(cfg, i);
        append(buf, &pos, inputName(i));
        append(buf, &pos, "=0x");
        appendHexByte(buf, &pos, b.raw);
        append(buf, &pos, "\n");
    }
    i = 0;
    while (i < 9) : (i += 1) {
        const b = bindingAt(cfg, i);
        append(buf, &pos, "; ");
        append(buf, &pos, inputName(i));
        append(buf, &pos, " raw=0x");
        appendHexByte(buf, &pos, b.raw);
        append(buf, &pos, " fixed=");
        append(buf, &pos, legacyFixed(b.raw));
        append(buf, &pos, "\n");
    }
    return pos;
}

pub fn configSave(path: []const u8, cfg: *const InputConfig) bool {
    const n = configSerialize(g_save_buf[0..], cfg);
    filemod.writeAll(path, g_save_buf[0..n]) catch return false;
    return true;
}

fn keyDown(raw_keys: []const u8, raw: u8) bool {
    if (raw_keys.len < 256) return false;
    return (raw_keys[@intCast(usize, raw)] & MASK) != 0;
}

pub fn configApply(raw_keys: []const u8, cfg: *const InputConfig, out: *backend.InputState) void {
    var bits: u8 = 0;
    out.quit = false;
    if (raw_keys.len >= 256) {
        if (keyDown(raw_keys, cfg.right.raw)) bits |= 0x01;
        if (keyDown(raw_keys, cfg.left.raw)) bits |= 0x02;
        if (keyDown(raw_keys, cfg.up.raw)) bits |= 0x04;
        if (keyDown(raw_keys, cfg.down.raw)) bits |= 0x08;
        if (keyDown(raw_keys, cfg.a.raw)) bits |= 0x10;
        if (keyDown(raw_keys, cfg.b.raw)) bits |= 0x20;
        if (keyDown(raw_keys, cfg.select.raw)) bits |= 0x40;
        if (keyDown(raw_keys, cfg.start.raw)) bits |= 0x80;
        if (keyDown(raw_keys, cfg.quit.raw)) out.quit = true;
    }
    out.buttons = bits;
}

// Legacy keyboard-only bits: exactly the DIK table std_dinput_pal.mapKeys has
// always used. This is L in the gamepad-preserving merge below.
fn legacyKeyBits(raw_keys: []const u8) u8 {
    var bits: u8 = 0;
    if (keyDown(raw_keys, 0xCD)) bits |= 0x01;
    if (keyDown(raw_keys, 0xCB)) bits |= 0x02;
    if (keyDown(raw_keys, 0xC8)) bits |= 0x04;
    if (keyDown(raw_keys, 0xD0)) bits |= 0x08;
    if (keyDown(raw_keys, 0x2C)) bits |= 0x10;
    if (keyDown(raw_keys, 0x2D)) bits |= 0x20;
    if (keyDown(raw_keys, 0x0E)) bits |= 0x40;
    if (keyDown(raw_keys, 0x1C)) bits |= 0x80;
    return bits;
}

// Active-config path. `legacy_bits` is M from dinputPoll (keyboard + gamepad
// merged); `raw_keys` is the same raw image used to derive L. Gamepad-only bits
// are M & ~L, then OR'd with the configured keyboard bits K. Quit follows the
// config's quit binding (window-close quit is applied by the caller).
pub fn configApplyWithGamepad(raw_keys: []const u8, legacy_bits: u8, cfg: *const InputConfig, out: *backend.InputState) void {
    var key = backend.InputState{ .buttons = 0, .quit = false };
    configApply(raw_keys, cfg, &key);
    const legacy_kb = legacyKeyBits(raw_keys);
    const gamepad = legacy_bits & ~legacy_kb;
    out.buttons = gamepad | key.buttons;
    out.quit = key.quit;
}

fn writeHexByte(v: u8) void {
    var buf: [2]u8 = undefined;
    buf[0] = hexChar(v >> 4);
    buf[1] = hexChar(v);
    std.io.write(buf[0..]);
}

pub fn configPrintTable(cfg: *const InputConfig) void {
    var i: u8 = 0;
    while (i < 9) : (i += 1) {
        const b = bindingAt(cfg, i);
        std.io.write(inputName(i));
        std.io.write(" raw=0x");
        writeHexByte(b.raw);
        std.io.write(" backend=");
        std.io.write(backendName(b.kind));
        std.io.write("\n");
    }
}

fn printChange(name: []const u8, raw: u8, down: bool) void {
    std.io.write("input ");
    std.io.write(name);
    std.io.write(" raw=0x");
    writeHexByte(raw);
    if (down) {
        std.io.write(" down\n");
    } else {
        std.io.write(" up\n");
    }
}

pub fn configPrintChanges(prev: *const backend.InputState, cur: *const backend.InputState, cfg: *const InputConfig) void {
    var i: u8 = 0;
    while (i < 9) : (i += 1) {
        if (stateChanged(prev, cur, i)) {
            printChange(inputName(i), bindingAt(cfg, i).raw, stateBit(cur, i));
        }
    }
}

// Debug helpers compare individual logical buttons, not the packed byte.
fn stateBit(st: *const backend.InputState, i: u8) bool {
    if (i == 8) return st.quit;
    return (st.buttons & (@as(u8, 1) << i)) != 0;
}

pub fn stateChanged(prev: *const backend.InputState, cur: *const backend.InputState, i: u8) bool {
    return stateBit(prev, i) != stateBit(cur, i);
}

pub fn captureBegin(c: *CaptureState, keys: []const u8) void {
    c.done = false;
    c.result = 0;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (i < keys.len and (keys[i] & MASK) != 0) {
            c.armed[i] = 0;
        } else {
            c.armed[i] = 1;
        }
    }
}

pub fn captureStep(c: *CaptureState, keys: []const u8) i32 {
    if (c.done) return -1;
    if (keys.len < 256) return -1;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (c.armed[i] == 0 and (keys[i] & MASK) == 0) c.armed[i] = 1;
    }
    i = 0;
    while (i < 256) : (i += 1) {
        if (c.armed[i] != 0 and (keys[i] & MASK) != 0) {
            c.done = true;
            c.result = @intCast(u8, i);
            return @intCast(i32, i);
        }
    }
    return -1;
}
