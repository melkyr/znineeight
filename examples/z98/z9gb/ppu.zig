// ppu.zig — z9gb DMG scanline PPU.
//
// The PPU advances in 456-dot scanlines (154 lines per frame). Mode 2 is 80
// dots, mode 3 uses the documented penalty model, and mode 0 is the remainder.
// A line is rendered once, in 8-pixel tile-row batches, into a [160]u8 shade
// buffer; sprites are mixed afterwards with per-pixel BG/OBJ priority. No heap
// or per-pixel helper calls are used.

const mmumod = @import("mmu.zig");

pub const SCREEN_W: usize = 160;
pub const SCREEN_H: usize = 144;
pub const FRAME_PIXELS: usize = SCREEN_W * SCREEN_H;

const LINE_DOTS: u32 = 456;
const MODE2_DOTS: u32 = 80;
const TOTAL_LINES: u8 = 154;
const VISIBLE_LINES: u8 = 144;
const MAX_SPRITES: usize = 10;

const DMG_COLORS: [4]u32 = [4]u32{
    0x009BBC0F,
    0x008BAC0F,
    0x00306230,
    0x000F380F,
};

pub const Ppu = struct {
    lcdc: u8,
    stat: u8,
    scy: u8,
    scx: u8,
    ly: u8,
    lyc: u8,
    dma: u8,
    bgp: u8,
    obp0: u8,
    obp1: u8,
    wy: u8,
    wx: u8,
    coincidence: bool,
    mode: u8,
    dot: u32,
    line: u8,
    window_line: u8,
    mode3_len: u32,
    bg_lut: [4]u32,
    obj0_lut: [4]u32,
    obj1_lut: [4]u32,
    fb: [FRAME_PIXELS]u32,
    shades: [SCREEN_W]u8,
    obj_drawn: [SCREEN_W]u8,
    sprite_count: u8,
    sprite_x: [MAX_SPRITES]u8,
    sprite_y: [MAX_SPRITES]u8,
    sprite_tile: [MAX_SPRITES]u8,
    sprite_attr: [MAX_SPRITES]u8,
    sprite_index: [MAX_SPRITES]u8,
};

fn updatePalette(out: *[4]u32, reg: u8) void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const shift: u8 = @intCast(u8, i * 2);
        const shade: u8 = (reg >> shift) & 0x03;
        out[i] = DMG_COLORS[@intCast(usize, shade)];
    }
}

pub fn ppuReset(p: *Ppu) void {
    p.lcdc = 0x91;
    p.stat = 0;
    p.scy = 0;
    p.scx = 0;
    p.ly = 0;
    p.lyc = 0;
    p.dma = 0;
    p.bgp = 0xFC;
    p.obp0 = 0xFF;
    p.obp1 = 0xFF;
    p.wy = 0;
    p.wx = 0;
    p.coincidence = true;
    p.mode = 2;
    p.dot = 0;
    p.line = 0;
    p.window_line = 0;
    p.mode3_len = 0;
    p.sprite_count = 0;
    updatePalette(&p.bg_lut, p.bgp);
    updatePalette(&p.obj0_lut, p.obp0);
    updatePalette(&p.obj1_lut, p.obp1);
    var i: usize = 0;
    while (i < FRAME_PIXELS) : (i += 1) {
        p.fb[i] = 0;
    }
    i = 0;
    while (i < SCREEN_W) : (i += 1) {
        p.shades[i] = 0;
        p.obj_drawn[i] = 0;
    }
}

pub fn ppuRead(p: *Ppu, addr: u16) u8 {
    switch (addr) {
        0xFF40 => return p.lcdc,
        0xFF41 => {
            var v: u8 = 0x80 | (p.stat & 0x78) | p.mode;
            if (p.coincidence) v |= 0x04;
            return v;
        },
        0xFF42 => return p.scy,
        0xFF43 => return p.scx,
        0xFF44 => return p.ly,
        0xFF45 => return p.lyc,
        0xFF46 => return p.dma,
        0xFF47 => return p.bgp,
        0xFF48 => return p.obp0,
        0xFF49 => return p.obp1,
        0xFF4A => return p.wy,
        0xFF4B => return p.wx,
        else => return 0xFF,
    }
}

