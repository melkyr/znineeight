// content_test.zig — T1 content schema and row completeness (spec §14.2,
// §14.4, §25.1, §25.2).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/content_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/content_test"
//   "$OUT/content_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const creatures = @import("../creatures_t1.zig");

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

// Expected rows are transcribed from §14.2 (names, zones, phase) and §14.4
// (drops) in DEFS order, not derived from the table under test.

const EXPECTED_NAMES = [18][]const u8{
    "Mystic Eel",
    "Mystic Electric Eel",
    "Steel Tuna",
    "Anemoniacus",
    "Freezing Perch",
    "Rust Tuna",
    "Kelp Crab",
    "Brine Jelly",
    "Chitin Barnacle",
    "Spark Anemone",
    "Mileel",
    "Tunisteel",
    "Coral Crab",
    "Abyssal Lantern-Jelly",
    "Neon Ghost-Ray",
    "Glass Squid",
    "Brine Angler",
    "Ironclad Wrasse",
};

const EXPECTED_ZONE = [18]u32{
    3, 3, 3, 2, 4,
    7, 7, 6, 6, 3,
    2, 2, 6, 4, 4,
    4, 4, 4,
};

const EXPECTED_PHASE = [18]u32{
    3, 2, 3, 3, 3,
    3, 3, 2, 3, 3,
    1, 1, 3, 2, 2,
    2, 2, 1,
};

const D = def.DropLine;

fn ln(part: i32, count: i32) D {
    return D{ .part = part, .count = count };
}

const Z = D{ .part = 0, .count = 0 };
const L = def.MAX_DROP_LINES;

const SUB = [18][L]D{
    [L]D{ ln(1, 3), ln(3, 1), Z, Z },
    [L]D{ ln(3, 3), ln(1, 1), Z, Z },
    [L]D{ ln(2, 3), ln(1, 1), Z, Z },
    [L]D{ ln(6, 2), ln(5, 2), Z, Z },
    [L]D{ ln(4, 3), ln(2, 1), Z, Z },
    [L]D{ ln(2, 2), ln(1, 2), Z, Z },
    [L]D{ ln(5, 2), ln(1, 2), Z, Z },
    [L]D{ ln(4, 3), ln(1, 1), Z, Z },
    [L]D{ ln(1, 4), ln(5, 1), Z, Z },
    [L]D{ ln(3, 2), ln(1, 1), Z, Z },
    [L]D{ ln(3, 4), ln(1, 2), ln(8, 1), Z },
    [L]D{ ln(2, 4), ln(1, 2), ln(9, 2), Z },
    [L]D{ ln(5, 3), ln(1, 2), Z, Z },
    [L]D{ ln(6, 2), ln(4, 3), Z, Z },
    [L]D{ ln(6, 4), ln(4, 2), Z, Z },
    [L]D{ ln(7, 4), ln(4, 2), Z, Z },
    [L]D{ ln(6, 2), ln(4, 2), Z, Z },
    [L]D{ ln(2, 3), ln(5, 2), ln(7, 2), Z },
};

const KILL = [18][L]D{
    [L]D{ ln(1, 2), Z, Z, Z },
    [L]D{ ln(3, 1), ln(1, 1), Z, Z },
    [L]D{ ln(2, 2), Z, Z, Z },
    [L]D{ ln(3, 1), ln(5, 1), Z, Z },
    [L]D{ ln(4, 1), ln(2, 1), Z, Z },
    [L]D{ ln(1, 2), Z, Z, Z },
    [L]D{ ln(5, 1), ln(1, 1), Z, Z },
    [L]D{ ln(4, 1), ln(1, 1), Z, Z },
    [L]D{ ln(1, 2), Z, Z, Z },
    [L]D{ ln(3, 1), ln(1, 1), Z, Z },
    [L]D{ ln(3, 2), ln(1, 1), Z, Z },
    [L]D{ ln(2, 2), ln(1, 1), Z, Z },
    [L]D{ ln(5, 1), ln(1, 1), Z, Z },
    [L]D{ ln(6, 1), ln(4, 1), Z, Z },
    [L]D{ ln(6, 1), ln(4, 1), Z, Z },
    [L]D{ ln(7, 1), ln(4, 1), Z, Z },
    [L]D{ ln(6, 1), ln(4, 1), Z, Z },
    [L]D{ ln(2, 2), ln(5, 1), Z, Z },
};

