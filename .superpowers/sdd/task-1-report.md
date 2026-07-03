# Task 1 Report: Create `sf/src/extern_c.zig` — Consolidate extern fns

**Status:** COMPLETE
**Commit:** `e3a43f26` refactor: consolidate extern fn into sf/src/extern_c.zig

## What was done

1. **Created `sf/src/extern_c.zig`** with the three consolidated declarations:
   ```zig
   pub extern fn write(fd: i32, buf: [*]const u8, count: i32) i32;
   pub extern fn __bootstrap_print(s: [*]const u8) void;
   pub extern fn __bootstrap_print_int(n: i32) void;
   ```

2. **`sf/src/pal.zig`** — replaced the bare `extern fn write` (line 4) with
   `const ext_c = @import("extern_c.zig");`. Updated both call sites in
   `stdout_write`/`stderr_write` to `ext_c.write(...)`. The `extern "c"` fopen/
   fread/fclose/fseek/ftell/c_exit declarations were **left in place** — the
   brief only scoped `write`, `__bootstrap_print`, `__bootstrap_print_int` into
   `extern_c.zig`.

3. **`sf/src/main_exp.zig`** — replaced lines 1-2 with the import; call sites
   now `ext_c.__bootstrap_print(...)` / `ext_c.__bootstrap_print_int(...)`.

4. **`sf/src/test_a.zig`** — replaced line 1 with the import; call site now
   `ext_c.__bootstrap_print("hello")`.

## Deviation from brief (IMPORTANT LEARNING)

The brief suggested adding `const write = ext_c.write;` alias to keep pal.zig
call sites unchanged. **This does NOT work with zig0.** The alias caused zig0
to emit a mangled *constant* symbol at the call sites
(`zC_29c0b880_2910d0f5_write(...)`) while the `pub extern fn` declaration in
extern_c.c kept the unmangled C name (`extern int write(...)`). Result:
```
pal.c: undefined reference to `zC_29c0b880_2910d0f5_write'
collect2: error: ld returned 1 exit status
```
**Fix:** call `ext_c.write(...)` directly (no alias). zig0 then correctly emits
the unmangled `write(...)` at the call site, matching the extern declaration.

Verified generated C:
- `extern_c.c:13: extern int write(int fd, unsigned char const* buf, int count);`
- `pal.c:186: (void)(write(1, msg.ptr, ...));`  (unmangled, consistent)

## Gate check

Exact gate command output: `3` (zig0), `0` (gcc).

- **gcc: 0 errors** — clean, zig1 binary produced (684692 bytes).
- **zig0: 3 "error:" matches are FALSE POSITIVES** — two `[AST_UTILS] Warning:
  NULL symbol ... at kw_error:656:49` lines and one source line containing
  `s_error`, all matched by the substring `error:`. Verified identical count
  (`3`) on the unmodified baseline via `git stash`, so they are pre-existing
  and unrelated to this change. **zig0 real error count = 0.**

## Files changed
- `sf/src/extern_c.zig` (new, 3 lines)
- `sf/src/pal.zig` (import + 2 call sites)
- `sf/src/main_exp.zig` (import + 2 call sites)
- `sf/src/test_a.zig` (import + 1 call site)

## Concerns
- None blocking. Note for future tasks: **do not use `const x = ext_mod.extern_fn;`
  aliases** — zig0 mangles the alias into a `zC_` constant symbol that won't link
  against the unmangled extern declaration. Reference extern fns via the module
  prefix directly (`ext_c.write(...)`).
