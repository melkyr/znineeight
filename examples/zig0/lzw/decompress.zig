const dict = @import("dict.zig");
const io = @import("io.zig");

/// Decodes a code and returns the first character of its expansion.
fn emitAndGetFirst(lzw_dict: *dict.Dictionary, code: i32) u8 {
    if (code < 256) {
        const c = @intCast(u8, code);
        io.writeByte(c);
        return c;
    }

    const prefix = dict.getPrefix(lzw_dict, @intCast(usize, code));
    const char = dict.getChar(lzw_dict, @intCast(usize, code));

    const first = emitAndGetFirst(lzw_dict, prefix);
    io.writeByte(char);
    return first;
}

pub fn decompress() dict.LzwError!void {
    errdefer io.printErr("Decompression aborted.");

    var lzw_dict: dict.Dictionary = undefined;
    dict.init(&lzw_dict);

    const first_code = io.readCode();
    if (first_code == -1) return;

    var old_code = first_code;
    var char = emitAndGetFirst(&lzw_dict, old_code);

    while (true) {
        const new_code = io.readCode();
        if (new_code == -1) break;

        if (@intCast(usize, new_code) < lzw_dict.size) {
            char = emitAndGetFirst(&lzw_dict, new_code);
            try dict.add(&lzw_dict, old_code, char);
        } else {
            // Special case for LZW: KwKwK
            const first = emitAndGetFirst(&lzw_dict, old_code);
            io.writeByte(first);
            try dict.add(&lzw_dict, old_code, first);
        }
        old_code = new_code;
    }
}
