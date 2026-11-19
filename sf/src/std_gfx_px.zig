// std_gfx_px.zig — Z98 Windows binding for the UNDERSANDED M9 pixel tier.
//
// This is the thin wrapper over the shared std_gfx_pal window/pump. The pure
// pixel core (std_gfx_px_core.zig) owns Surface/Sprite/PxError/Bar and every
// locked-pixel operation; this module owns the 16bpp 565 system-memory
// offscreen, the lock state, the 1:1 Blt present, the px-only GDI fallback,
// and the event delegation to std_gfx_pal. It creates no second window when
// attached to an open std_gfx cell window.

const core = @import("std_gfx_px_core.zig");
const pal = @import("std_gfx_pal.zig");
const gfx = @import("std_gfx.zig");
const io = @import("std_io.zig");

pub const PxError = core.PxError;
pub const Surface = core.Surface;
pub const Sprite = core.Sprite;
pub const Bar = core.Bar;
pub const Gfx = core.Gfx;
pub const MAX_PX_W = core.MAX_PX_W;
pub const MAX_PX_H = core.MAX_PX_H;

var g_px_state: core.GfxState = undefined;
var g_px_gfx: Gfx = undefined;
var g_px_win_state: pal.State = undefined;

// Memory target: the core owns the fixed canvas and its one Gfx handle.
pub fn gfxPxOpenMemory(w: u32, h: u32) PxError!*Gfx {
    return core.gfxPxOpenMemory(w, h);
}

pub fn gfxPxDump(g: *Gfx) []const u8 {
    return core.gfxPxDump(g);
}

fn warnUnlocked(s: *core.GfxState) void {
    if (s.unlocked_logged) return;
    s.unlocked_logged = true;
    io.write("gfxPx: fill/blit while unlocked ignored\n");
}

fn warnPresent(s: *core.GfxState, what: []const u8) void {
    if (s.present_failed_logged) return;
    s.present_failed_logged = true;
    io.write("gfxPx: present failed");
    if (what.len != 0) {
        io.write(" (");
        io.write(what);
        io.write(")");
    }
    io.write("\n");
}

fn bind(s: *core.GfxState, pst: *pal.State, surface: *void, owned: bool, w: u32, h: u32) void {
    s.pixels = @ptrCast([*]u8, pal.nullHandle());
    s.pitch = 0;
    s.w = w;
    s.h = h;
    s.mem_only = false;
    s.opened = true;
    s.win = pst.hwnd;
    s.dd7 = pst.dd7;
    s.primary = pst.primary;
    s.px_surface = surface;
    s.pst = @ptrCast(*void, pst);
    s.locked = false;
    s.owned = owned;
    s.fallback = !pal.pxPrimaryIs565(pst.primary);
    s.surface_lost = false;
    s.needs_full_repaint = false;
    s.unlocked_logged = false;
    s.present_failed_logged = false;
}

// Standalone fixed 640x480 px window. pal.open creates the window + DD7 +
// primary clipper; pxFixClient makes the client exactly w x h and removes the
// resizable frame. The cell/back/atlas resources in pal.State are released by
// gfxPxClose because this px Gfx owns the window.
pub fn gfxPxOpen(title: []const u8, w: u32, h: u32) PxError!*Gfx {
    if (w != MAX_PX_W or h != MAX_PX_H) return error.OpenFailed;
    if (!pal.pxDepthOk()) return error.OpenFailed;
    if (!pal.open(title, 80, 30, &g_px_win_state)) return error.OpenFailed;
    if (!pal.pxFixClient(&g_px_win_state, w, h)) {
        pal.close(&g_px_win_state);
        return error.OpenFailed;
    }
    if (@ptrToInt(g_px_win_state.dd7) == 0 or @ptrToInt(g_px_win_state.primary) == 0) {
        pal.close(&g_px_win_state);
        return error.OpenFailed;
    }
    const surface = pal.pxCreate565(g_px_win_state.dd7, w, h);
    if (@ptrToInt(surface) == 0) {
        pal.close(&g_px_win_state);
        return error.OpenFailed;
    }
    bind(&g_px_state, &g_px_win_state, surface, true, w, h);
    g_px_gfx.opaque = &g_px_state;
    return &g_px_gfx;
}

