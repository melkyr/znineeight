// errtab.zig — z9edit headless core: `error[NNNN]` -> human-readable message.
//
// Z98 subset only, GUI-free. Hand-maintained const table seeded from the
// ERR_30xx members in `sf/src/diagnostics.zig` (no compiler coupling: the
// editor keeps its own copy so the standalone binary does not import the
// compiler). Unknown codes return null.

const Entry = struct { code: u32, msg: []const u8 };

const TABLE = [_]Entry{
    Entry{ .code = 3000, .msg = "type mismatch" },
    Entry{ .code = 3001, .msg = "undefined symbol" },
    Entry{ .code = 3002, .msg = "invalid assignment" },
    Entry{ .code = 3003, .msg = "missing return" },
    Entry{ .code = 3004, .msg = "switch not exhaustive" },
    Entry{ .code = 3005, .msg = "circular type dependency" },
    Entry{ .code = 3006, .msg = "invalid coercion" },
    Entry{ .code = 3007, .msg = "visibility violation" },
    Entry{ .code = 3008, .msg = "enum literal requires payload" },
    Entry{ .code = 3009, .msg = "unknown enum literal member" },
    Entry{ .code = 3010, .msg = "cannot infer enum literal type" },
    Entry{ .code = 3011, .msg = "error literal not in set" },
    Entry{ .code = 3012, .msg = "varargs invalid" },
    Entry{ .code = 3013, .msg = "invalid print specifier" },
    Entry{ .code = 3014, .msg = "use of undefined variable" },
    Entry{ .code = 3015, .msg = "error ignored" },
    Entry{ .code = 3016, .msg = "orelse requires optional" },
    Entry{ .code = 3017, .msg = "suspending function pointer" },
    Entry{ .code = 3018, .msg = "async suspend outside suspending function" },
    Entry{ .code = 3019, .msg = "async builtin in defer" },
    Entry{ .code = 3020, .msg = "unhandled node kind" },
    Entry{ .code = 3045, .msg = "unknown calling convention" },
    Entry{ .code = 3046, .msg = "async frame size invalid" },
    Entry{ .code = 3047, .msg = "async frame large" },
    Entry{ .code = 3048, .msg = "cannot read file" },
    Entry{ .code = 3049, .msg = "ptrCast requires two arguments" },
    Entry{ .code = 3050, .msg = "array size not constant" },
    Entry{ .code = 3051, .msg = "return inside defer" },
    Entry{ .code = 3052, .msg = "break out of defer" },
    Entry{ .code = 3053, .msg = "continue out of defer" },
    Entry{ .code = 3054, .msg = "try inside defer" },
    Entry{ .code = 3055, .msg = "enum value not constant" },
    Entry{ .code = 3056, .msg = "call target not callable" },
    Entry{ .code = 3057, .msg = "local shadow" },
    Entry{ .code = 3058, .msg = "condition not bool" },
    Entry{ .code = 3059, .msg = "if without else" },
    Entry{ .code = 3060, .msg = "method syntax not supported" },
    Entry{ .code = 3061, .msg = "wrong argument count" },
    Entry{ .code = 3062, .msg = "index out of bounds" },
    Entry{ .code = 3063, .msg = "print type not supported" },
    Entry{ .code = 3064, .msg = "cyclic global init" },
    Entry{ .code = 3065, .msg = "print container not tuple" },
    Entry{ .code = 3066, .msg = "single pointer index" },
    Entry{ .code = 3067, .msg = "single pointer slice bounds" },
    Entry{ .code = 3068, .msg = "switch without else" },
    Entry{ .code = 3069, .msg = "tuple index not comptime" },
    Entry{ .code = 3070, .msg = "tuple index out of range" },
    Entry{ .code = 3071, .msg = "switch case qualifier" },
    Entry{ .code = 3072, .msg = "offset target not struct" },
    Entry{ .code = 3073, .msg = "offset unknown field" },
    Entry{ .code = 3074, .msg = "comptime builtin unresolved" },
    Entry{ .code = 3075, .msg = "try enclosing return" },
    Entry{ .code = 3076, .msg = "enum literal numeric compare" },
};

pub fn errtabMessage(code: u32) ?[]const u8 {
    var i: usize = 0;
    while (i < TABLE.len) : (i += 1) {
        if (TABLE[i].code == code) return TABLE[i].msg;
    }
    return null;
}
