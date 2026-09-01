# fn_ptr_struct_field — RED  [std-lib Phase 1]

## What it tests
Struct containing a function-pointer field (`const Writer = struct { write_fn: fn([]const u8) void };`) — the vtable idiom the std-lib `Writer` struct design needs. Zero corpus coverage before this repro.

## zig1 evidence
- **dump rc:** 0
- **gcc:** 1 error — `main_0E9037BF.h:10:14: error: variable or field 'write_fn' declared void`
- **Classification:** FAIL per QUICK_REF classifier

## Notes
Dump succeeds (rc=0, 1 `.c` emitted) but the emitted C struct is wrong: the function-pointer field is emitted as `void write_fn;` instead of a function-pointer type. gcc rejects the header. This is an emission defect (struct fn-ptr field type not lowered). **Blocks the std-lib `Writer` vtable struct design as written** — the fn-ptr field must be emitted as a real C function pointer for the struct to be usable.
