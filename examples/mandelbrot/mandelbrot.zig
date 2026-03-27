const Width: usize = 80;
const Height: usize = 24;
const MaxIter: u8 = 100;

extern fn __bootstrap_print(s: [*]const u8) void;

fn mandelbrot(cx: f64, cy: f64) u8 {
    var x: f64 = 0.0;
    var y: f64 = 0.0;
    var iter: u8 = 0;
    while (@intCast(u32, iter) < @intCast(u32, MaxIter)) {
        const x2 = x * x;
        const y2 = y * y;
        if (x2 + y2 > 4.0) break;
        const newx = x2 - y2 + cx;
        y = 2.0 * x * y + cy;
        x = newx;
        iter += 1;
    }
    return iter;
}

fn mapToChar(iter: u8) u8 {
    const CharMap = [16]u8{ ' ', '.', ':', '-', '=', '+', '*', '#', '%', '&', '@', '@', '@', '@', '@', '@' };
    const iter_u32 = @intCast(u32, iter);
    const idx = @intCast(usize, (iter_u32 * 15) / @intCast(u32, MaxIter));
    return CharMap[idx];
}

pub fn main() void {
    const step_x = 3.5 / @intToFloat(f64, Width);
    const step_y = 2.0 / @intToFloat(f64, Height);
    const x0 = -2.5;
    const y0 = -1.0;

    var y: usize = 0;
    while (y < Height) {
        const cy = y0 + @intToFloat(f64, y) * step_y;
        var line: [Width]u8 = undefined;
        var x: usize = 0;
        while (x < Width) {
            const cx = x0 + @intToFloat(f64, x) * step_x;
            const iter = mandelbrot(cx, cy);
            line[x] = mapToChar(iter);
            x += 1;
        }

        // Build null‑terminated string for C-interop
        var c_str: [Width + 1]u8 = undefined;
        var i: usize = 0;
        while (i < Width) {
            c_str[i] = line[i];
            i += 1;
        }
        c_str[Width] = 0;

        __bootstrap_print(&c_str[0]);
        __bootstrap_print("\n");

        y += 1;
    }
}
