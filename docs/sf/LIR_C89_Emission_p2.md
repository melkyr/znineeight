# LIR → C89 Emission Design Specification

**Version:** 1.0  
**Component:** C89 code generation, buffered I/O, name mangling, type header emission  
**Parent Document:** `DESIGN.md v3.0` (Sections 8–9, 11–14), `TYPE_SYSTEM.md` (Section 9), `AST_LIR_Lowering.md`  
**Supersedes:** Bootstrap monolithic codegen pass

---

## 0. Scope & Relationship to Pipeline

This document specifies the **LIR → C89 Emission** pass (Pipeline Step 8). It consumes the flattened, optimized LIR produced by Steps 6–7 and emits deterministic, strictly compliant C89 source code. The emitter is purely linear, uses buffered I/O, and never mutates input data structures.

| Input | Source |
|---|---|
| `ArrayList(LirFunction)` | LIR Lowering/Optimization output |
| `TypeRegistry` | Resolved types, layouts, payloads |
| `StringInterner` | Canonical names, mangled C identifiers |
| `CoercionTable` / `ComptimeValueTable` | Resolved constant values (for fallback folding) |
| `NameMangler` | FNV-1a deterministic identifier mapping |
| `DiagnosticCollector` | ICE/OOM/error reporting |

| Output | Consumer |
|---|---|
| `module.c` / `module.h` | C89 compiler (MSVC 6.0, GCC, OpenWatcom) |
| `zig_special_types.h` | Shared type definitions across modules |
| `build_target.{bat,sh}` | Build orchestration |
| `zig_runtime.{h,c}` | Arena, panic, checked conversions (statically linked) |

**Key Invariant:** The emitter performs **zero analysis**. All type resolution, control-flow lifting, defer expansion, and coercion decisions are finalized in the LIR. Emission is a deterministic string-generation walk over basic blocks.

---

## 1. Emitter Architecture & State Management

The emitter is encapsulated in a single stateful struct that tracks indentation, buffered I/O, and temporary emission caches.

```zig
pub const C89Emitter = struct {
    writer: *BufferedWriter,
    indent: u32,
    reg: *TypeRegistry,
    interner: *StringInterner,
    mangler: *NameMangler,
    diag: *DiagnosticCollector,
    
    // Per-function emission caches (scratch arena-backed)
    func: *LirFunction,
    block_labels: ArrayList(u32),      // bb_id → label string_id
    switch_cases: *ArrayList(SwitchCase),
    call_args: ArrayList(u32),         // scratch for call argument emission
    pending_labels: ArrayList(u32),    // blocks needing label emission
};

pub const BufferedWriter = struct {
    buf: [4096]u8,
    pos: usize,
    file: *FileHandle,  // abstracted OS file handle or memory buffer
    alloc: *Allocator,
};
```

**Memory Strategy:**
- `permanent` arena: `NameMangler` caches, `zig_special_types.h` type graph, global string interner.
- `module` arena: `C89Emitter` struct, `BufferedWriter`, per-function caches.
- `scratch` arena: `call_args`, `pending_labels`, temporary formatting buffers. Reset per function.
- **No recursion:** All emission uses explicit iteration over `func.blocks` and `block.insts`.

---

## 2. C89 Output Generation Strategy

Emission follows a strict two-phase order to satisfy C89 forward-declaration requirements and deterministic output:

### 2.1 Phase 1: Type Headers

1. Emit `zig_special_types.h` containing all slice, optional, error-union, and tagged-union typedefs required by public signatures.
2. Emit `module.h` containing:
   - Public function prototypes (mangled names).
   - `extern` variable declarations.
   - Public type aliases (`typedef struct zS_Node zS_Node;`).
3. Types are emitted in **topological dependency order** (primitives → compound → public signatures). Self-referential types use forward declarations.

### 2.2 Phase 2: Function Bodies

1. Iterate functions in source-declaration order.
2. For each function:
   - Emit signature with mangled name.
   - Emit hoisted `decl_temp`/`decl_local` declarations at block top.
   - Iterate `BasicBlock` in ID order. Emit label (if non-entry), then instructions.
   - Emit terminators (`goto`, `if`, `return`).
3. Flush buffer, write trailing `/* EOF */` comment.

