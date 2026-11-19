// std_gfx_px_core.zig — Z98 pure pixel core for the UNDERSANDED M9 tier.
//
// No Windows headers, no gfx/pal imports, no heap, no file I/O: software
// clipping, 565 writes, indexed->LUT blits, the §27 bar math, the pitch-tight
// framebuffer dump, and the headless memory-target API. The Windows wrapper
// std_gfx_px.zig re-exports these symbols and adds the DirectDraw present path.
//
// Surface/Sprite/PxError are spec §23.1 verbatim. The memory canvas is one
// module-level fixed 640x480 565 buffer (614,400 bytes) in BSS; opening a
// memory Gfx points a plain Surface at it and never allocates.

pub const PxError = error{ OpenFailed, SurfaceFailed, LockFailed, OutOfMemory };

pub const Surface = struct {
    pixels: [*]u8,
    pitch: i32,
    w: u32,
    h: u32,
};

pub const Sprite = struct {
    w: u32,
    h: u32,
    idx: [*]const u8,
    lut: [*]const u16,
    key: u8,
};

pub const Bar = struct {
    fill: i32,
    red: i32,
};

pub const MAX_PX_W: u32 = 640;
pub const MAX_PX_H: u32 = 480;
pub const MAX_PX_BYTES: usize = 640 * 480 * 2;

// The Windows wrapper shares this state type. The COM/window handles are
// opaque `*void` here (and only here) so the pure core stays free of Windows
// headers and of std_gfx/std_gfx_pal imports.
pub const GfxState = struct {
    pixels: [*]u8,
    pitch: i32,
    w: u32,
    h: u32,
    mem_only: bool,
    opened: bool,
    win: *void,
    dd7: *void,
    primary: *void,
    px_surface: *void,
    pst: *void,
    locked: bool,
    owned: bool,
    fallback: bool,
    unlocked_logged: bool,
};

pub const Gfx = struct { opaque: *GfxState };

var g_canvas: [MAX_PX_BYTES]u8 = undefined;
var g_state: GfxState = undefined;
var g_gfx: Gfx = undefined;

pub fn pxCoreSurface(s: *GfxState) Surface {
    return Surface{
        .pixels = s.pixels,
        .pitch = s.pitch,
        .w = s.w,
        .h = s.h,
    };
}

fn nullPtr() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn storePixel(row: [*]u8, x: i32, px: u16) void {
    const off = @intCast(usize, x * 2);
    row[off] = @intCast(u8, px & 0xFF);
    row[off + 1] = @intCast(u8, (px >> 8) & 0xFF);
}

pub fn pxCoreFill(sf: *Surface, x: i32, y: i32, w: i32, h: i32, px: u16) void {
    if (w <= 0 or h <= 0) return;
    var x0 = x;
    var y0 = y;
    var x1 = x + w;
    var y1 = y + h;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    const sw = @intCast(i32, sf.w);
    const sh = @intCast(i32, sf.h);
    if (x1 > sw) x1 = sw;
    if (y1 > sh) y1 = sh;
    if (x0 >= x1 or y0 >= y1) return;
    var yy = y0;
    while (yy < y1) : (yy += 1) {
        const row = sf.pixels + @intCast(usize, yy) * @intCast(usize, sf.pitch);
        var xx = x0;
        while (xx < x1) : (xx += 1) {
            storePixel(row, xx, px);
        }
    }
}

pub fn pxCoreBlitPart(sf: *Surface, dx: i32, dy: i32, s: *const Sprite,
    sx: i32, sy: i32, sw: i32, sh: i32) void {
    if (sw <= 0 or sh <= 0) return;
    var sx0 = sx;
    var sy0 = sy;
    var dx0 = dx;
    var dy0 = dy;
    var w0 = sw;
    var h0 = sh;
    const sprite_w = @intCast(i32, s.w);
    const sprite_h = @intCast(i32, s.h);

    if (sx0 < 0) {
        const cut = 0 - sx0;
        sx0 = 0;
        dx0 += cut;
        w0 -= cut;
    }
    if (sy0 < 0) {
        const cut = 0 - sy0;
        sy0 = 0;
        dy0 += cut;
        h0 -= cut;
    }
    if (w0 <= 0 or h0 <= 0) return;
    if (sx0 + w0 > sprite_w) w0 = sprite_w - sx0;
    if (sy0 + h0 > sprite_h) h0 = sprite_h - sy0;
    if (w0 <= 0 or h0 <= 0) return;

    if (dx0 < 0) {
        const cut = 0 - dx0;
        dx0 = 0;
        sx0 += cut;
        w0 -= cut;
    }
    if (dy0 < 0) {
        const cut = 0 - dy0;
        dy0 = 0;
        sy0 += cut;
        h0 -= cut;
    }
    if (w0 <= 0 or h0 <= 0) return;

    const dest_w = @intCast(i32, sf.w);
    const dest_h = @intCast(i32, sf.h);
    if (dx0 + w0 > dest_w) w0 = dest_w - dx0;
    if (dy0 + h0 > dest_h) h0 = dest_h - dy0;
    if (w0 <= 0 or h0 <= 0) return;

    var y: i32 = 0;
    while (y < h0) : (y += 1) {
        const srow = @intCast(usize, sy0 + y) * @intCast(usize, s.w);
        const drow = sf.pixels + @intCast(usize, dy0 + y) * @intCast(usize, sf.pitch);
        var x: i32 = 0;
        while (x < w0) : (x += 1) {
            const k = s.idx[srow + @intCast(usize, sx0 + x)];
            if (k != s.key) {
                const px = s.lut[@intCast(usize, k)];
                storePixel(drow, dx0 + x, px);
            }
        }
    }
}