// Borrow the already-open cell window/pump. The cell window is never closed
// here; gfxPxClose releases only the px surface for an attached Gfx.
pub fn gfxPxAttach(cell: *gfx.Gfx) ?*Gfx {
    if (!pal.pxDepthOk()) return null;
    const pst = gfx.gfxNativeState(cell);
    if (!pal.isWindowOpen(pst)) return null;
    if (@ptrToInt(pst.dd7) == 0 or @ptrToInt(pst.primary) == 0) return null;
    const surface = pal.pxCreate565(pst.dd7, MAX_PX_W, MAX_PX_H);
    if (@ptrToInt(surface) == 0) return null;
    bind(&g_px_state, pst, surface, false, MAX_PX_W, MAX_PX_H);
    g_px_gfx.opaque = &g_px_state;
    return &g_px_gfx;
}

pub fn gfxPxLock(g: *Gfx) PxError!Surface {
    const s = g.opaque;
    if (!s.opened) return error.OpenFailed;
    if (s.locked) return core.pxCoreSurface(s);
    if (s.mem_only) {
        s.locked = true;
        return core.pxCoreSurface(s);
    }
    if (core.pxCoreSurfaceLost(s)) {
        if (!gfxPxRestore(g)) return error.LockFailed;
    }
    var pixels: *void = pal.nullHandle();
    var pitch: i32 = 0;
    if (!pal.pxLock(s.px_surface, &pixels, &pitch)) {
        if (!pal.pxIsLost(s.px_surface)) return error.LockFailed;
        core.pxCoreMarkSurfaceLost(s);
        if (!gfxPxRestore(g)) return error.LockFailed;
        if (!pal.pxLock(s.px_surface, &pixels, &pitch)) return error.LockFailed;
    }
    s.pixels = @ptrCast([*]u8, pixels);
    s.pitch = pitch;
    s.locked = true;
    return core.pxCoreSurface(s);
}

pub fn gfxPxUnlock(g: *Gfx) void {
    const s = g.opaque;
    if (!s.opened or !s.locked) return;
    if (!s.mem_only) {
        if (!pal.pxUnlock(s.px_surface)) return;
    }
    s.locked = false;
}

pub fn gfxPxFill(g: *Gfx, x: i32, y: i32, w: i32, h: i32, rgb565: u16) void {
    const s = g.opaque;
    if (!s.opened) return;
    if (s.mem_only) {
        core.gfxPxFill(g, x, y, w, h, rgb565);
        return;
    }
    if (!s.locked) {
        warnUnlocked(s);
        return;
    }
    var sf = core.pxCoreSurface(s);
    core.pxCoreFill(&sf, x, y, w, h, rgb565);
}

pub fn gfxPxBlit(g: *Gfx, dx: i32, dy: i32, sprite: *const Sprite) void {
    const s = g.opaque;
    if (!s.opened) return;
    if (s.mem_only) {
        core.gfxPxBlit(g, dx, dy, sprite);
        return;
    }
    if (!s.locked) {
        warnUnlocked(s);
        return;
    }
    var sf = core.pxCoreSurface(s);
    core.pxCoreBlit(&sf, dx, dy, sprite);
}

pub fn gfxPxBlitPart(g: *Gfx, dx: i32, dy: i32, sprite: *const Sprite,
    sx: i32, sy: i32, sw: i32, sh: i32) void {
    const s = g.opaque;
    if (!s.opened) return;
    if (s.mem_only) {
        core.gfxPxBlitPart(g, dx, dy, sprite, sx, sy, sw, sh);
        return;
    }
    if (!s.locked) {
        warnUnlocked(s);
        return;
    }
    var sf = core.pxCoreSurface(s);
    core.pxCoreBlitPart(&sf, dx, dy, sprite, sx, sy, sw, sh);
}

// Present requires an unlocked surface. DD path = one 1:1 Blt with the primary
// clipper; any failure at >=16bpp switches to the px-only GDI fallback.
pub fn gfxPxPresent(g: *Gfx, x: i32, y: i32, w: i32, h: i32) void {
    const s = g.opaque;
    if (!s.opened or s.mem_only) return;
    if (s.locked) {
        warnPresent(s, "locked");
        return;
    }
    if (core.pxCoreSurfaceLost(s)) {
        if (!gfxPxRestore(g)) {
            warnPresent(s, "restore");
            return;
        }
    }
    if (s.fallback) {
        if (!pal.pxGdiPresent565(s.win, s.px_surface, x, y, w, h)) {
            warnPresent(s, "gdi");
        }
        return;
    }
    var hr = pal.pxPresentRect(s.primary, s.win, s.px_surface, x, y, w, h);
    if (hr == pal.DDERR_SURFACELOST) {
        core.pxCoreMarkSurfaceLost(s);
        if (!gfxPxRestore(g)) {
            warnPresent(s, "restore");
            return;
        }
        hr = pal.pxPresentRect(s.primary, s.win, s.px_surface, x, y, w, h);
    }
    if (hr == 0) return;
    s.fallback = true;
    if (!pal.pxGdiPresent565(s.win, s.px_surface, x, y, w, h)) {
        warnPresent(s, "dd+gdi");
    }
}