### 2.3 Determinism Guarantees

- Block IDs are sequential (`0..N`). Label names are derived from BB ID: `z_bb_0:`.
- Switch cases emitted in `cases_start..cases_start+cases_count` order.
- No hash-iteration leakage; all maps use stable open-addressing with deterministic seed (FNV-1a with fixed seed).
- Temporary IDs are sequential within function.
- No pointer addresses leaked into output.

---

## 3. Type Emission (`zig_special_types.h`)

### 3.1 Topological Sorting of Type Dependencies

The type registry already contains a dependency graph from Pass 4. The emitter uses Kahn's algorithm again to emit types in an order that satisfies C89's "declare before use" rule.

```zig
fn emitSpecialTypes(emitter: *C89Emitter, reg: *TypeRegistry) !void {
    var sorted = try topologicalSortTypes(reg, emitter.alloc);
    for (sorted) |tid| {
        const ty = reg.types.items[tid];
        if (ty.kind == .void_type or ty.kind == .bool_type or ty.kind == .noreturn_type) continue; // primitives
        if (ty.name_id == 0) continue; // anonymous types handled inline
        try emitter.emitTypeDefinition(tid);
    }
}
```

### 3.2 Exact C89 Struct Layouts

| Z98 Type | C89 Equivalent | Emission Notes |
|---|---|---|
| `[]T` | `typedef struct { T* ptr; unsigned int len; } zS_Slice_T;` | Generic per `T` mangled name |
| `?T` | `typedef struct { T value; int has_value; } zS_Opt_T;` | `has_value` is `int` (C89 `bool` via macro) |
| `!T` | `typedef struct { union { T payload; int err; } data; int is_error; } zS_EU_T;` | `is_error` tracks success/failure |
| `!void` | `typedef struct { int err; int is_error; } zS_EU_void;` | No payload union member |
| `union(enum)` | `typedef struct { int tag; union { ... } payload; } zS_TU_Name;` | Tag is `int` (backing enum) |
| `union` (bare) | `typedef union { ... } zS_U_Name;` | Standard C union |
| `enum(T)` | `typedef T E_Name; #define E_Name_Member N` | Backing type + preprocessor constants |
| Empty struct/union | `typedef struct { char _dummy; } zS_Empty;` | C89 forbids empty aggregates |

### 3.3 Forward Declaration Logic

```zig
// Example: self-referential struct via pointer
fn emitStructForwardDecl(emitter: *C89Emitter, name_id: u32) !void {
    const c_name = emitter.mangleTypeName(name_id);
    try emitter.writer.writeFmt("typedef struct %s %s;\n", c_name, c_name);
}
```

Then emit full definition later.

### 3.4 `zig_compat.h` Bootstrap Layer

This file is generated once per compilation and included at the top of every `.c` file.

```c
/* zig_compat.h - C89 compatibility layer */
#ifndef ZIG_COMPAT_H
#define ZIG_COMPAT_H

/* 64-bit integers */
#if defined(_MSC_VER) && _MSC_VER <= 1200
  typedef __int64 z64;
  typedef unsigned __int64 zu64;
#elif defined(__WATCOMC__)
  typedef __int64 z64;
  typedef unsigned __int64 zu64;
#else
  typedef long long z64;
  typedef unsigned long long zu64;
#endif

/* Boolean */
#ifndef bool
  typedef int bool;
  #define true 1
  #define false 0
#endif

/* Null pointer */
#ifndef NULL
  #define NULL ((void*)0)
#endif

#endif
```

---

## 4. Function Body Emission

Each `LirFunction` is emitted as a standalone C89 function.

### 4.1 Signature Generation

```zig
fn emitFunctionSignature(self: *C89Emitter, fn: *LirFunction) !void {
    const ret_c = self.resolveCType(fn.return_type);
    const mangled = self.mangleName(fn.name_id);
    // Optional comment with original name
    const original = self.interner.get(fn.name_id);
    try self.writer.writeFmt("/* %s */\n%s %s(", original, ret_c, mangled);
    
    var i: usize = 0;
    while (i < fn.params.len) : (i += 1) {
        if (i > 0) try self.writer.write(", ");
        const p = fn.params.items[i];
        try self.writer.writeFmt("%s %s", self.resolveCType(p.type_id), self.mangleLocalName(p.name_id));
    }
    if (fn.params.len == 0) try self.writer.write("void");
    try self.writer.write(") {\n");
    self.indent += 1;
}
```

