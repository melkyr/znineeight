// In-place lexical normalization of a `/`-separated path.
// Collapses `.`/`..` segments and `//` runs so that syntactically different
// but physically identical path spellings become byte-equal.
//
// Contract:
//   - `buf` is the caller's mutable scratch; `buf.len >= src.len` required.
//   - `src` may alias `buf` (in-place); the write cursor never overtakes the
//     read cursor because output length <= input length.
//   - Returns the canonicalized sub-slice (aliases `buf`); null if `buf` too small.
//
// Rules (F-PATHNORM-Inv §2.2):
//   1. Absolute prefix: leading `/` seeds a single root `/`; relative keeps none.
//   2. Segment split on `/`; empty segments (runs, leading/trailing) dropped.
//   3. `.` segment dropped.
//   4. `..`: pops the segment stack when non-empty; dropped above root when
//      absolute; kept as a leading `..` when relative (CWD-relative).
//   5. Real segment pushed + written, `/` separator when output lacks one.
//   6. Trailing slash trimmed.
//   7. Empty result: absolute -> "/", relative -> "." (never "").
//   8. `//` runs collapse (rule 2).
//   9. `..` popping the absolute anchor leaves exactly `/`.
//
// Segment stack is fixed [512]usize (4 KB). A path < 512 bytes has <= 256
// single-char segments, so 512 entries is safe; pushes are guarded anyway.
pub fn normalizePath(buf: []u8, src: []const u8) ?[]const u8 {
    if (buf.len < src.len) return null;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        buf[i] = src[i];
    }
    var len: usize = src.len;
    var out_len: usize = 0;
    var is_abs: usize = 0;
    if (len > 0 and buf[0] == '/') {
        is_abs = 1;
        buf[0] = '/';
        out_len = 1;
    }
    var stack: [512]usize = undefined;
    var stack_len: usize = 0;
    var seg_start: usize = if (is_abs == 1) @intCast(usize, 1) else @intCast(usize, 0);
    var pos: usize = seg_start;
    while (pos <= len) : (pos += 1) {
        var is_sep: u32 = 0;
        if (pos == len) {
            is_sep = 1;
        } else if (buf[pos] == '/') {
            is_sep = 1;
        }
        if (is_sep == 1) {
            var seg_len: usize = pos - seg_start;
            if (seg_len > 0) {
                var is_dot: u32 = 0;
                var is_dotdot: u32 = 0;
                if (seg_len == 1 and buf[seg_start] == '.') is_dot = 1;
                if (seg_len == 2 and buf[seg_start] == '.' and buf[seg_start + 1] == '.') is_dotdot = 1;
                if (is_dot == 0 and is_dotdot == 0) {
                    if (out_len > 0 and buf[out_len - 1] != '/') {
                        buf[out_len] = '/';
                        out_len += 1;
                    }
                    if (stack_len < 512) {
                        stack[stack_len] = out_len;
                        stack_len += 1;
                    }
                    var k: usize = 0;
                    while (k < seg_len) : (k += 1) {
                        buf[out_len + k] = buf[seg_start + k];
                    }
                    out_len += seg_len;
                } else if (is_dotdot == 1) {
                    if (stack_len > 0) {
                        stack_len -= 1;
                        out_len = stack[stack_len];
                        if (out_len > is_abs and buf[out_len - 1] == '/') out_len -= 1;
                    } else if (is_abs == 0) {
                        if (out_len > 0 and buf[out_len - 1] != '/') {
                            buf[out_len] = '/';
                            out_len += 1;
                        }
                        buf[out_len] = '.';
                        out_len += 1;
                        buf[out_len] = '.';
                        out_len += 1;
                    }
                }
            }
            seg_start = pos + 1;
        }
    }
    while (out_len > 1 and buf[out_len - 1] == '/') {
        out_len -= 1;
    }
    if (out_len == 0) {
        if (is_abs == 1) {
            buf[0] = '/';
            out_len = 1;
        } else {
            buf[0] = '.';
            out_len = 1;
        }
    }
    return buf[0..out_len];
}
