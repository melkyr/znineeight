# Runtime API Reference

This document describes the runtime functions and types available to Zig programs compiled by the RetroZig bootstrap compiler. These functions are implemented in C89 to ensure compatibility with 1998-era software environments.

## 1. Memory Management (Arena Allocator)

The primary memory management mechanism in RetroZig is the Arena Allocator. It is designed for high performance and low fragmentation.

### 1.1 `Arena` (Type)
An opaque type representing a memory arena. All allocations made from an arena are freed together when the arena is destroyed.

### 1.2 `arena_create`
```zig
fn arena_create(initial_capacity: usize) *Arena
```
Creates a new arena with the specified initial capacity. Returns a pointer to the new arena, or `null` if memory allocation fails.

### 1.3 `arena_alloc`
```zig
fn arena_alloc(a: *Arena, size: usize) *void
```
Allocates `size` bytes from the specified arena. The allocated memory is guaranteed to be 8-byte aligned. If the arena's current block is full, a new block is automatically allocated and linked. This function panics if memory cannot be allocated.

### 1.4 `arena_reset`
```zig
fn arena_reset(a: *Arena) void
```
Resets the arena, making all its memory available for reuse. It does not free the underlying memory blocks back to the OS, allowing for fast reuse of the same memory.

### 1.5 `arena_destroy`
```zig
fn arena_destroy(a: *Arena) void
```
Frees all memory blocks associated with the arena and then destroys the arena itself. Any pointers previously allocated from this arena become invalid.

### 1.6 `zig_default_arena` (Global Variable)
```zig
var zig_default_arena: *Arena
```
A pointer to a default, global arena that is automatically initialized at program startup. This is convenient for simple programs or one-off allocations.

### 1.7 `arena_alloc_default`
```zig
fn arena_alloc_default(size: usize) *void
```
A convenience wrapper that allocates memory from the `zig_default_arena`. Provided primarily for backward compatibility with earlier bootstrap milestones.

## 2. Runtime Safety

### 2.1 `__bootstrap_panic` (Internal)
```c
static void __bootstrap_panic(const char* msg, const char* file, int line)
```
Reports a fatal runtime error and aborts the program. Used for out-of-memory conditions, null pointer dereferences (if checked), and failed numeric casts.

## 3. Usage Examples

### 3.1 Basic Allocation
```zig
// Use the default arena
const ptr = arena_alloc_default(16);
```

### 3.2 Custom Arena Management
```zig
pub fn processFile(filename: []const u8) !void {
    const arena = arena_create(64 * 1024); // 64KB initial
    if (arena == null) return error.OutOfMemory;
    defer arena_destroy(arena);

    // All allocations for this file processing go here
    const buffer = arena_alloc(arena, 4096);
    // ...
}
```
