// global_struct_array_store_xmod — RUNTIME-gated RED fixture (compile-gate OK, run zeros/garbage).
//
// Bug: zig1 DROPS a struct-value assignment into a STORAGE-GLOBAL array element. A whole-element
// store whose target is a subscripted module-scope global (e.g. `rooms[0] = Room { ... };`) is
// emitted as an assign_index whose base is the by-name load_global alias temp of the global array
// (c89_emit.zig:5172-5181 temp_global_map). The emitter's DCE pass never read-marks an
// ARRAY-typed assign_index base (c89_emit.zig:7080, dceTempIsArray :7055-7068), so that alias
// temp has read_count 0, is classified dead (c89_emit.zig:3380), and the per-instruction
// emission filter (c89_emit.zig:7384-7387, assign_index "result" = base via dceResultPos :7202)
// SKIPS emitting the store. Because every later read of the global makes a fresh load_global
// alias temp, a storage-global array element store is dead-classified in EVERY function that
// performs it -> the store is unconditionally dropped; init() builds the value in locals and
// `return;`s with no write-back. Original repro: examples/z98/mud_server/main.zig:22-47 —
// initRooms() emits zT_0.north = 1; ... then `return;` with no `zG_...rooms[0] = zT_0;`, so the
// world global is all-zero and mud movement never works (DBG dir=0 tag=1 room=0 north=0).
//
// Shape matrix (probes, all 4 compilers): (a) field store `rooms[0].north = v` — EMITTED,
// correct; (b) whole struct-literal store `rooms[0] = Room{...}` — DROPPED (this fixture);
// (c) copy from a named local `var r: Room = ...; rooms[0] = r;` — DROPPED; (d) local-array
// element store `var a: [2]Room = undefined; a[0] = Room{...}` — EMITTED, correct (survives only
// because the local array is read later in the same fn; a never-read local array store is also
// DCE-dropped — the drop is liveness-driven and hits the always-unread global alias every time).
//
// This fixture mirrors the mud initRooms() shape: a file-scope `var rooms: [2]Room = undefined;`
// populated by whole-struct-literal stores in a called init fn. A correct compiler must print the
// source-set values from main. Field-store sibling control (same values via the working
// `rooms[i].field = v` path) prints exactly the expected GREEN stdout below.
//
// RED today (all 4 compilers share the defect): run rc=0 with stdout `0 0 0 0` (8 B) — the
// initRooms stores are dropped, the rooms global stays zero-initialized (north == 0, desc is a
// null slice so len == 0).
// GREEN (after the store-drop fix) = deterministic stdout:
//   1 5 5 10
// (10 bytes; rooms[0].north=1 rooms[0].desc.len=5 rooms[1].north=5 rooms[1].desc.len=10,
// verified on the field-store sibling control which prints byte-identical output.)
const std = @import("std");

const Room = struct {
    desc: []const u8,
    north: u8,
    south: u8,
    east: u8,
    west: u8,
};

var rooms: [2]Room = undefined;

fn initRooms() void {
    rooms[0] = Room {
        .desc = "first",
        .north = @intCast(u8, 1),
        .south = @intCast(u8, 2),
        .east = @intCast(u8, 3),
        .west = @intCast(u8, 4)
    };
    rooms[1] = Room {
        .desc = "secondroom",
        .north = @intCast(u8, 5),
        .south = @intCast(u8, 6),
        .east = @intCast(u8, 7),
        .west = @intCast(u8, 8)
    };
}

pub fn main() void {
    initRooms();
    std.io.printInt(@intCast(i32, rooms[0].north));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, rooms[0].desc.len));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, rooms[1].north));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, rooms[1].desc.len));
    std.io.writeByte('\n');
}