pub fn ppuWrite(p: *Ppu, addr: u16, value: u8) void {
    switch (addr) {
        0xFF40 => {
            p.lcdc = value;
            if ((value & 0x80) == 0) {
                p.mode = 0;
                p.dot = 0;
                p.line = 0;
                p.ly = 0;
                p.window_line = 0;
                p.coincidence = (p.ly == p.lyc);
            }
        },
        0xFF41 => p.stat = value & 0x78,
        0xFF42 => p.scy = value,
        0xFF43 => p.scx = value,
        0xFF44 => {},
        0xFF45 => {
            p.lyc = value;
            p.coincidence = (p.ly == p.lyc);
        },
        0xFF46 => p.dma = value,
        0xFF47 => {
            p.bgp = value;
            updatePalette(&p.bg_lut, value);
        },
        0xFF48 => {
            p.obp0 = value;
            updatePalette(&p.obj0_lut, value);
        },
        0xFF49 => {
            p.obp1 = value;
            updatePalette(&p.obj1_lut, value);
        },
        0xFF4A => p.wy = value,
        0xFF4B => p.wx = value,
        else => {},
    }
}

pub fn ppuFramebuffer(p: *const Ppu) []const u32 {
    return p.fb[0..];
}

fn windowStart(p: *const Ppu) u32 {
    if (p.wx >= 7) return @intCast(u32, p.wx - 7);
    return 0;
}

fn windowActive(p: *const Ppu) bool {
    if ((p.lcdc & 0x20) == 0) return false;
    if ((p.lcdc & 0x01) == 0) return false;
    if (p.wy > 143) return false;
    if (p.wx > 166) return false;
    if (p.line < p.wy) return false;
    return windowStart(p) < SCREEN_W;
}

fn tileDataAddr(tile_id: u8, lcdc: u8) usize {
    if ((lcdc & 0x10) != 0) {
        return @intCast(usize, tile_id) * 16;
    }
    if (tile_id < 128) {
        return 0x1000 + @intCast(usize, tile_id) * 16;
    }
    return 0x0800 + @intCast(usize, tile_id - 128) * 16;
}

fn scanOam(p: *Ppu, bus: *mmumod.Bus) void {
    p.sprite_count = 0;
    const height: u8 = if ((p.lcdc & 0x04) != 0) 16 else 8;
    const line_i: i32 = @intCast(i32, p.line);
    var i: usize = 0;
    while (i < 160 and p.sprite_count < MAX_SPRITES) : (i += 4) {
        const oy: u8 = bus.oam[i];
        const top: i32 = @as(i32, @intCast(i32, oy)) - 16;
        const bottom: i32 = top + @intCast(i32, height);
        if (line_i >= top and line_i < bottom) {
            const s: usize = @intCast(usize, p.sprite_count);
            p.sprite_x[s] = bus.oam[i + 1];
            p.sprite_y[s] = bus.oam[i];
            p.sprite_tile[s] = bus.oam[i + 2];
            p.sprite_attr[s] = bus.oam[i + 3];
            p.sprite_index[s] = @intCast(u8, i / 4);
            p.sprite_count += 1;
        }
    }
}

fn objWait(p: *const Ppu, ox: u8) u32 {
    const left: u32 = if (ox >= 8) @intCast(u32, ox - 8) else 0;
    var off: u32 = 0;
    if (windowActive(p) and left >= windowStart(p)) {
        const wx: u32 = left - windowStart(p);
        off = wx & 7;
    } else {
        const sx: u32 = @intCast(u32, p.scx) + left;
        off = sx & 7;
    }
    const pixels_right: u32 = 8 - off;
    if (pixels_right > 2) return pixels_right - 2;
    return 0;
}

fn computeMode3(p: *const Ppu) u32 {
    var len: u32 = 172 + @intCast(u32, p.scx & 0x07);
    if (windowActive(p)) len += 6;
    var i: usize = 0;
    while (i < @intCast(usize, p.sprite_count)) : (i += 1) {
        const ox: u8 = p.sprite_x[i];
        if (ox == 0) {
            len += 11;
        } else {
            len += 6 + objWait(p, ox);
        }
    }
    return len;
}

fn fetchTileRow(bus: *mmumod.Bus, tile_id: u8, row: usize, lcdc: u8, lo: *u8, hi: *u8) void {
    const addr: usize = tileDataAddr(tile_id, lcdc) + row * 2;
    lo.* = bus.vram[addr];
    hi.* = bus.vram[addr + 1];
}