const OVER = [18][L]D{
    [L]D{ ln(1, 1), Z, Z, Z },
    [L]D{ ln(3, 1), Z, Z, Z },
    [L]D{ ln(2, 1), Z, Z, Z },
    [L]D{ ln(5, 1), Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z },
    [L]D{ ln(3, 1), Z, Z, Z },
    [L]D{ ln(3, 1), Z, Z, Z },
    [L]D{ ln(2, 1), Z, Z, Z },
    [L]D{ ln(1, 1), Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z },
    [L]D{ ln(4, 1), Z, Z, Z },
    [L]D{ ln(2, 1), Z, Z, Z },
};

fn nameIs(d: *const def.CreatureDef, want: []const u8) bool {
    if (d.name_len != @intCast(i32, want.len)) return false;
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        if (d.name[i] != want[i]) return false;
    }
    return true;
}

fn namesEqual(a: *const def.CreatureDef, b: *const def.CreatureDef) bool {
    if (a.name_len != b.name_len) return false;
    var i: usize = 0;
    while (i < @intCast(usize, a.name_len)) : (i += 1) {
        if (a.name[i] != b.name[i]) return false;
    }
    return true;
}

fn tableMatches(actual: []const D, expected: []const D) bool {
    if (expected.len > def.MAX_DROP_LINES) return false;
    var i: usize = 0;
    while (i < def.MAX_DROP_LINES) : (i += 1) {
        var want_part: i32 = 0;
        var want_count: i32 = 0;
        if (i < expected.len) {
            want_part = expected[i].part;
            want_count = expected[i].count;
        }
        if (actual[i].part != want_part) return false;
        if (actual[i].count != want_count) return false;
    }
    return true;
}

fn tNames() bool {
    if (creatures.DEFS.len != 18) return false;
    if (EXPECTED_NAMES.len != 18) return false;

    var i: usize = 0;
    while (i < 18) : (i += 1) {
        const d = creatures.DEFS[i];
        const want = EXPECTED_NAMES[i];
        if (want.len == 0) return false;
        if (want.len > def.MAX_NAME_LEN) return false;
        if (!nameIs(&d, want)) return false;

        var j: usize = 0;
        while (j < @intCast(usize, d.name_len)) : (j += 1) {
            if (d.name[j] < 0x20) return false;
            if (d.name[j] > 0x7e) return false;
        }

        var k: usize = i + 1;
        while (k < 18) : (k += 1) {
            const other = creatures.DEFS[k];
            if (namesEqual(&d, &other)) return false;
        }
    }
    return true;
}

fn tMasks() bool {
    if (creatures.DEFS.len != 18) return false;

    var i: usize = 0;
    while (i < 18) : (i += 1) {
        const d = creatures.DEFS[i];
        if (d.zone_mask != EXPECTED_ZONE[i]) return false;
        if (d.phase_mask != EXPECTED_PHASE[i]) return false;
        if (d.zone_mask == 0) return false;
        if (d.phase_mask == 0) return false;
        if ((d.phase_mask & 0x3) != d.phase_mask) return false;
    }
    return true;
}

fn tDrops() bool {
    if (creatures.DEFS.len != 18) return false;

    var i: usize = 0;
    while (i < 18) : (i += 1) {
        const d = creatures.DEFS[i];
        if (!tableMatches(d.sub[0..], SUB[i][0..])) return false;
        if (!tableMatches(d.kill[0..], KILL[i][0..])) return false;
        if (!tableMatches(d.over[0..], OVER[i][0..])) return false;
    }
    return true;
}

fn tTablesBudget() bool {
    if (@sizeOf(def.Tables) > 32 * 1024) return false;
    if (@sizeOf(def.CreatureDef) > 288) return false;
    return true;
}

pub fn main() void {
    report("creature_names_nonempty_unique_24", tNames());
    report("creature_masks_match_s14_2", tMasks());
    report("creature_drops_match_s14_4", tDrops());
    report("tables_size_within_32k_budget", tTablesBudget());

    if (fails != 0) os.exit(1);
    io.write("content_test PASS\n");
}