### 4.2 Hoisted Declaration Emission

C89 requires all declarations at the top of the block. The LIR lowerer already hoisted them; the emitter just prints them in declaration order.

```zig
fn emitHoistedDecls(self: *C89Emitter, fn: *LirFunction) !void {
    var i: usize = 0;
    while (i < fn.hoisted_temps.len) : (i += 1) {
        const t = fn.hoisted_temps.items[i];
        const c_type = self.resolveCType(t.type_id);
        try self.writer.writeIndent(self.indent);
        try self.writer.writeFmt("%s %s;\n", c_type, self.mangleTempName(t.temp_id));
    }
}
```

### 4.3 Block & Instruction Emission Loop

Blocks are emitted in sequential ID order. Jump targets use C89 labels (`z_bb_N:`).

```zig
fn emitFunctionBody(self: *C89Emitter, fn: *LirFunction) !void {
    var bb_idx: usize = 0;
    while (bb_idx < fn.blocks.len) : (bb_idx += 1) {
        const bb = &fn.blocks.items[bb_idx];
        
        // Emit label for non-entry blocks
        if (bb.id > 0) {
            try self.writer.writeIndent(self.indent);
            try self.writer.writeFmt("z_bb_%d:\n", bb.id);
        }
        
        // Emit instructions
        var inst_idx: usize = 0;
        while (inst_idx < bb.insts.len) : (inst_idx += 1) {
            try self.emitInst(bb.insts.items[inst_idx]);
        }
        
        // Terminator already emitted as part of the last instruction in the block.
        // LIR guarantees every block ends with a terminator (jump, branch, ret, switch_br).
    }
    self.indent -= 1;
    try self.writer.write("}\n\n");
}
```

---

## 5. Instruction Mapping (LIR → C89)

All LIR instructions follow three-address form or explicit control-flow. Mapping is direct and stateless.

### 5.1 Basic Instructions

| LIR Instruction | C89 Output Pattern |
|---|---|
| `decl_temp` | Handled in hoisting phase; not emitted inline |
| `assign` | `%s = %s;` |
| `assign_field` | `%s.%s = %s;` |
| `assign_index` | `%s[%s] = %s;` |
| `binary` | `%s = %s %s %s;` (operator mapping: `+`, `-`, `*`, `/`, `%%`, `&`, `|`, `^`, `<<`, `>>`, `&&`, `||`) |
| `unary` | `%s = %s%s;` (prefix: `-`, `!`, `~`) |
| `load_local` / `store_local` | `%s = %s;` / `%s = %s;` |
| `load_global` / `store_global` | `%s = %s;` / `%s = %s;` |
| `load_field` / `store_field` | `%s = %s.%s;` / `%s.%s = %s;` |
| `load_index` / `store_index` | `%s = %s[%s];` / `%s[%s] = %s;` |
| `load` / `store` | `%s = *%s;` / `*%s = %s;` |
| `addr_of` | `%s = &%s;` |
| `jump` | `goto z_bb_%d;` |
| `branch` | `if (%s) goto z_bb_%d; else goto z_bb_%d;` |
| `ret` | `return %s;` |
| `ret_void` | `return;` |
| `nop` | (omitted) |

### 5.2 Switch Branch Emission

`switch_br` uses an external `cases` array. Emitter generates a C89 `switch` statement for performance on 1998-era hardware.

```zig
fn emitSwitch(self: *C89Emitter, cond_temp: u32, cases: []const SwitchCase, else_bb: u32) !void {
    const c_cond = self.resolveTemp(cond_temp);
    try self.writer.writeIndent(self.indent);
    try self.writer.writeFmt("switch (%s) {\n", c_cond);
    self.indent += 1;
    
    var i: usize = 0;
    while (i < cases.len) : (i += 1) {
        const c = cases[i];
        try self.writer.writeIndent(self.indent);
        try self.writer.writeFmt("case %d: goto z_bb_%d;\n", c.value, c.target_bb);
    }
    
    try self.writer.writeIndent(self.indent);
    try self.writer.writeFmt("default: goto z_bb_%d;\n", else_bb);
    self.indent -= 1;
    try self.writer.writeIndent(self.indent);
    try self.writer.write("}\n");
}
```

