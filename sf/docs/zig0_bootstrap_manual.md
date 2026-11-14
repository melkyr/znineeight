# zig0 Bootstrap Manual

How to compile Z98 code with the zig0 bootstrap compiler. Based on /workspace/znineeight project structure.

## 1. Build zig0 from Source

```bash
cd /workspace/znineeight
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0
```

Source: `src/bootstrap/bootstrap_all.cpp` (single-file bootstrap).
Output: `zig0` binary in project root.

## 2. Standard Compilation Invocation

```bash
# Canonical form
./zig0 -o /absolute/path/output.c source.zig

# Without -o, writes per-module files to /tmp/
./zig0 source.zig
```

Notes:
- Always use `-o` with absolute path for reliable output.
- Zig0 sends diagnostics AND C code to stdout (no stderr separation).
- Warnings look like: `src/file.zig:LINE:COL: warning: message`.
- `--verbose` flag exists for debug output (per COMPATIBILITY.md).
- `--header-priority-include` does NOT exist.

## 3. zig0 Output Artifacts

When compiling with `-o /path/file.c`:
- Per-module `.c` files (one per `@import`)
- Per-module `.h` headers
- `zig_runtime.h` / `zig_runtime.c` — C runtime stubs
- `zig_compat.h` — platform compatibility defines
- `zig_special_types.h` — `Slice_u8`, `ErrorUnion_*`, etc.
- `platform_win98.h` — Win98 compatibility
- `build_target.sh` / `build_target.bat` — auto-generated build scripts

Output files go to the SAME DIRECTORY as the `-o` path.

## 4. Compile C89 Output with GCC

```bash
gcc -std=c89 \
    -Wno-long-long \
    -Wno-pointer-sign \
    -Wno-unused-but-set-variable \
    -Wno-implicit-function-declaration \
    -I/workspace/znineeight/include \
    *.c -o zig1
```

## 5. Import Patterns — CRITICAL

This is the most important rule for zig0 to generate correct C code.

### Module-qualified function calls (WORKS)

```zig
const mod = @import("mod.zig");
var result = try mod.someFunction(args);
// Generates: zF_<hash>_someFunction(args)  ← foreign function, links correctly
```

### Direct function import (BROKEN)

```zig
const someFunction = @import("mod.zig").someFunction;
var result = try someFunction(args);
// Generates: zC_<hash>_someFunction(args)  ← per-module stub, won't link
```

### Type imports (WORKS either way)

```zig
const TypeDirect = @import("mod.zig").SomeType;
const TypeViaMod = mod.SomeType;
// Both generate: struct zS_<hash>_SomeType
```

**Rule**: Always call functions through module qualifier (`mod.function()`).
Only import types directly if needed. Functions MUST be called via `mod.` prefix.

**Verified against**: `examples/rogue_mud/` — all 7 cross-module sand_alloc callers
use `sand_mod.sand_alloc(...)`, generating unified `zF_043628_sand_alloc`.

## 6. Free Functions Only — NO Method Syntax

Zig0 does NOT support `pub fn` inside `struct` blocks. All methods must be
free functions.

```zig
// BROKEN in zig0
pub const MyStruct = struct {
    pub fn init() MyStruct { ... }          // ❌ method syntax
    pub fn doSomething(self: *MyStruct) void { ... }  // ❌
};

// CORRECT
pub const MyStruct = struct { ... };

pub fn myStructInit() MyStruct { ... }     // ✅ free function
pub fn myStructDoSomething(self: *MyStruct) void { ... }  // ✅ free function
```

Naming convention: `ModuleName_functionName(self: *Type, ...) ReturnType`.

**Verified against**: `examples/rogue_mud/lib/sand.zig`, `room.zig`, `bsp.zig`.

## 7. Sand Allocator — The Proven Pattern

