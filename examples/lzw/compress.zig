const dict = @import("dict.zig");
const io = @import("io.zig");

pub fn compress() dict.LzwError!void {
    var lzw_dict: dict.Dictionary = undefined;
    dict.init(&lzw_dict);

    const first = io.readByte();
    if (first == -1) return;

    var prefix: i32 = first;

    while (true) {
        const c = io.readByte();
        if (c == -1) break;

        const suffix = @intCast(u8, c);
        const found = dict.find(&lzw_dict, prefix, suffix);

        if (found != -1) {
            prefix = found;
        } else {
            io.writeCode(prefix);

            // Try to add to dictionary, but ignore if full (traditional LZW choice)
            // or we could return an error. Here we demonstrate errdefer if we had cleanup.
            dict.add(&lzw_dict, prefix, suffix) catch |err| {
                if (err == dict.LzwError.DictionaryFull) {
                    // In a real compressor we might reset the dictionary here.
                    // For this demo, we just stop adding.
                } else {
                    return err;
                }
            };

            prefix = @intCast(i32, suffix);
        }
    }
    io.writeCode(prefix);
}