### 5.3 Coercion & Cast Emission

Coercions are explicit LIR instructions. Emitter outputs C casts or helper calls.

```zig
fn emitCoercion(self: *C89Emitter, inst: LirInst) !void {
    return switch (inst) {
        .int_cast => |c| {
            const tgt = self.resolveCType(c.target);
            const src = self.resolveTemp(c.value);
            const dst = self.resolveTemp(c.result);
            if (c.is_checked) {
                // Runtime checked conversion helper
                try self.writer.writeFmt("%s = __bootstrap_checked_cast_%s(%s);\n", dst, tgt, src);
            } else {
                try self.writer.writeFmt("%s = (%s)%s;\n", dst, tgt, src);
            }
        },
        .wrap_optional => |w| {
            const dst = self.resolveTemp(w.result);
            const src = self.resolveTemp(w.value);
            try self.writer.writeFmt("%s.has_value = 1;\n", dst);
            try self.writer.writeFmt("%s.value = %s;\n", dst, src);
        },
        .make_slice => |s| {
            const dst = self.resolveTemp(s.result);
            const ptr = self.resolveTemp(s.ptr);
            const len = self.resolveTemp(s.len);
            try self.writer.writeFmt("%s.ptr = %s;\n", dst, ptr);
            try self.writer.writeFmt("%s.len = %s;\n", dst, len);
        },
        .wrap_error_ok => |w| {
            const dst = self.resolveTemp(w.result);
            const src = self.resolveTemp(w.value);
            try self.writer.writeFmt("%s.data.payload = %s;\n", dst, src);
            try self.writer.writeFmt("%s.is_error = 0;\n", dst);
        },
        .wrap_error_err => |w| {
            const dst = self.resolveTemp(w.result);
            const err = self.resolveTemp(w.value);
            try self.writer.writeFmt("%s.data.err = %s;\n", dst, err);
            try self.writer.writeFmt("%s.is_error = 1;\n", dst);
        },
        // ... other coercions similarly
        else => {},
    };
}
```

### 5.4 `std.debug.print` Intrinsic Emission

Lowered to `print_str` and `print_val` LIR instructions. Emitter maps them to bootstrap runtime helpers.

```zig
fn emitPrint(self: *C89Emitter, inst: LirInst) !void {
    return switch (inst) {
        .print_str => |p| {
            const str = self.escapeCString(self.interner.get(p.string_id));
            try self.writer.writeFmt("__bootstrap_print(\"%s\");\n", str);
        },
        .print_val => |p| {
            const helper = self.resolvePrintHelper(p.type_id, p.fmt);
            try self.writer.writeFmt("%s(%s);\n", helper, self.resolveTemp(p.value));
        },
        else => {},
    };
}
```

**Print Helper Mapping:**

| Z98 Type | Format | Helper Function |
|---|---|---|
| `i32`, `u32` | `d`, `x` | `__bootstrap_print_int` |
| `i64`, `u64` | `d`, `x` | `__bootstrap_print_int64` |
| `[]const u8` | `s` | `__bootstrap_print_str` |
| `bool` | (default) | `__bootstrap_print_bool` |
| `u8` | `c` | `__bootstrap_print_char` |

---

## 6. Name Mangling & Identifier Management

Deterministic FNV-1a-based mangling ensures C89 compatibility and cross-module stability.

### 6.1 Mangling Rules

1. **Temporaries & Builtins:** `__tmp_N`, `__ret_`, `__bootstrap_*` → **no mangling**.
2. **User Identifiers:** `z<Kind>_<Hash8>_<Name>`
   - `<Kind>`: `F` (function), `G` (global), `T` (type), `L` (local/param)
   - `<Hash8>`: Lower 8 hex chars of FNV-1a hash of `(module_path + name)`
   - `<Name>`: Original identifier, truncated to fit 31-char C89 limit
3. **C89 Keywords:** Prefixed with `z_` (e.g., `switch` → `z_switch`, `extern` → `z_extern`)
4. **Extern Symbols:** Verbatim (no mangling, no prefixing)
5. **Global Uniqueness:** Hash includes module path. Collision resolution via `_<counter>` (rare).

