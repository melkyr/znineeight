const dict = @import("dict.zig");
const io = @import("io.zig");
const comp = @import("compress.zig");
const decomp = @import("decompress.zig");

extern fn getchar() i32;

pub fn main() void {
    io.printStr("LZW Compressor/Decompressor Demo\n");
    io.printStr("Select mode: [c]ompress, [d]ecompress: ");

    const choice = getchar();
    // Consume newline if present
    const next = getchar();
    if (next != @intCast(i32, '\n') and next != -1) {
        // Just keep going
    }

    if (choice == @intCast(i32, 'c')) {
        io.printStr("Enter text to compress (end with EOF/Ctrl-D):\n");
        comp.compress() catch |err| {
            if (err == dict.LzwError.DictionaryFull) {
                io.printErr("Dictionary full!");
            } else {
                // Already handled by errdefer in compress.zig if we wanted,
                // but we can add more specific info here.
                io.printErr("Compression failed!");
            }
            return;
        };
        io.writeByte('\n');
    } else if (choice == @intCast(i32, 'd')) {
        io.printStr("Enter space-separated codes to decompress (end with EOF/Ctrl-D):\n");
        decomp.decompress() catch |err| {
            io.printErr("Decompression failed!");
            return;
        };
        io.writeByte('\n');
    } else {
        io.printErr("Invalid choice!");
    }

    defer io.printStr("LZW Operation Finished.\n");
}
