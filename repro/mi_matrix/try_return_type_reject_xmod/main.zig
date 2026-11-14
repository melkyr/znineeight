// try_return_type_reject_xmod — FX12 (Volume II ch12) reject fixture.
//
// Zig 0.15.2 parity for `try`: the enclosing function must return an error
// union whose error set contains the operand's set, and the operand itself
// must be an error union. Before FX12 every shape below compiled rc 0 (A2
// even emitted gcc-invalid C and A1/A3 silently dropped the error). Each site
// is exactly one level-0 `error[3075]` (`ERR_3075_TRY_ENCLOSING_RETURN`,
// deduped per try node, span on the `try`), 0 `.c` emitted, no signals, no
// warnings; the census is pinned in `expected_error.txt` (`3075 9`).
//
// The three Zig-shaped messages (exact texts):
//   enclosing return not an error union:
//     expected type '<ret-kind>', found error set
//     note: function cannot return an error
//     (a1/a2/nb: 'void'/'i32'; opt: 'optional'; ifv/swv: 'void')
//   operand's set not a subset of the enclosing function's set:
//     try error set may not be compatible with the enclosing function's return type
//     (a3, cross-module)
//   operand not an error union:
//     expected error union type, found '<kind>'
//     note: consider omitting 'try'
//     (a4: 'comptime_int')
//   container-level `try` (module initializer):
//     'try' outside function scope
//     (ctry)
//
// Note on the if-value shape: it is written `_ = if (...) ... else 0;`
// (a value-position discard) so the census stays one 3075 per site -- the
// poison return types the `if` `void`, and a `const` binding would add the
// pre-existing `error[3000]: cannot declare variable of type void`.
const helper = @import("helper.zig");

const E1 = error{A};

fn gA1() !void {
    return error.Boom;
}

// A1: `void` function, erroring `!void` operand.
fn a1() void {
    try gA1();
}

fn gA2() !void {
    return error.Boom;
}

// A2: `i32` function.
fn a2() i32 {
    try gA2();
    return 1;
}

// A3: cross-module set mismatch (helper E2 into caller E1).
fn a3() E1!void {
    try helper.gA3();
}

// A4: non-error-union operand.
fn a4() void {
    try 5;
}

fn gNB() !void {
    return error.Boom;
}

// Nested-block `i32` return.
fn nb() i32 {
    {
        try gNB();
    }
    return 1;
}

fn gOPT() !void {
    return error.Boom;
}

// Optional (`?i32`) return.
fn opt() ?i32 {
    try gOPT();
    return 1;
}

fn gIF() !i32 {
    return error.Boom;
}

// if-value payload shape in a `void` function.
fn ifv() void {
    _ = if (true) try gIF() else 0;
}

fn gSW() !i32 {
    return error.Boom;
}

// switch-value payload shape in a `void` function.
fn swv() void {
    const x = switch (1) {
        else => try gSW(),
    };
}

fn gCT() !void {
    return error.Boom;
}

// Container-level `try` (module initializer).
const ctry = try gCT();

pub fn main() void {
    _ = a1;
    _ = a2;
    _ = a3;
    _ = a4;
    _ = nb;
    _ = opt;
    _ = ifv;
    _ = swv;
    _ = ctry;
}