```zig
pub const Sand = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
};

pub fn sandInit(buffer: []u8) Sand {
    return Sand{
        .start = buffer.ptr,
        .pos = @intCast(usize, 0),
        .end = buffer.len,
    };
}

pub fn sandAlloc(sand: *Sand, size: usize, alignment: usize) ![*]u8 {
    const mask = alignment - 1;
    const aligned = (sand.pos + mask) & ~mask;
    if (aligned + size > sand.end) return error.OutOfMemory;
    const result = sand.start + aligned;
    sand.pos = aligned + size;
    return result;
}

pub fn sandReset(sand: *Sand) void {
    sand.pos = @intCast(usize, 0);
}
```

Usage:
```zig
var buf: [1024 * 1024]u8 = undefined;
var arena = sandInit(buf[0..]);
var ptr = try sandAlloc(&arena, 64, 4);
```

Store `arena: *Sand` in structs that need allocation:
```zig
pub const ArrayList = struct {
    items: [*]T,
    len: usize,
    capacity: usize,
    arena: *Sand,
};
```

**Reference**: `examples/rogue_mud/lib/sand.zig` (full implementation),
`examples/rogue_mud/lib/bsp.zig`, `room.zig`, `priority_queue.zig` (usage).

## 8. ArrayList — The Proven Pattern

No generics. Copy-specialize per type:

```zig
pub const U32ArrayList = struct {
    items: [*]u32,          // [*]T, NOT *T
    len: usize,             // usize, NOT u32
    capacity: usize,
    arena: *Sand,           // arena for growth
};

pub fn u32ArrayListInit(arena: *Sand) U32ArrayList {
    return U32ArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .arena = arena,
    };
}

pub fn u32ArrayListEnsureCapacity(self: *U32ArrayList, new_cap: usize) !void {
    if (new_cap <= self.capacity) return;
    var new_capacity = new_cap;
    if (new_capacity < self.capacity * 2) new_capacity = self.capacity * 2;
    if (new_capacity < 8) new_capacity = 8;
    // Use hardcoded size (4 for u32), NOT @sizeOf(u32)
    var raw = try mod.sandAlloc(self.arena, 4 * new_capacity, 4);
    var new_items = @ptrCast([*]u32, raw);
    var i: usize = 0;
    while (i < self.len) {
        new_items[i] = self.items[i];
        i += 1;
    }
    self.items = new_items;
    self.capacity = new_capacity;
}
```

**Reference**: `examples/rogue_mud/lib/room.zig:20-62`, `bsp.zig:13-61`, `priority_queue.zig:9-74`.

## 9. Known zig0 Codegen Bugs

### 9.1 ErrorUnion Slice_u8 not generated
```
Symptom: `error: unknown type name 'ErrorUnion_Slice_u8'`
Workaround: Return `[*]u8` instead of `![]const u8`, use `catch unreachable`
```

### 9.2 extern var linker errors
```
Symptom: `undefined reference to 'zV_<hash>___argc'`
Workaround: Stub with static variables, return 0/null from accessors
```

### 9.3 Long string literals not wrapped
```
Symptom: `incompatible type for argument 1 of 'zF_<hash>_fn'`
  (string literal passed where Slice_u8 struct expected)
Workaround: Use short strings, or assign to variable first
```

### 9.4 @sizeOf / @alignOf produce Unresolved call
```
Symptom: "Unresolved call at LINE:OFF" in zig0 output
Workaround: Use hardcoded size/alignment constants
```

### 9.5 @enumToInt / @intToEnum unsupported
```
Symptom: compile error or "Unresolved call"
Workaround: Manual switch statement mapping variants to integers
```

### 9.6 `return {}` in void functions
```
Symptom: Generates `__return_val = ;` in C (syntax error)
Workaround: No return in void functions
```

### 9.7 Integer literal `0` inferred as i32
```
Symptom: type mismatch when assigning to u32/usize
Workaround: Always use @intCast(usize, 0) for struct inits
```

### 9.8 `*T` not indexable in C
```
Symptom: `*u32` can't be subscripted
Workaround: Always use [*]T for array fields (many-item pointer)
```

### 9.9 no `&self.field` as l-value
```
Symptom: "Cannot take address of non-lvalue"
Workaround: Store sub-structs as *Type pointers, heap-allocated from arena.
  OR extract field to local, take &local.
```