### 6.2 Implementation

```zig
pub const NameMangler = struct {
    hash_seed: u32,
    cache: U64ToU32Map,  // key = (module_id << 32) | name_id → interned mangled string_id
    keyword_set: HashSet(u32),
    interner: *StringInterner,

    pub fn mangle(self: *NameMangler, name_id: u32, kind: u8, module_id: u32) !u32 {
        const name = self.interner.get(name_id);
        if (self.isTempOrBuiltin(name)) return name_id;
        if (self.isC89Keyword(name)) return self.mangleC89Keyword(name);
        
        const key = (@intCast(u64, module_id) << 32) | name_id;
        if (self.cache.get(key)) |cached| return cached;
        
        const hash = self.fnv1a(name);
        const kind_char = switch (kind) { 0 => 'F', 1 => 'G', 2 => 'T', else => 'L' };
        var buf: [32]u8 = undefined;
        var pos: usize = 0;
        // Manual formatting to avoid Z98 fmtBuf limitations
        pos = writeStr(&buf, pos, "z");
        buf[pos] = kind_char; pos += 1;
        buf[pos] = '_'; pos += 1;
        pos = writeHex(&buf, pos, hash & 0xFFFFFFFF);
        buf[pos] = '_'; pos += 1;
        pos = writeStr(&buf, pos, name);
        // Truncate to 31 chars if needed
        if (pos > 31) pos = 31;
        
        const mangled_id = self.interner.intern(buf[0..pos]);
        try self.cache.put(key, mangled_id);
        return mangled_id;
    }
};
```

**Z98 Note:** The formatting functions `writeStr` and `writeHex` are simple loops writing to a byte buffer; no `fmtBuf` required.

---

## 7. Global Constant Pools

String literals and floating-point constants are stored in global pools to avoid duplication and ensure C89 compatibility (no compound literals).

### 7.1 String Literal Pool

```c
/* In module.c */
static const char z_str_0[] = "Hello, world!\n";
static const char z_str_1[] = "x = ";
```

The LIR `string_const` instruction references the pool index; the emitter emits `z_str_N`.

### 7.2 Float Constant Pool

Floating-point constants that cannot be expressed as simple literals (e.g., `3.1415926535`) are emitted as static `const double` variables to avoid precision loss across compilers.

```c
static const double z_float_0 = 3.1415926535;
```

---

## 8. Z98 Constraints & C89 Compliance Guarantees

| Constraint | Enforcement in Emitter |
|---|---|
| **C89 Strict Mode** | No `//` comments, no `inline`, no compound literals `(T){}`, no trailing commas in initializers |
| **Declarations First** | All `decl_temp`/`decl_local` emitted before any executable statement in each function |
| **`__int64` for 64-bit** | `i64`/`u64` map to `__int64`/`unsigned __int64` via `zig_compat.h` |
| **`bool` Emulation** | `bool` maps to `int`; `true`/`false` via `#define` |
| **Void Pointer Arithmetic** | `(*char)(ptr) + offset` emitted when casting `*void` or performing byte offsets |
| **Empty Aggregates** | `char _dummy;` injected in struct/union emission if field count == 0 |
| **Identifier Length** | All mangled names truncated to 31 characters before interning |
| **Deterministic Output** | Stable iteration order, seeded hashing, no address/pointer leakage, sequential BB/Temp IDs |
| **<16 MB Peak RAM** | 4KB buffered I/O, scratch arena reset per function, no unbounded string concatenation |

### 8.1 C89 Compliance Checklist

| C89 Restriction | Z98 Workaround in Emitter |
|---|---|
| No `//` comments | All emitter comments use `/* ... */` |
| No compound literals | Struct/array initialization decomposed to field/index assignments |
| Declarations must precede code | LIR hoisting guarantees `decl_*` appear first |
| No `inline` | Slice/optional helpers emitted as `static` functions (no inline) |
| `bool` not standard | `typedef int bool; #define true 1 #define false 0` in `zig_compat.h` |
| `__int64` non-standard | Detected via `_MSC_VER` / compiler macros, mapped in compat header |
| Identifier limit: 31 chars | Mangler truncates, preserves uniqueness via hash prefix |
| Empty struct/union illegal | Dummy `char _dummy;` field injected automatically |
| Trailing comma in initializers | Emitter omits comma after last field/argument |
| Void pointer arithmetic | Explicit cast to `unsigned char*` before adding offset |
| No mixed declarations and code | All declarations hoisted to function prologue |

