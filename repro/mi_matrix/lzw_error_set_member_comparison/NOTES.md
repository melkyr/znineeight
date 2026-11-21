# RED: lzw_error_set_member_comparison

**Minimal repro:** `var e: E = E.A; _ = e == E.A;`  
**zig1:** dump rc=0, gcc errors — `unknown type name zT_C00BF080_E` + `'zT_3' undeclared`  
**zig0 oracle:** rc=0, gcc rc=0  

**Root cause:** c89_emit does not emit error set member values as C enum/#define constants.  
`E.A` comparison in generated C references `zT_3` (member constant) which is never defined.  
Error set type `zT_C00BF080_E` is also not emitted (pre-existing gap, shared with C2/lzw_error_set_typedef).