// Restore a lost px/primary pair once, re-creating the offscreen if the driver
// rejects Restore. Success clears the lost flag and arms a full repaint; the
// caller re-locks through gfxPxLock for the next frame.
pub fn gfxPxRestore(g: *Gfx) bool {
    const s = g.opaque;
    if (!s.opened) return false;
    if (s.mem_only) return true;
    if (!core.pxCoreSurfaceLost(s) and !pal.pxIsLost(s.px_surface) and
        !pal.pxIsLost(s.primary)) {
        return true;
    }
    core.pxCoreMarkSurfaceLost(s);
    if (s.locked) {
        if (!pal.pxUnlock(s.px_surface)) return false;
        s.locked = false;
    }
    if (!pal.pxRestore(s.px_surface)) {
        pal.pxRelease(s.px_surface);
        s.px_surface = pal.nullHandle();
        const recreated = pal.pxCreate565(s.dd7, s.w, s.h);
        if (@ptrToInt(recreated) == 0) return false;
        s.px_surface = recreated;
    }
    if (!pal.pxRestore(s.primary)) return false;
    s.fallback = !pal.pxPrimaryIs565(s.primary);
    core.pxCoreMarkRestored(s);
    return true;
}

pub fn gfxPxNeedsFullRepaint(g: *Gfx) bool {
    return core.pxCoreNeedsFullRepaint(g.opaque);
}

pub fn gfxPxClearFullRepaint(g: *Gfx) void {
    core.pxCoreClearFullRepaint(g.opaque);
}

// Test seam: mark the live px surface lost without a driver event so the tier
// and probe can drive restore -> re-lock -> full-repaint deterministically.
pub fn gfxPxTestRestore(g: *Gfx) bool {
    const s = g.opaque;
    if (!s.opened or s.mem_only) return false;
    core.pxCoreMarkSurfaceLost(s);
    return true;
}

pub fn gfxPxClose(g: *Gfx) void {
    const s = g.opaque;
    if (!s.opened) return;
    if (!s.mem_only) {
        if (s.locked) {
            _ = pal.pxUnlock(s.px_surface);
            s.locked = false;
        }
        pal.pxRelease(s.px_surface);
        s.px_surface = pal.nullHandle();
        if (s.owned) pal.close(&g_px_win_state);
    }
    s.opened = false;
    s.mem_only = true;
    s.pixels = @ptrCast([*]u8, pal.nullHandle());
    s.pitch = 0;
    s.win = pal.nullHandle();
    s.dd7 = pal.nullHandle();
    s.primary = pal.nullHandle();
    s.pst = pal.nullHandle();
    s.surface_lost = false;
    s.needs_full_repaint = false;
}

pub fn gfxPxPollEvent(g: *Gfx, ev: *gfx.Event) bool {
    const s = g.opaque;
    if (!s.opened or s.mem_only) return false;
    if (@ptrToInt(s.pst) == 0) return false;
    const pst: *pal.State = @ptrCast(*pal.State, s.pst);
    var raw: pal.RawEvent = undefined;
    if (!pal.pollEvent(pst, &raw)) return false;
    ev.* = gfx.gfxEventFromRaw(raw);
    return true;
}

pub fn gfxPxWaitEvent(g: *Gfx, timeout_ms: u32) bool {
    const s = g.opaque;
    if (!s.opened or s.mem_only) return false;
    if (@ptrToInt(s.pst) == 0) return false;
    const pst: *pal.State = @ptrCast(*pal.State, s.pst);
    var raw: pal.RawEvent = undefined;
    if (!pal.waitEvent(pst, timeout_ms, &raw)) return false;
    const ev = gfx.gfxEventFromRaw(raw);
    _ = ev;
    return true;
}