---

## 9. Buffering & I/O Strategy

The `BufferedWriter` minimizes syscalls and guarantees deterministic byte output.

```zig
pub const BufferedWriter = struct {
    buf: [4096]u8,
    pos: usize,
    file: *FileHandle,
    alloc: *Allocator,

    pub fn write(self: *BufferedWriter, data: []const u8) !void {
        var remaining = data;
        while (remaining.len > 0) {
            const space = self.buf.len - self.pos;
            const copy_len = if (remaining.len < space) remaining.len else space;
            // Manual copy loop (Z98 may not have @memcpy)
            var i: usize = 0;
            while (i < copy_len) : (i += 1) {
                self.buf[self.pos + i] = remaining[i];
            }
            self.pos += copy_len;
            remaining = remaining[copy_len..];
            if (self.pos == self.buf.len) try self.flush();
        }
    }

    pub fn writeIndent(self: *BufferedWriter, level: u32) !void {
        var i: u32 = 0;
        while (i < level * 4) : (i += 1) {
            if (self.pos == self.buf.len) try self.flush();
            self.buf[self.pos] = ' ';
            self.pos += 1;
        }
    }

    pub fn flush(self: *BufferedWriter) !void {
        if (self.pos == 0) return;
        // Platform abstraction layer call
        try pal.file_write(self.file, self.buf[0..self.pos]);
        self.pos = 0;
    }
};
```

**Indentation:** Spaces are used instead of tabs for C89 portability across 1998-era editors.

**Line Ending:** Always `\n`. CRLF conversion handled by target platform toolchain if needed.

---

## 10. Error Handling & Diagnostics

The emitter reports only fatal errors (ICE, OOM). No semantic errors occur at this stage.

| Condition | Diagnostic |
|---|---|
| Type not resolved | ICE: "unresolved type in emission" |
| Missing C name for type | ICE: "type lacks C name" |
| Mangled name collision | ICE: "hash collision in name mangling" |
| Buffer write failure | Propagates OS error via PAL |

---

## 11. Testing & Validation

| Test Layer | Input | Verified Property |
|---|---|---|
| **Unit: Type Emission** | `[]T`, `?T`, `!T`, `union(enum)` | Correct C89 struct/typedef layout, forward decl order |
| **Unit: Instruction Mapping** | `binary`, `assign_field`, `wrap_optional` | Exact C syntax, correct mangling, cast placement |
| **Unit: Switch/Control Flow** | Nested `switch_br`, `branch`, `loop_header` | Correct `goto` targets, no dead labels, C89 `switch` syntax |
| **Integration: `--dump-c89`** | `eval.zig`, `mud.zig` | Byte-identical output across runs |
| **C89 Compilation Gate** | Generated `.c` files | `gcc -std=c89 -pedantic -Wall -Werror`, `cl /Za /W3`, `wcc386 -za` all pass |
| **Memory Gate** | `zig1.zig` compilation | Peak `scratch` + `permanent` + I/O buffers < 16 MB |
| **Differential vs `zig0`** | Reference programs | Generated C89 matches `zig0` output (allowing stable comment/hash differences) |

### 11.1 Differential Testing Script

```bash
#!/bin/sh
# test_emitter.sh
zig0 --emit-c89 test.zig -o test_zig0.c
zig1 --emit-c89 test.zig -o test_zig1.c
diff -u test_zig0.c test_zig1.c | grep -v '^+++' | grep -v '^---'
```

---

## 12. Extensibility & Future Backends

The architecture is explicitly backend-agnostic:

