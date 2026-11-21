// stdlib_local_type_fieldcap_xmod — Task B2 final fix wave positive control:
// a function-local aggregate with exactly the 32-field cap still emits valid C
// and runs. Guards the `registerContainerType` >32-field clean reject from
// over-rejecting the boundary (the 33-field case is the reject control
// `local_type_fieldcap_reject_xmod`).
//
// Every check is `@panic`-guarded; stdout is deterministic and RUNRC=0.
//
//   fieldcap-32-ok
//   done
const std = @import("std");

fn cap32() u32 {
    const S = struct {
        f0: u32, f1: u32, f2: u32, f3: u32, f4: u32, f5: u32, f6: u32, f7: u32,
        f8: u32, f9: u32, f10: u32, f11: u32, f12: u32, f13: u32, f14: u32, f15: u32,
        f16: u32, f17: u32, f18: u32, f19: u32, f20: u32, f21: u32, f22: u32, f23: u32,
        f24: u32, f25: u32, f26: u32, f27: u32, f28: u32, f29: u32, f30: u32, f31: u32,
    };
    var s: S = undefined;
    s.f0 = 1;
    s.f31 = 32;
    if (s.f0 != 1 or s.f31 != 32) @panic("fieldcap boundary");
    return s.f0 + s.f31;
}

pub fn main() void {
    if (cap32() != 33) @panic("ret");
    std.io.print("fieldcap-32-ok\n");
    std.io.print("done\n");
}
