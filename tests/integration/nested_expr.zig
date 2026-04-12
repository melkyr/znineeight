const Cell = union(enum) { A: void, B: void, C: void };
pub fn main() void {
    var a = true;
    var b = false;
    var x: Cell = if (a) (if (b) .A else .B) else .C;

    var n = 1;
    var y: Cell = switch (n) {
        1 => switch (n) { 1 => .A, else => .B },
        else => .C,
    };
}
