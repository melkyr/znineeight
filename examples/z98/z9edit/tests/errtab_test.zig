// errtab_test.zig — native Linux tests for the z9edit error-message table.
//
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT/errtab" examples/z98/z9edit/tests/errtab_test.zig
//   sh "$OUT/errtab/build_target.sh" linux "$OUT/errtab/errtab_test"
//   "$OUT/errtab/errtab_test"

const io = @import("std_io");
const os = @import("std_os");
const errtab = @import("../errtab.zig");

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn tKnown() bool {
    const m1 = errtab.errtabMessage(3001);
    if (m1) |s| {
        if (!eq(s, "undefined symbol")) return false;
    } else {
        return false;
    }
    const m2 = errtab.errtabMessage(3048);
    if (m2) |s| {
        if (!eq(s, "cannot read file")) return false;
    } else {
        return false;
    }
    return true;
}

fn tUnknown() bool {
    if (errtab.errtabMessage(9999) != null) return false;
    if (errtab.errtabMessage(0) != null) return false;
    if (errtab.errtabMessage(3021) != null) return false;
    return true;
}

pub fn main() void {
    report("known_code_message", tKnown());
    report("unknown_null", tUnknown());
    if (fails != 0) os.exit(1);
}