pub fn pxCoreBlit(sf: *Surface, dx: i32, dy: i32, s: *const Sprite) void {
    pxCoreBlitPart(sf, dx, dy, s, 0, 0,
        @intCast(i32, s.w), @intCast(i32, s.h));
}

pub fn pxCoreDump(sf: *const Surface, out: []u8) void {
    const w: usize = @intCast(usize, sf.w);
    const h: usize = @intCast(usize, sf.h);
    const row_bytes = w * 2;
    if (out.len < row_bytes * h) return;
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const src = sf.pixels + y * @intCast(usize, sf.pitch);
        const dst = y * row_bytes;
        var i: usize = 0;
        while (i < row_bytes) : (i += 1) {
            out[dst + i] = src[i];
        }
    }
}

// Spec §27 literally: fill = value*width/max; red =
// clamp((25 - margin)*width/max, 0, width). max<=0 is the zero guard and the
// value is clamped to 0..max before the division. Do not "fix" the formula.
pub fn pxCoreBar(width: i32, value: i32, max: i32, margin: i32) Bar {
    if (max <= 0) return Bar{ .fill = 0, .red = 0 };
    var v = value;
    if (v < 0) v = 0;
    if (v > max) v = max;
    const fill = v * width / max;
    var red = (25 - margin) * width / max;
    if (red < 0) red = 0;
    if (red > width) red = width;
    return Bar{ .fill = fill, .red = red };
}

pub fn gfxPxOpenMemory(w: u32, h: u32) PxError!*Gfx {
    if (w == 0 or h == 0 or w > MAX_PX_W or h > MAX_PX_H) {
        return error.OpenFailed;
    }
    const s = &g_state;
    s.pixels = @ptrCast([*]u8, &g_canvas[0]);
    s.pitch = @intCast(i32, w * 2);
    s.w = w;
    s.h = h;
    s.mem_only = true;
    s.opened = true;
    s.win = nullPtr();
    s.dd7 = nullPtr();
    s.primary = nullPtr();
    s.px_surface = nullPtr();
    s.pst = nullPtr();
    s.locked = false;
    s.owned = false;
    s.fallback = false;
    s.unlocked_logged = false;
    g_gfx.opaque = s;
    return &g_gfx;
}

pub fn gfxPxDump(g: *Gfx) []const u8 {
    const s = g.opaque;
    if (!s.opened) return g_canvas[0..0];
    const n: usize = @intCast(usize, s.w) * @intCast(usize, s.h) * 2;
    return g_canvas[0..n];
}

pub fn gfxPxFill(g: *Gfx, x: i32, y: i32, w: i32, h: i32, rgb565: u16) void {
    if (!g.opaque.opened) return;
    var sf = pxCoreSurface(g.opaque);
    pxCoreFill(&sf, x, y, w, h, rgb565);
}

pub fn gfxPxBlit(g: *Gfx, dx: i32, dy: i32, s: *const Sprite) void {
    if (!g.opaque.opened) return;
    var sf = pxCoreSurface(g.opaque);
    pxCoreBlit(&sf, dx, dy, s);
}

pub fn gfxPxBlitPart(g: *Gfx, dx: i32, dy: i32, s: *const Sprite,
    sx: i32, sy: i32, sw: i32, sh: i32) void {
    if (!g.opaque.opened) return;
    var sf = pxCoreSurface(g.opaque);
    pxCoreBlitPart(&sf, dx, dy, s, sx, sy, sw, sh);
}
