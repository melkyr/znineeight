/* zig_gfx_wndproc.c — std_gfx Win9x window-proc trampoline (P4-M1).
 *
 * Z98 cannot define a stdcall callback, so this small C shim owns the WndProc.
 * It records SENT WM_SIZE/WM_CLOSE messages (WM_SIZE never enters the
 * PeekMessage queue) for std_gfx_pal.zig's poll loop and forwards every message
 * to the default proc address the PAL installs at gfxOpen.
 *
 * This file is linked only for std_gfx GUI programs via cross_nocrt.sh's
 * EXTRA_CSRC hook, so other no-CRT programs keep their exact import/link set.
 * It deliberately does not reference DefWindowProcA directly: the PAL passes
 * the address, keeping this object import-free.
 */

#include <windows.h>

static void* z98_gfx_defproc = 0;
static volatile LONG z98_gfx_resize_pending = 0;
static volatile LONG z98_gfx_resize_w = 0;
static volatile LONG z98_gfx_resize_h = 0;
static volatile LONG z98_gfx_close_pending = 0;

static LRESULT CALLBACK z98_gfx_wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_SIZE) {
        z98_gfx_resize_w = (LONG)LOWORD(lp);
        z98_gfx_resize_h = (LONG)HIWORD(lp);
        z98_gfx_resize_pending = 1;
    } else if (msg == WM_CLOSE || msg == WM_DESTROY) {
        z98_gfx_close_pending = 1;
    }
    if (z98_gfx_defproc) {
        typedef LRESULT (CALLBACK *Z98GfxDefProc)(HWND, UINT, WPARAM, LPARAM);
        return ((Z98GfxDefProc)z98_gfx_defproc)(hwnd, msg, wp, lp);
    }
    return 0;
}

void z98_gfx_set_defproc(void* p) {
    z98_gfx_defproc = p;
}

void* z98_gfx_wndproc_addr(void) {
    return (void*)z98_gfx_wndproc;
}

void z98_gfx_reset(void) {
    z98_gfx_resize_pending = 0;
    z98_gfx_resize_w = 0;
    z98_gfx_resize_h = 0;
    z98_gfx_close_pending = 0;
}

int z98_gfx_resize_take(unsigned* w, unsigned* h) {
    if (!z98_gfx_resize_pending) return 0;
    z98_gfx_resize_pending = 0;
    if (w) *w = (unsigned)z98_gfx_resize_w;
    if (h) *h = (unsigned)z98_gfx_resize_h;
    return 1;
}

int z98_gfx_close_take(void) {
    if (!z98_gfx_close_pending) return 0;
    z98_gfx_close_pending = 0;
    return 1;
}
