const Cell = union(enum) { Alive: void, Dead: void };
pub fn main() void {
    var arr: [2]Cell = .{ .Alive, .Dead };
}
