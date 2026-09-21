// local_type_fieldcap_reject_xmod — Task B2 final fix wave negative control:
// a function-local struct with more than 32 fields clean-rejects. Before the
// fix `registerContainerType`'s fixed `[32]` field scratch buffers silently
// truncated the aggregate (32 fields registered) and emitted/miscompiled
// invalid C (field access beyond the cap aliased field 0; a named-type field
// could reference an undeclared `zT_*`).
//
// Contract: dump rc=2, 0 `.c`,
//   error[3000]: aggregate type has more than 32 fields, which is not supported
fn f() u32 {
    const S = struct {
        f0: u32, f1: u32, f2: u32, f3: u32, f4: u32, f5: u32, f6: u32, f7: u32,
        f8: u32, f9: u32, f10: u32, f11: u32, f12: u32, f13: u32, f14: u32, f15: u32,
        f16: u32, f17: u32, f18: u32, f19: u32, f20: u32, f21: u32, f22: u32, f23: u32,
        f24: u32, f25: u32, f26: u32, f27: u32, f28: u32, f29: u32, f30: u32, f31: u32,
        f32: u32,
    };
    var s: S = undefined;
    s.f32 = 7;
    return s.f32;
}

pub fn main() void {
    _ = f();
}