### 9.10 error union `!` in function pointer types
```
Symptom: "function pointer type may not contain error unions" (paraphrased)
Workaround: Remove ! from function pointer types
```

### 9.11 string literal → Slice_u8 sometimes broken
```
Symptom: Some strings get __make_slice_u8(), some are raw char*
Workaround: Assign to variable before passing
```

### 9.12 Build script references non-existent files
```
Symptom: build_target.sh references `net_runtime.c` or other missing files
Workaround: Manual gcc invocation with all *.c files
```

### 9.13 exit() not implemented
```
Symptom: Calling exit from zig0-built code may hang or crash
Workaround: Spinning loop: while (true) {}
```

## 10. &self.field — NOT Allowed

Zig0 cannot take `&` of a struct field accessed through `self`:

```zig
fn process(self: *MyStruct) void {
    var x = &self.field;  // ❌ FAILS: "Cannot take address of non-lvalue"
}
```

**Fix**: Store sub-structs as `*Type` pointers, heap-allocated from sand:

```zig
pub const Parent = struct {
    child: *ChildType,  // pointer, not inline struct
};

pub fn parentInit(arena: *Sand) Parent {
    var raw = try sandAlloc(arena, @sizeOf(ChildType), 4);
    var child = @ptrCast(*ChildType, raw);
    child.* = childTypeInit(arena);
    return Parent{ .child = child };
}
```

Access is then `self.child.field` (working, because child is already a pointer).

## 11. Directory Structure

- Compile from project root (`/workspace/znineeight`), not from `src/` subdirectory.
- Zig0 resolves `@import` paths relative to the source file's location.
- All files in the import tree should be at sibling level for simplicity.
- `../` parent imports work but signal potential issues.

Working structure:
```
/workspace/znineeight/
  zig0                    -- bootstrap compiler binary
  sf/
    src/
      main.zig            -- entry point
      allocator.zig       -- Sand allocator
      string_interner.zig
      source_manager.zig
      diagnostics.zig
      ...
```

## 12. Testing

Zig0 does NOT have `test {}` blocks. Tests are standalone `pub fn main() !void` executables:

```zig
pub fn main() !void {
    var buf: [65536]u8 = undefined;
    var arena = sandInit(buf[0..]);

    // test body
    if (result != expected) {
        pal.stderr_write("FAIL\n");
        return;
    }
    pal.stderr_write("PASS\n");
}
```

**Reference**: `examples/rogue_mud/test/dungeon_test.zig`.

## 13. Where to Find Working Examples

| Example | Demonstrates |
|---------|-------------|
| `examples/hello/` | Minimal extern fn, stderr_write, main() |
| `examples/rogue_mud/` | Multi-module, sand allocator, cross-module calls, arraylists, structs, unions |
| `examples/lisp_interpreter/` | Sand allocator, pointer arithmetic, expression-switch, ptr.* assignment |
| `examples/func_ptr_return/` | Function pointer types, @ptrCast |
| `examples/quicksort/` | Comparator function pointers, [*]T parameters |
| `examples/sort_strings/` | Multi-level pointers [*][*]const u8 |
| `examples/days_in_month/` | Expression-switch, for range loops |

## 14. Debugging zig0 Issues

### "Unresolved call" in output
Look for: `Unresolved call at LINE:OFF in context 'functionName'`
- Means zig0 can't codegen a function call
- Fix: check import pattern (mod.fn() not fn())
- Fix: if still broken, inline the function body

### Segfault during compilation
- Usually triggered by unsupported pattern
- Bisect by removing functions and recompiling
- Non-standard constructs (ErrorUnion_Slice_u8) are likely triggers

### Mixed stdout (C code + warnings)
- Zig0 puts everything on stdout
- Filter: `./zig0 src/main.zig 2>/dev/null > output.c`
- Or use `grep -v "^src/"` to strip warning lines

### Exit 1 but only warnings
- Look for `error:` in output
- Warnings alone don't cause exit 1
- Exit 1 with warnings only suggests hidden crash/signal

