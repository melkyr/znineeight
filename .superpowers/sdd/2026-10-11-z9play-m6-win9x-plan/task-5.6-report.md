# T5.6 Report — Other-architecture support exploration (report only)

**Status:** DONE_WITH_CONCERNS

## Scope

Report-only task per plan Amendment 2 (f) and T5.6. No source, test, runtime,
or build changes. Deliverables:

- `sf/docs/tech_docs/Other_arch_supp.md`
- `sf/docs/tech_docs/INDEX.md` row
- this report

No push. `run.err`/`run.out`/`progress.md` untouched.

## Method

1. Read the T5.6 brief and the plan's Amendment 2 T5.6 text.
2. Traced the current execution model and every frozen 32-bit assumption to
   `file:line` in `sf/src`: `zig_compat.h`, `type_registry.zig`,
   `type_resolver.zig`, `lower.zig`, `c89_emit.zig`, `main.zig`,
   `allocator.zig`, `std_file*.zig`, `std_os*.zig`, `std_time*.zig`,
   `std_net.zig`, `async_*`, `std_async.zig`, `scripts/seed/*`.
3. Checked the existing Windows/no-CRT docs (`10_c_runtime.md`,
   `12_async_coroutines.md`, `13_windows_support.md`) to avoid duplicating
   established facts.
4. Researched external ABI/toolchain/syscall documentation for the non-repo
   claims: Arm AAPCS32, RISC-V psABI/CC, x86-64 System V psABI, Linux ARM and
   generic syscall tables, GCC extended asm, OpenWatcom C guide.
5. Wrote the doc with per-target C89 adequacy, model fit, PAL/ABI work,
   blockers, required compiler features, inline-asm analysis, targeting vs
   self-hosting, performance limiters, phasing, risks, and a file-level change
   list.

No code was compiled, no benchmarks were run, and no target hardware was used.
All performance statements are qualitative and labeled as such.

## Key conclusions

- The current compiler is a **32-bit semantic machine** regardless of the host
  C compiler: `usize`/`isize` are 4 bytes
  (`sf/src/type_registry.zig:1146-1147`), pointers are 4 bytes
  (`:750-753`, `:772-775`), slices are 8 bytes
  (`:800`), `va_list` is 4 bytes (`:1155`), optional/error-union layout uses
  4-byte steps (`sf/src/type_resolver.zig:365-377`), and `@intToPtr` casts
  through `(unsigned int)` (`sf/src/c89_emit.zig:3597-3603`).
- **AArch32/ARMv7 and RV32 are the real low-cost targets.** Their ILP32 data
  model matches the current model. The work is primarily PAL/syscall/stat
  layouts, `char` signedness, and build recipes, not a type-system change.
  ARM `_llseek` is 140 (same constant); RISC-V uses generic `_llseek` 62;
  x86-64/AArch64 use `lseek`.
- **AArch64, RV64, and x86-64 are blocked by the width/layout model**, not by
  C89. Slices must become 16 bytes, `usize`/pointers must become 8 bytes,
  optional/error-union tags and alignment must scale, `va_list` must use the
  target ABI, and pointer casts must stop truncating.
- **16-bit DOS/8086/286 is not viable as a simple extension.** 16-bit `int`,
  segmented pointers, 64 KiB objects, the 16 MB budget, and the 256 MiB static
  pool make it a different backend. 32-bit protected-mode DOS with a DOS
  extender is a separate, more plausible target.
- **Inline asm is genuinely required only for bare-metal startup/syscalls and
  CPU/atomic probes.** For Linux/Android/Windows, C helpers and existing PAL
  code suffice. The recommended path is to keep asm in C support files, not
  add a Z98 `asm` language feature first.
- **Targeting and self-hosting are different.** Cross-emission needs the target
  descriptor + PAL + build recipe (and the width model for 64-bit).
  Self-hosting additionally needs the compiler's host PAL, a target C compiler,
  a target-specific seed/fixed point, and enough memory. 32-bit ARM/RV32 is
  the easiest self-host; 64-bit self-host is blocked until the compiler's own
  type model is width-parameterized.
- **Performance:** the current emitted build scripts use `-O0`
  (`sf/src/c89_emit.zig:8556`, `:8560-8565`), and the seed build is `-O0`
  (`scripts/seed/build_from_seed.sh:91-102`). Optimization flags are the
  largest immediate lever; architecture choice is secondary. No benchmark
  claims are made.

## Concerns

1. **No target verification.** No cross compiler, qemu target, or hardware was
   used. The report is design/research-level; PAL and ABI claims (especially
   `struct stat`/`timeval` offsets) are marked unverified and must be probed.
2. **The 64-bit layout change is wide and risky.** It touches type
   registry/layout, lowering, comptime folding, async frame layout, C emission,
   `@sizeOf`, and goldens. Doing it piecemeal risks silent layout corruption.
   The doc recommends treating it as one phase with layout probes.
3. **The 16 MB budget vs 256 MiB static pool is a real self-host constraint.**
   The pool is a static BSS array (`sf/src/allocator.zig:247-248`); the 16 MB
   figure is an allocation budget, not the image size. Bare-metal/16-bit
   self-host is not plausible without changing the allocator.
4. **Seed/fixed-point portability.** The committed seed and build recipe are
   x86-32 (`scripts/seed/build_from_seed.sh:18-29`, `:91-102`). The md5 fixed
   point is not portable across architectures/compilers; each self-host target
   needs its own recorded closure.
5. **`char` signedness.** Z98 treats `c_char` as signed
   (`sf/src/type_registry.zig:1276`); ARM and RISC-V C `char` is unsigned.
   This is a small but real ABI/semantics audit item for AArch32/RV32.
6. **No implementation is authorized by this task.** The plan is a report; any
   follow-up phase needs a new plan/task and the usual compiler gates.

## Gates

- Review only: report quality, honesty, coverage, no emulation framing,
  INDEX row present, zero code changes. Satisfied by inspection.
- No source/test/build changes were made. The only edits are the doc, the
  INDEX row, and this report.