| Feature | Extension Point |
|---|---|
| **New Backend (LLVM/x86)** | Replace `C89Emitter` with `LlvmEmitter` or `X86Emitter`. Same `fn emit(func: *LirFunction)` interface |
| **Parallel Module Emission** | Each worker thread gets independent `C89Emitter` + `BufferedWriter`. `permanent` arena is read-only during emission |
| **Advanced Optimization** | LIR optimization (Step 7) runs before emission. Emitter sees only canonical three-address code |
| **C99/C11 Target** | Swap `zig_compat.h`, enable compound literals, allow declarations mid-block, replace `__int64` with `long long` |
| **Debug Info** | Emit `#line` directives mapping `span_start`/`span_end` to C source. Compatible with MSVC/GDB |

---

## Appendix A: LIR → C89 Instruction Mapping Table (Complete)

| LIR Variant | C89 Emission | Special Handling |
|---|---|---|
| `decl_temp` | `T temp_N;` | Hoisted to function prologue |
| `assign` | `dst = src;` | Direct |
| `assign_field` | `base.f = src;` | Field ID → C member name |
| `assign_index` | `base[idx] = src;` | Direct |
| `jump` | `goto z_bb_N;` | Direct |
| `branch` | `if (cond) goto z_bb_T; else goto z_bb_E;` | Direct |
| `switch_br` | `switch(cond) { case V: goto ... }` | Uses external `cases` array |
| `loop_header` | `z_bb_N:` | Marker only |
| `ret` | `return val;` | Direct |
| `ret_void` | `return;` | Direct |
| `binary` | `res = lhs OP rhs;` | Operator mapping exact |
| `unary` | `res = OP op;` | Direct |
| `call` | `res = callee(arg1, arg2);` | Mangling for callee |
| `load_field`/`store_field` | `res = base.f;` / `base.f = val;` | Direct |
| `load_index`/`store_index` | `res = base[i];` / `base[i] = val;` | Direct |
| `load`/`store` | `res = *ptr;` / `*ptr = val;` | Direct |
| `addr_of` | `res = &operand;` | Direct |
| `wrap_optional` | `res.has_value = 1; res.value = val;` | Struct field assignment |
| `check_optional` | `res = val.has_value;` | Flag extraction |
| `make_slice` | `res.ptr = p; res.len = l;` | Struct construction |
| `int_cast` | `res = (T)val;` or `__bootstrap_checked_cast...` | Checked vs unchecked |
| `print_str` | `__bootstrap_print("...");` | Intrinsic |
| `print_val` | `__bootstrap_print_X(val);` | Type-specific helper |
| `nop` | *(omitted)* | DCE placeholder |

---

## Appendix B: Runtime Helpers (`zig_runtime.c`)

The emitter relies on a small set of runtime functions provided by `zig_runtime.c` (compiled once and linked statically).

| Helper | Purpose |
|---|---|
| `__bootstrap_panic(msg)` | Called on unreachable or failed assertion |
| `__bootstrap_checked_cast_i32(u64)` | Runtime bounds-checked cast to i32 |
| `__bootstrap_checked_cast_u32(u64)` | Runtime bounds-checked cast to u32 |
| `__bootstrap_print(str)` | Write zero-terminated string to stdout |
| `__bootstrap_print_int(i32)` | Print signed integer |
| `__bootstrap_print_int64(z64)` | Print 64-bit integer |
| `__bootstrap_print_hex(u32)` | Print hex |
| `__bootstrap_print_str(struct { char* ptr; unsigned int len; })` | Print slice |
| `__bootstrap_print_bool(int)` | Print "true" or "false" |
| `__bootstrap_print_char(char)` | Print single character |

---

## Appendix C: Core Emission Loop (Pseudocode)

```zig
pub fn emitModule(self: *C89Emitter, module: *LirModule) !void {
    try self.emitHeaderIncludes();
    try self.emitSpecialTypes();      // Phase 1
    try self.emitModuleHeader();      // Phase 1
    
    var i: usize = 0;
    while (i < module.functions.len) : (i += 1) {
        const func = module.functions.items[i];
        if (!func.is_extern) {
            try self.emitFunctionSignature(func);
            try self.emitHoistedDecls(func);
            try self.emitFunctionBody(func);
            try self.writer.flush();
        }
    }
    
    try self.emitModuleFooter();
}
```

This pass is the final transformation before C89 compilation. It is strictly linear, deterministic, and enforces every Z98 constraint while producing clean, portable C89 output compatible with 1998-era toolchains.
