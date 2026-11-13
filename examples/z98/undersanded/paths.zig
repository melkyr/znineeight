const str = @import("std_str");

fn is83Char(c: u8) bool {
    if (c >= 'a' and c <= 'z') return true;
    if (c >= '0' and c <= '9') return true;
    return c == '_' or c == '-';
}

pub fn is83Name(name: []const u8) bool {
    if (name.len == 0) return false;

    var base_end: usize = name.len;
    const dot = str.findChar(name, '.');
    if (dot) |d| {
        base_end = d;
        const ext = name[d + 1 .. name.len];
        if (ext.len < 1 or ext.len > 3) return false;
        var ei: usize = 0;
        while (ei < ext.len) : (ei += 1) {
            if (!is83Char(ext[ei])) return false;
        }
    }

    if (base_end < 1 or base_end > 8) return false;
    var i: usize = 0;
    while (i < base_end) : (i += 1) {
        if (!is83Char(name[i])) return false;
    }
    return true;
}

pub fn pathJoin83(dir: []const u8, name: []const u8, out: []u8) ?[]u8 {
    if (!is83Name(name)) return null;

    var sep = true;
    if (dir.len == 0) {
        sep = false;
    } else {
        const last = dir[dir.len - 1];
        if (last == '\\' or last == '/') sep = false;
    }

    var need: usize = dir.len + name.len;
    if (sep) need += 1;
    if (need > out.len) return null;

    str.copy(out, dir);
    var o: usize = dir.len;
    if (sep) {
        out[o] = '\\';
        o += 1;
    }
    str.copy(out[o..], name);
    return out[0..need];
}
