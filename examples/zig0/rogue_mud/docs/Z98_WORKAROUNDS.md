# Z98 Workarounds for Rogue MUD

This document serves as a quick reference for developers working on the Rogue MUD project using the `zig0` bootstrap compiler.

## Module Naming
Avoid naming modules identically to types.
- ✅ `scenario.zig` (contains `Dungeon_t`)
- ❌ `dungeon.zig` (contains `Dungeon`)

## Return Slices via Out-Params
To avoid the lifetime analyzer's conservative "dangling pointer" check when returning a slice from a struct field, use an out-parameter.
```zig
pub fn getSlice(self: *MyStruct, out: *[]u8) void {
    if (out != null) out.* = self.ptr[0..self.len];
}
```

## Replace Methods with Prefixed Functions
Z98 does not support methods. Use a naming convention like `StructName_FunctionName`.
```zig
pub fn Room_centerX(self: Room_t) u8 { ... }
```

## Explicit Optionals Handling
Avoid the `.?.` chain. Use explicit unwrapping.
```zig
if (node_opt) |node| {
    // use node here
}
```

## Integer Casting
Always use `@intCast(Target, Source)` for integer conversions, even when the target is `usize`.

## Unresolved Call Warnings
If you see "Unresolved call", double-check that all types are imported correctly. If the C code still generates correctly, it may be a transient resolution issue in the bootstrap compiler.
