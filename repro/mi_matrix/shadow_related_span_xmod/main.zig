// shadow_related_span_xmod — Task 18 reject fixture.
//
// Every `error[3057]` shadow/redeclaration diagnostic must also render a
// related span pointing at the previous declaration, the way official Zig
// 0.15.2 renders `note: previous declaration here` (local/param/capture) or
// `note: declared here` (container-level declaration). Expected stderr (pinned
// in NOTES.md): one `main.zig:<line>: note: ...` line after each error excerpt.
//
// Container-level declaration (shadowed by containerForm below).
const g: i32 = 1;

// 1. function-local shadows a parameter (related span -> the parameter).
fn paramForm(x: i32) void {
    var x: i32 = 5;
    _ = x;
}

// 2. inner `const` shadows an outer local (related span -> the outer local),
//    and 3. same-scope redeclaration (`previous declaration here`).
fn localForm() void {
    var outer: i32 = 1;
    {
        const outer = 2;
        _ = outer;
    }
    const twice = 1;
    _ = twice;
    const twice = 2;
    _ = twice;
}

// 4. `if` capture shadows an outer local (related span -> the outer local).
fn captureForm(opt: ?i32) void {
    var cap: i32 = 1;
    if (opt) |cap| {
        _ = cap;
    }
}

// 5. local shadows a container-level declaration (`note: declared here`).
fn containerForm() void {
    const g = 9;
    _ = g;
}

pub fn main() void {
    paramForm(1);
    localForm();
    captureForm(null);
    containerForm();
}
