# RED: lzw_eu_return_mismatch (CRASH)

**Minimal repro:** `catch |err| return err` with error union functions.  
**zig1:** SEGV crash in lowerExprImpl, 0 bytes C output, dump rc=134 (CRASH).  
**zig0 oracle:** rc=0, gcc rc=0 — accepts the program.  

**Root cause:** Lowerer SEGV when processing `catch |err| return err` where the returned error union TypeId differs from function's declared return TypeId. Crash in lowerExprImpl at address 0x94 (likely null deref). Same general class as C5 cross-module crash.