fn renderBackground(p: *Ppu, bus: *mmumod.Bus) void {
    var x: usize = 0;
    if ((p.lcdc & 0x01) == 0) {
        while (x < SCREEN_W) : (x += 1) p.shades[x] = 0;
        return;
    }
    const row: u8 = @intCast(u8, (@as(u16, p.line) + @as(u16, p.scy)) & 0xFF);
    const tile_row: usize = @intCast(usize, row >> 3);
    const row_in_tile: usize = @intCast(usize, row & 7);
    const map_base: usize = if ((p.lcdc & 0x08) != 0) 0x1C00 else 0x1800;
    var cached_tile: u32 = 0xFFFFFFFF;
    var lo: u8 = 0;
    var hi: u8 = 0;
    while (x < SCREEN_W) : (x += 1) {
        const sx: u32 = @intCast(u32, p.scx) + @intCast(u32, x);
        const tx: u32 = (sx >> 3) & 31;
        if (tx != cached_tile) {
            const map_addr: usize = map_base + tile_row * 32 + @intCast(usize, tx);
            fetchTileRow(bus, bus.vram[map_addr], row_in_tile, p.lcdc, &lo, &hi);
            cached_tile = tx;
        }
        const bit: u8 = @intCast(u8, 7 - (sx & 7));
        const low: u8 = (lo >> bit) & 0x01;
        const high: u8 = (hi >> bit) & 0x01;
        p.shades[x] = low | (high << 1);
    }
}

fn renderWindow(p: *Ppu, bus: *mmumod.Bus) void {
    if (!windowActive(p)) return;
    const start: usize = @intCast(usize, windowStart(p));
    const row: u8 = p.window_line;
    const tile_row: usize = @intCast(usize, row >> 3);
    const row_in_tile: usize = @intCast(usize, row & 7);
    const map_base: usize = if ((p.lcdc & 0x40) != 0) 0x1C00 else 0x1800;
    var cached_tile: u32 = 0xFFFFFFFF;
    var lo: u8 = 0;
    var hi: u8 = 0;
    var x: usize = start;
    while (x < SCREEN_W) : (x += 1) {
        const wx: u32 = @intCast(u32, x) - @intCast(u32, start);
        const tx: u32 = (wx >> 3) & 31;
        if (tx != cached_tile) {
            const map_addr: usize = map_base + tile_row * 32 + @intCast(usize, tx);
            fetchTileRow(bus, bus.vram[map_addr], row_in_tile, p.lcdc, &lo, &hi);
            cached_tile = tx;
        }
        const bit: u8 = @intCast(u8, 7 - (wx & 7));
        const low: u8 = (lo >> bit) & 0x01;
        const high: u8 = (hi >> bit) & 0x01;
        p.shades[x] = low | (high << 1);
    }
    p.window_line +%= 1;
}

fn spriteBefore(p: *const Ppu, a: usize, b: usize) bool {
    if (p.sprite_x[a] != p.sprite_x[b]) return p.sprite_x[a] < p.sprite_x[b];
    return p.sprite_index[a] < p.sprite_index[b];
}

fn renderSprites(p: *Ppu, bus: *mmumod.Bus) void {
    if ((p.lcdc & 0x02) == 0) return;
    var i: usize = 0;
    while (i < SCREEN_W) : (i += 1) p.obj_drawn[i] = 0;

    var order: [MAX_SPRITES]u8 = undefined;
    const count: usize = @intCast(usize, p.sprite_count);
    i = 0;
    while (i < count) : (i += 1) order[i] = @intCast(u8, i);
    i = 1;
    while (i < count) : (i += 1) {
        var j: usize = i;
        while (j > 0) {
            const cur: usize = @intCast(usize, order[j]);
            const prev: usize = @intCast(usize, order[j - 1]);
            if (!spriteBefore(p, cur, prev)) break;
            order[j] = order[j - 1];
            order[j - 1] = @intCast(u8, cur);
            j -= 1;
        }
    }

    const height: usize = if ((p.lcdc & 0x04) != 0) 16 else 8;
    const line_i: i32 = @intCast(i32, p.line);
    var k: usize = 0;
    while (k < count) : (k += 1) {
        const s: usize = @intCast(usize, order[k]);
        const oy: u8 = p.sprite_y[s];
        const ox: u8 = p.sprite_x[s];
        const attr: u8 = p.sprite_attr[s];
        var row_i: i32 = line_i + 16 - @as(i32, @intCast(i32, oy));
        if (row_i < 0 or row_i >= @intCast(i32, height)) continue;
        var row: usize = @intCast(usize, row_i);
        if ((attr & 0x40) != 0) row = height - 1 - row;

        var tile_id: u8 = p.sprite_tile[s];
        if (height == 16) {
            const base: u8 = tile_id & 0xFE;
            if (row >= 8) {
                tile_id = base + 1;
                row -= 8;
            } else {
                tile_id = base;
            }
        }
        const addr: usize = @intCast(usize, tile_id) * 16 + row * 2;
        const lo: u8 = bus.vram[addr];
        const hi: u8 = bus.vram[addr + 1];
        const lut: *const [4]u32 = if ((attr & 0x10) != 0) &p.obj1_lut else &p.obj0_lut;

        var off: usize = 0;
        while (off < 8) : (off += 1) {
            const fx: i32 = @as(i32, @intCast(i32, ox)) - 8 + @intCast(i32, off);
            if (fx < 0 or fx >= @intCast(i32, SCREEN_W)) continue;
            const px: usize = @intCast(usize, fx);
            if (p.obj_drawn[px] != 0) continue;
            const bit: u8 = if ((attr & 0x20) != 0) @intCast(u8, off) else @intCast(u8, 7 - off);
            const low: u8 = (lo >> bit) & 0x01;
            const high: u8 = (hi >> bit) & 0x01;
            const idx: u8 = low | (high << 1);
            if (idx == 0) continue;
            p.obj_drawn[px] = 1;
            if ((p.lcdc & 0x01) != 0 and (attr & 0x80) != 0 and p.shades[px] != 0) continue;
            p.fb[@intCast(usize, p.line) * SCREEN_W + px] = lut[@intCast(usize, idx)];
        }
    }
}

