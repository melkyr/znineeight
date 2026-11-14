// match.zig — z9edit headless core: bracket matching and balance.
//
// Z98 subset only, GUI-free. v1 balance is a raw byte scan (brackets inside
// strings/comments count too); that matches the "invert the adjacent pair"
// behavior the shell needs without a second lexer pass. `Unbalance.line` is
// 1-based per the status-bar contract.

const buffer = @import("buffer.zig");

pub const Unbalance = struct { ch: u8, line: usize };

const StackEntry = struct { ch: u8, pos: usize };
const MAX_STACK: usize = 1024;

fn isOpen(c: u8) bool {
    return c == '(' or c == '[' or c == '{';
}

fn isClose(c: u8) bool {
    return c == ')' or c == ']' or c == '}';
}

fn isMate(open: u8, close: u8) bool {
    if (open == '(' and close == ')') return true;
    if (open == '[' and close == ']') return true;
    if (open == '{' and close == '}') return true;
    return false;
}

fn lineOf(b: *buffer.GapBuffer, pos: usize) usize {
    var ln: usize = 0;
    var col: usize = 0;
    buffer.bufLineColOf(b, pos, &ln, &col);
    return ln + 1;
}

pub fn matchPairAt(b: *buffer.GapBuffer, pos: usize, mate: *usize) bool {
    const len = buffer.bufLen(b);
    if (pos >= len) return false;
    const c = buffer.bufByteAt(b, pos);
    if (isOpen(c)) {
        var depth: usize = 1;
        var i = pos + 1;
        while (i < len) : (i += 1) {
            const d = buffer.bufByteAt(b, i);
            if (d == c) {
                depth += 1;
            } else if (isMate(c, d)) {
                depth -= 1;
                if (depth == 0) {
                    mate.* = i;
                    return true;
                }
            }
        }
        return false;
    }
    if (isClose(c)) {
        var depth: usize = 1;
        var i = pos;
        while (i > 0) {
            i -= 1;
            const d = buffer.bufByteAt(b, i);
            if (d == c) {
                depth += 1;
            } else if (isMate(d, c)) {
                depth -= 1;
                if (depth == 0) {
                    mate.* = i;
                    return true;
                }
            }
        }
        return false;
    }
    return false;
}

pub fn matchUnbalanced(b: *buffer.GapBuffer, out: *Unbalance) bool {
    const len = buffer.bufLen(b);
    var stack: [MAX_STACK]StackEntry = undefined;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const c = buffer.bufByteAt(b, i);
        if (isOpen(c)) {
            if (depth < MAX_STACK) {
                stack[depth] = StackEntry{ .ch = c, .pos = i };
                depth += 1;
            }
        } else if (isClose(c)) {
            if (depth == 0) {
                out.* = Unbalance{ .ch = c, .line = lineOf(b, i) };
                return true;
            }
            if (!isMate(stack[depth - 1].ch, c)) {
                out.* = Unbalance{ .ch = c, .line = lineOf(b, i) };
                return true;
            }
            depth -= 1;
        }
    }
    if (depth > 0) {
        out.* = Unbalance{ .ch = stack[0].ch, .line = lineOf(b, stack[0].pos) };
        return true;
    }
    return false;
}
