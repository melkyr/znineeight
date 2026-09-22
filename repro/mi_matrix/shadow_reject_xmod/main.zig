// shadow_reject_xmod — Task 7D reject fixture.
//
// Official Zig 0.15.2: "Variable identifiers are never allowed to shadow
// identifiers from an outer scope." Each site below reuses an identifier that
// is already declared in a strictly-enclosing scope or the same scope (Zig's
// shadow / redeclaration), or shadows a container-level declaration. Every one
// must clean-reject with `error[3057]` at the shadowing declaration, rc=2 and
// 0 emitted `.c`. The `_` discard is NOT a binding and may be re-bound freely
// (covered by the shadow_ok_xmod positive control).

const std = @import("std");

// Container-level declarations (shadowed by the containerForms below).
const g_const: i32 = 1;
var g_var: i32 = 2;
fn g_fn() i32 { return 3; }
const GType = struct { a: i32 };

// 1. inner `const` shadows an outer local `var`
// 2. inner `var` shadows an outer local `const`
fn localForms() void {
    var outer_var: i32 = 1;
    const outer_const: i32 = 2;
    {
        const outer_var = 10;
        _ = outer_var;
    }
    {
        var outer_const: i32 = 20;
        _ = outer_const;
    }
}

// 3. same-scope redeclaration (`var` then `var`).
fn redeclareForm() void {
    var dup: i32 = 1;
    _ = dup;
    var dup: i32 = 2;
    _ = dup;
}

// 4. function-local shadows a function parameter.
fn paramShadowedByLocal(x: i32) void {
    var x: i32 = 5;
    _ = x;
}

// 5. function parameter shadows a container-level declaration.
fn paramShadowsContainer(g_const: i32) void {
    _ = g_const;
}

// 6. local shadows a container-level `const`, `var`, `fn`, and type.
fn containerForms() void {
    const g_const = 10;
    _ = g_const;
    const g_var = 11;
    _ = g_var;
    const g_fn = 12;
    _ = g_fn;
    const GType = 13;
    _ = GType;
}

// 7. `if` / `while` / `for` capture shadows an outer local.
fn captureForms(opt: ?i32, arr: [2]i32) void {
    var if_cap: i32 = 1;
    if (opt) |if_cap| {
        _ = if_cap;
    }
    var wcap: i32 = 2;
    var wopt: ?i32 = null;
    while (wopt) |wcap| {
        _ = wcap;
        break;
    }
    var fcap: i32 = 3;
    for (arr) |fcap| {
        _ = fcap;
    }
}

const U = union(enum) { a: i32, b: void };

// 8. switch-prong capture shadows an outer local.
fn switchForm(u: U) void {
    var sc: i32 = 1;
    switch (u) {
        .a => |sc| {
            _ = sc;
        },
        .b => {},
    }
}

const MyErr = error{Foo};

// 9. `catch` payload shadows a local in the same block.
fn catchForm(r: MyErr!i32) void {
    var e: MyErr = MyErr.Foo;
    _ = e;
    const v = r catch |e| 0;
    _ = v;
}

pub fn main() void {
    localForms();
    redeclareForm();
    paramShadowedByLocal(1);
    paramShadowsContainer(1);
    containerForms();
    captureForms(null, .{ 1, 2 });
    switchForm(.{ .b = {} });
    catchForm(0);
    std.io.printInt(g_const);
}