fn renderLine(p: *Ppu, bus: *mmumod.Bus) void {
    renderBackground(p, bus);
    renderWindow(p, bus);
    var x: usize = 0;
    const base: usize = @intCast(usize, p.line) * SCREEN_W;
    while (x < SCREEN_W) : (x += 1) {
        p.fb[base + x] = p.bg_lut[@intCast(usize, p.shades[x])];
    }
    renderSprites(p, bus);
}

fn startMode3(p: *Ppu, bus: *mmumod.Bus) void {
    scanOam(p, bus);
    p.mode3_len = computeMode3(p);
    p.mode = 3;
    renderLine(p, bus);
}

fn enterMode0(p: *Ppu, bus: *mmumod.Bus) void {
    p.mode = 0;
    if ((p.stat & 0x08) != 0) bus.io[0x0F] |= 0x02;
}

fn enterLine(p: *Ppu, bus: *mmumod.Bus, line: u8) void {
    p.line = line;
    p.ly = line;
    p.dot = 0;
    p.coincidence = (p.ly == p.lyc);
    if (p.coincidence and (p.stat & 0x40) != 0) bus.io[0x0F] |= 0x02;
    if (line < VISIBLE_LINES) {
        p.mode = 2;
        if ((p.stat & 0x20) != 0) bus.io[0x0F] |= 0x02;
    } else {
        p.mode = 1;
        if (line == VISIBLE_LINES and (p.stat & 0x10) != 0) bus.io[0x0F] |= 0x02;
    }
}

fn nextLine(p: *Ppu, bus: *mmumod.Bus) void {
    var line: u16 = @intCast(u16, p.line) + 1;
    if (line >= TOTAL_LINES) {
        line = 0;
        p.window_line = 0;
    }
    enterLine(p, bus, @intCast(u8, line));
}

pub fn ppuTick(p: *Ppu, cycles: u32, bus: *mmumod.Bus) void {
    if ((p.lcdc & 0x80) == 0) {
        p.mode = 0;
        p.dot = 0;
        p.line = 0;
        p.ly = 0;
        p.window_line = 0;
        p.coincidence = (p.ly == p.lyc);
        return;
    }

    var left: u32 = cycles;
    while (left > 0) {
        if (p.line >= VISIBLE_LINES) {
            const remain: u32 = LINE_DOTS - p.dot;
            const step: u32 = if (left < remain) left else remain;
            p.dot += step;
            left -= step;
            if (p.dot >= LINE_DOTS) {
                p.dot = 0;
                nextLine(p, bus);
            }
            continue;
        }

        if (p.dot < MODE2_DOTS) {
            const remain: u32 = MODE2_DOTS - p.dot;
            const step: u32 = if (left < remain) left else remain;
            p.dot += step;
            left -= step;
            if (p.dot >= MODE2_DOTS) startMode3(p, bus);
            continue;
        }

        if (p.dot < MODE2_DOTS + p.mode3_len) {
            const remain: u32 = MODE2_DOTS + p.mode3_len - p.dot;
            const step: u32 = if (left < remain) left else remain;
            p.dot += step;
            left -= step;
            if (p.dot >= MODE2_DOTS + p.mode3_len) enterMode0(p, bus);
            continue;
        }

        const remain: u32 = LINE_DOTS - p.dot;
        const step: u32 = if (left < remain) left else remain;
        p.dot += step;
        left -= step;
        if (p.dot >= LINE_DOTS) {
            p.dot = 0;
            nextLine(p, bus);
        }
    }
}
