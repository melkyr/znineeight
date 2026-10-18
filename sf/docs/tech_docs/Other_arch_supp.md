# Other-architecture support exploration [2026-10-18 — M6 T5.6, report only]

> Scope: what it would take to generate native code for architectures other than
> 32-bit x86, using the existing Z98-to-C89 path, and separately what it would
> take to self-host the compiler there. This is research, not a compatibility
> claim. No emulation path is considered: the question is what real compiler,
> ABI, runtime, and toolchain work is required.
>
> Method: repo facts are cited as `file:line`; non-repo claims cite public ABI,
> toolchain, or kernel documentation. Anything not verified in this repository
> or by a local build is marked **[unverified]**. No benchmarks were run and no
> performance numbers are asserted.

## 1. Execution model recap and frozen assumptions

### 1.1 Pipeline

Z98 source is consumed by `zig1`, which is itself written in Z98. The compiler
emits per-module C89 plus a fixed runtime/support set, and a host C toolchain
turns that C into a native binary:

```
Z98 source --zig1--> C89 (.c/.h + zig_runtime/zig_pal/c_exit/...) --host CC--> native executable
```

The compiler is bootstrapped from `release/seed/zig1-seed.tgz`: the seed compiler
emits the current `sf/src`, gcc compiles it, and the result must close a
two-hop fixed point (`scripts/seed/build_from_seed.sh:18-29`,
`scripts/seed/build_from_seed.sh:150-168`). Both the seed recipe and the
developer build use `gcc -m32`
(`scripts/seed/build_from_seed.sh:91-102`, `docs/sf/AGENTS.md:458`).

There is currently **no architecture target**. The CLI selects only an OS
target (`-osl` / `-osw`, `--target linux|windows`) and a Windows profile
(`sf/src/main.zig:1810-1831`, `sf/src/main.zig:2009-2019`). The architecture is
whatever the host/cross C compiler produces. The emitted build scripts know only
`linux` and `mingw`, both with `-m32`
(`sf/src/c89_emit.zig:8556-8565`, `sf/src/c89_emit.zig:8769-8795`).

### 1.2 Frozen 32-bit semantic model

These are the assumptions a port must confront. They are not incidental:
they are spread across the type registry, layout math, lowering, C emission,
runtime, and the self-host recipe.

| Assumption | Evidence |
|:--|:--|
| `usize` and `isize` are 4 bytes, align 4 | `sf/src/type_registry.zig:1146-1147` |
| `usize`/`isize` C spelling is `unsigned int` / `int` | `sf/src/type_registry.zig:544-545` |
| `usize`/`isize` integer width is 32 bits | `sf/src/type_registry.zig:337` |
| Pointer and many-pointer types are size 4, align 4 | `sf/src/type_registry.zig:750-753`, `sf/src/type_registry.zig:772-775` |
| A slice is size 8 and emitted as `{ Elem *ptr; unsigned int len; }` | `sf/src/type_registry.zig:800`, `sf/src/c89_emit.zig:1726-1742` |
| `i64`/`u64`/`f64` are size 8, align 8, pinned by `Z98_ALIGN8` | `sf/src/include/zig_compat.h:5-9`, `:29-30`, `:49`; `sf/src/c89_emit.zig:1699-1716` |
| Optional and error-union layout uses a hard-coded 4-byte payload/tag step | `sf/src/type_resolver.zig:365-377` |
| `va_list` is size 4, align 4 | `sf/src/type_registry.zig:1155` |
| `@sizeOf`/`@alignOf`/`@bitSizeOf` read the registry's stored size/alignment | `sf/src/type_resolver.zig:1255-1273` |
| `usize` literal range is capped at `4294967295` | `sf/src/type_registry.zig:2181` |
| `@ptrToInt` always produces `usize`; `@intToPtr` casts through `(unsigned int)` | `sf/src/c89_emit.zig:7949-7955`, `sf/src/c89_emit.zig:3597-3603` |
| `@isWindows` is the only target predicate | `sf/src/main.zig:650`, `sf/src/comptime_eval.zig:1579-1580`, `sf/src/lower.zig:6137` |
| POSIX 64-bit seek is `_llseek` syscall 140, with i386 `struct stat` offsets | `sf/src/std_file.zig:80-98`, `sf/src/std_file.zig:206` |
| POSIX file primitives are declared as `open/read/write/syscall/close/...` | `sf/src/std_file_pal.zig:43-69` |
| Windows and POSIX PAL branches are compile-time `_WIN32` splits | `sf/src/include/zig_pal.c:6-20`, `sf/src/include/zig_pal.c:241-348`; `sf/docs/tech_docs/13_windows_support.md` §2 |
| Compiler peak budget is 16 MB, but the pool is a 256 MiB static array | `sf/src/allocator.zig:247-248`, `sf/src/allocator.zig:257-258`, `docs/sf/AGENTS.md:21-22`, `:99` |
| Default pool budget is 64 MB | `sf/src/allocator.zig:260`, `sf/src/main.zig:2043` |
| Seed build is `gcc -m32` with a fixed-point gate | `scripts/seed/build_from_seed.sh:18-29`, `:91-102`, `:150-168` |

The 256 MiB pool is a static BSS object. The 16 MB figure is an allocation
budget checked by `checkCombinedPeak` (`sf/src/allocator.zig:279-296`), not the
object's image size. Any self-host target must satisfy both.

## 2. Per-target analysis

The table below is the short form; the subsections give the real work.

| Target | C89 adequate as IR? | Main model fit | Main work | Native performance outlook |
|:--|:--|:--|:--|:--|
| AArch32 / ARMv7 (EABI, LE) | Yes | Good: 32-bit pointers, `int` 4, `long long` 8/8 | PAL syscall/struct/stat port; char unsigned; no type-width work | Close to x86-32; toolchain/CPU dependent |
| RISC-V RV32 (ILP32, LE) | Yes | Good: 32-bit pointers, `int` 4, `long long` 8/8 | PAL syscall/struct/stat port; char unsigned; `_llseek` 62 not 140 | Close to x86-32; core-dependent |
| AArch64 (LP64, LE) | Yes in principle | **No**: pointer/`usize` width, slice/optional/async layout | Full width parameterization; pointer casts; `va_list`; syscalls | Better baseline than 32-bit, but blocked by model work |
| RV64 (LP64, LE) | Yes in principle | **No**: same width/layout gaps | Same as AArch64 | Better baseline; blocked by model work |
| x86-64 (LP64, LE) | Yes in principle | **No**: same width/layout gaps | Same as AArch64; simplest toolchain availability | Better baseline; blocked by model work |
| 16-bit DOS / 8086/286 | Only with a different backend | **No** | 16-bit `int`, segmented pointers, 64 KiB objects, memory model | Not viable as a simple extension |

### 2.1 AArch32 / ARMv7

**C89 as IR.** Yes for expression, control-flow, and aggregate code. The
emitted C is ordinary C89; AAPCS32 is the C compiler's job. The data model is
close to the current one:

- Data pointer: 4 bytes, align 4.
- `char` is **unsigned** in the ARM C mapping (`LDRB is unsigned`).
- `int` 4, `long long` 8 align 8, `double` 8 align 8.
- Stack is 8-byte aligned at a public interface.

(Source: Arm AAPCS32, "Mapping of C & C++ built-in data types" and "Fundamental
Data Types", https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst.)

**What breaks.** Less than on 64-bit, but not nothing:

1. `c_char` is treated as signed by Z98's signedness helpers
   (`sf/src/type_registry.zig:1276`), while ARM C `char` is unsigned. Any
   operation that relies on plain `char` sign extension or comparison can
   differ. Most Z98 code uses explicit `u8`/`i8`, but the C ABI surface
   (`c_char`, C strings, `extern "c"` signatures) must be audited or the
   emitted `char` must be pinned with a target attribute.
2. `_llseek` is 140 on ARM EABI, same as the current i386 constant
   (`sf/src/std_file.zig:80`; Linux `arch/arm/tools/syscall.tbl` line 140 is
   `_llseek`). So the seek number happens to be right. The `struct stat`
   layout is not: the current `st_mtime` offset 64 and `st_size` offset 44
   are i386/glibc probes (`sf/src/std_file.zig:82-98`). ARM EABI stat layout
   differs and must be probed or avoided.
3. `std_time`'s `struct timeval` comment is explicitly 32-bit POSIX
   (`sf/src/std_time_pal.zig:15`). ARM 32-bit is compatible in shape, but
   time64 migration on modern glibc/musl must be checked.
4. POSIX `std_file` / `std_net` / `std_os` mostly work through libc, but the
   PAL prototypes and the `syscall` wrapper are target ABI assumptions
   (`sf/src/std_file_pal.zig:43-69`).
5. The Windows PAL is irrelevant; a Linux/Android/bare-metal PAL is needed.
   Android adds bionic differences and a different `struct stat`, plus
   `/proc/self/exe` may not exist for `pal_get_default_lib_path`.

**Toolchain.** GCC/Clang cross toolchains for `arm-linux-gnueabihf` and
`arm-none-eabi` are standard **[unverified locally]**. C89 mode is supported.
Bare-metal needs a startup file, linker script, and a libc or shim.

**ABI/layout.** AAPCS32 matches the current 32-bit model closely: 4-byte
pointers, 8-byte `long long` alignment, 8-byte stack alignment. `Z98_ALIGN8`
is at worst redundant on ARM. No new ABI selection is needed for ordinary C
calls; the C compiler chooses AAPCS.

**OS/PAL work.** Linux/Android: port or verify `std_file`, `std_os`, `std_time`,
`std_net`, and `pal.zig`'s compiler-side file/args/time hooks. Bare-metal:
replace all of them and add startup.

**Performance.** A 32-bit ARM target with a good C compiler and `-O2` should be
in the same broad class as 32-bit x86 for this kind of code. No numbers are
claimed. The current build recipe uses `-O0` (`sf/src/c89_emit.zig:8556`),
which is a larger immediate performance factor than the architecture.

### 2.2 RISC-V RV32

**C89 as IR.** Yes. RV32 ILP32 has 4-byte pointers and 4-byte `int`, 8-byte
`long long`, a 128-bit-aligned stack at procedure entry, and `char` is
unsigned. (Source: RISC-V psABI, "ILP32" type table and "C/C++ Type
Representations", https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-cc.adoc,
and the ABI spec, https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-abi.adoc.)

**What breaks.**

1. **Syscall numbers differ.** RISC-V uses the generic syscall table. On
   ILP32, `__NR3264_lseek` is 62 and maps to `__NR_llseek`; 140 is
   `__NR_setpriority` in the generic table. The current `SYS_LLSEEK = 140`
   (`sf/src/std_file.zig:80`) is wrong for RISC-V. See Linux
   `include/uapi/asm-generic/unistd.h` (`#define __NR3264_lseek 62`,
   `__NR_llseek __NR3264_lseek`) and its header comment: "New architectures
   should use this file".
2. **`struct stat` / `timeval` layout** differs from i386; the probed offsets
   in `sf/src/std_file.zig:82-98` do not apply.
3. **`char` unsigned** vs Z98 `c_char` treated as signed
   (`sf/src/type_registry.zig:1276`).
4. **Calls through libc** are fine; bare-metal needs SBI or a PAL shim.
5. **`gethostbyname` return-as-`usize`** (`sf/src/std_net.zig:580`) is
   intentionally pointer-sized; with 32-bit `usize` on RV32 it is consistent.
   It becomes a 64-bit blocker only on RV64.

**Toolchain.** `riscv64-unknown-elf-gcc` / `riscv32-unknown-linux-gnu-gcc`
and Clang are standard **[unverified locally]**. C89 is supported. RV32IMAC
without F/D uses soft-float; the C compiler emits the appropriate libcalls.

**Floating point.** Z98 `f32`/`f64` are ordinary C `float`/`double`. Soft-float
and hard-float ABIs are the C toolchain's choice; code generated for one ABI
must not be linked with the other. That is a build-recipe concern, not a
language concern.

**Performance.** RV32 cores vary enormously. With a good core and `-O2`, this
should be in the same class as 32-bit x86; no benchmark is asserted. RV32's
smaller register file and lack of some addressing modes may cost more on
pointer-heavy code. This is qualitative.

### 2.3 AArch64

**C89 as IR.** Yes in principle; the emitted C is portable C89. The blocker is
the Z98 type/layout model, not C89.

**What breaks.**

1. **Pointer/`usize` width.** LP64 pointers are 8 bytes
   (`sf/src/include/zig_compat.h:50` is `unsigned int`, i.e. 4). The registry
   hard-codes pointer size 4 (`sf/src/type_registry.zig:750-753`,
   `:772-775`), so every pointer-containing struct layout is wrong.
2. **Slice layout.** Z98 slices are size 8 (`sf/src/type_registry.zig:800`)
   and emitted as `{ Elem *ptr; unsigned int len; }`
   (`sf/src/c89_emit.zig:1726-1742`). On LP64 this must be 16 bytes with a
   64-bit length. All by-value slice ABI, struct layout, and `@sizeOf` follow.
3. **Optional/error-union layout.** The `+4` tag steps and 4-byte alignment
   floors in `sf/src/type_resolver.zig:365-377` are 32-bit assumptions. On
   LP64 the tag/alignment must become 8 bytes where the payload alignment is
   8.
4. **Pointer/integer casts.** `@ptrToInt` always produces `usize`
   (`sf/src/c89_emit.zig:7949-7955`) and `@intToPtr` casts through
   `(unsigned int)` (`sf/src/c89_emit.zig:3597-3603`). On AArch64 this
   truncates every pointer. The literal-fit check caps `usize` at `2^32-1`
   (`sf/src/type_registry.zig:2181`).
5. **`va_list`.** Z98 models `va_list` as size 4
   (`sf/src/type_registry.zig:1155`) and emits the C `va_list` type
   (`sf/src/type_registry.zig:547`). AArch64's `va_list` is a 32-byte
   aggregate with its own ABI; `@sizeOf(va_list)`, struct embedding, and
   by-value passing assumptions all break. (AAPCS64 defines the type; the
   size is architecture-specific.)
6. **Syscalls/stat.** AArch64 Linux `lseek` is not `_llseek`; use `lseek`
   (generic 62) or libc. `struct stat` differs from i386. The current
   `std_file` POSIX branch must be target-selected.
7. **ASLR/address size.** The C compiler/loader handles 48-bit canonical
   addresses; the compiler's `usize` must be 64-bit for pointer arithmetic
   and `@ptrToInt`.

**Toolchain.** `aarch64-linux-gnu-gcc` and Clang are standard
**[unverified locally]**. C89 mode is supported. Linux/Android PAL work is the
same shape as ARMv7 but with 64-bit types.

**ABI/layout.** The C compiler handles AAPCS64 for ordinary C calls. Z98's
`extern "stdcall"` (`sf/src/c89_emit.zig:1793-1798`) is x86-specific and must
be rejected or remapped on AArch64; it should not silently emit an empty
`Z98_STDCALL` into a non-x86 ABI.

**Performance.** AArch64 has a better baseline than AArch32 (more registers,
64-bit arithmetic native, better memory model). Once the 64-bit model is
correct, `-O2` should produce competitive code for Z98's workload. This is
qualitative; no benchmark was run.

### 2.4 RV64

**C89 as IR.** Yes in principle.

**What breaks.** The same list as AArch64, with RISC-V specifics:

- LP64 pointers/`long` 8 bytes; `size_t` is `unsigned long`
  (RISC-V psABI "LP64" table).
- `va_list` has the same representation as `void *`
  (RISC-V psABI "va_list, va_start, and va_arg") and is therefore 8 bytes.
  Z98's 4-byte `va_list` model is wrong.
- `char` is unsigned (RISC-V psABI "C/C++ Type Representations").
- Linux syscall ABI: `lseek` 62, not `_llseek` 140. The generic table maps
  `__NR_lseek` to `__NR3264_lseek` on 64-bit.
- Bare-metal needs SBI `ecall` or a shim; no libc.

**Toolchain.** `riscv64-linux-gnu-gcc` / Clang standard **[unverified
locally]**. RV64GC vs RV64IMA affects float support; the ABI (LP64 vs LP64D)
must be consistent across all objects.

**Performance.** RV64 avoids 32-bit long-long libcalls and has a cleaner
64-bit baseline. Relative to x86-64/AArch64, implementation quality and
extension set matter more than the ISA. No numbers asserted.

### 2.5 x86-64

**C89 as IR.** Yes in principle. This is the easiest 64-bit target from a
toolchain standpoint (the host is almost certainly x86-64) and the hardest to
justify because the current code deliberately emits 32-bit C.

**What breaks.** The same LP64 issues:

- `usize`/pointer width, slice 8 -> 16, optional/error-union layout,
  `va_list` (x86-64 SysV `va_list` is a 24-byte array-of-struct type), pointer
  casts, `@sizeOf`.
- `@ptrToInt` must produce a 64-bit value; `@intToPtr` must not cast through
  `(unsigned int)`.
- `_llseek` is not available on x86-64; use `lseek` (syscall 8) or
  `lseek64`/libc. (Linux x86-64 syscall table: lseek = 8; see
  https://filippo.io/linux-syscall-table/.)
- `struct stat` and `struct timeval` layouts differ from i386.
- The build scripts pass `-m32` unconditionally; a 64-bit target needs a
  separate recipe and must not link 32-bit runtime objects.

**Toolchain.** Native `gcc`/`clang` is available on the host. C89 mode is
supported.

**Performance.** x86-64 removes 32-bit long-long helpers and has more
registers. With `-O2` it should be the fastest of the candidate targets for
this code, but the 32-bit semantic model (`usize` 4) would cause repeated
extension/truncation if left in place. Correct width parameterization is a
prerequisite for both correctness and performance.

### 2.6 16-bit DOS / 8086 / 286

**Verdict: not viable as a simple extension of the current backend.** It is a
different code-generation model, not another target profile.

Reasons, in order of severity:

1. **`int` is 16-bit.** The C89 emitter spells `i32`/`u32` as `int`/`unsigned
   int` (`sf/src/type_registry.zig` primitives, and the default C spelling
   paths). On a 16-bit compiler, `int` is 16 bits, so every 32-bit operation
   would need `long`, with different promotion rules, `printf` formats, and
   helper calls. Z98's `i32` is 4 bytes by language definition
   (`sf/src/type_registry.zig:1140`); the target type cannot silently become
   2 bytes.
2. **Segmented pointers.** 8086/286 pointers are 16-bit near or 32-bit
   segment:offset far pointers. A `usize` that fits a linear address does not
   exist without a memory model. `@ptrToInt`, `@intToPtr`, pointer subtraction,
   slice `ptr + len`, arrays, and any object larger than 64 KiB need explicit
   near/far/huge handling. The current flat 4-byte pointer model
   (`sf/src/type_registry.zig:750-753`) is not representable.
3. **Object size and stack.** The compiler's static 256 MiB pool
   (`sf/src/allocator.zig:247-248`) and 16 MB budget cannot fit in the
   640 KiB conventional-memory model or a single 64 KiB segment. A 16-bit
   compiler would need a different allocator, smaller data structures, and a
   memory model that can address them. The current compiler is not close.
4. **Toolchain.** 16-bit C compilers exist (OpenWatcom `WCC` is the 16-bit
   compiler; `WCC386` is the 32-bit one:
   https://open-watcom.github.io/open-watcom-v2-wikidocs/cguide.html). They
   support small/medium/compact/large/huge memory models, but each model
   changes pointer sizes and calling conventions. The emitted C would need a
   model-aware pointer type, not a single `usize`.
5. **Startup and OS.** DOS has no POSIX/Win32 PAL; file I/O, time, console,
   and networking need DOS interrupts or a DOS extender. Bare-metal 8086 needs
   startup code and a linker script.

A **32-bit protected-mode DOS** target (386 + DOS extender, OpenWatcom
`WCC386`, flat model) is a different and much more plausible question: 4-byte
pointers, 4-byte `int`, flat address space. It still needs a DOS PAL and an
extender, but it does not require a 16-bit memory model. It is not the same
as "16-bit DOS support" and should be scoped separately.

## 3. Real blockers, ranked

The ordering is by blast radius and by how many targets each blocks.

### 3.1 Target-width-parameterized type model (highest)

**What:** make `usize`, `isize`, pointer size/alignment/width, slice layout,
optional/error-union layout, `va_list`, and `@sizeOf`/`@alignOf`/`@offsetOf`
depend on a target descriptor rather than constants.

**Evidence of the constants:** `sf/src/type_registry.zig:337`, `:544-545`,
`:750-753`, `:772-775`, `:800`, `:1146-1147`, `:1155`, `:2181`;
`sf/src/type_resolver.zig:365-377`, `:1255-1273`;
`sf/src/c89_emit.zig:1726-1742`, `:1699-1716`.

**Why it is hard:** layout is computed once in `type_resolver.zig` and read by
lowering, comptime evaluation, async layout, C emission, and `@sizeOf`. A
width change affects struct offsets, field access emission, by-value ABI,
array sizes, tagged-union payloads, async frame offsets, slice/optional
passing, and every golden output. It is a cross-cutting semantic change, not a
flag.

**Targets:** AArch64, RV64, x86-64. AArch32/RV32 need only pointer-width
consistency (already 4) and `va_list`/`c_char` audit.

**Complexity/risk:** very high. Silent layout divergence is the main risk;
the 32-bit corpus/goldens do not exercise it.

### 3.2 Pointer/integer casts and width-sensitive literals

**What:** `@ptrToInt`/`@intToPtr` must use the target pointer width; integer
literal fit checks must use target `usize`/`isize`; arithmetic that mixes
pointers and `usize` must not truncate.

**Evidence:** `sf/src/c89_emit.zig:7949-7955` (result `TYPE_USIZE`),
`sf/src/c89_emit.zig:3597-3603` (`(unsigned int)` cast),
`sf/src/type_registry.zig:2181` (cap 4294967295).

**Targets:** all 64-bit. AArch32/RV32 are already consistent at 32 bits.

**Complexity/risk:** medium once the type model exists; high if done first,
because changing the cast spelling without changing `usize` creates
inconsistent arithmetic.

### 3.3 64-bit literals and arithmetic

The 64-bit spelling layer already exists for the Windows work:
`z64`/`zu64`, `Z98_I64_C`/`Z98_U64_C`, and `Z98_ALIGN8`
(`sf/src/include/zig_compat.h:18-37`, `sf/docs/tech_docs/13_windows_support.md`
§7). The emitter routes `i64`/`u64`/`f64` through carrier typedefs
(`sf/src/c89_emit.zig:1699-1716`). This is the part that is **already in
progress/landed**; the remaining work is to ensure shifts, division, and
constants are target-correct on 64-bit `usize` and on compilers without
`long long` helpers. C89 itself has no standard 64-bit type; the existing
`long long` extension is a toolchain assumption, already documented for gcc,
MSVC, and OpenWatcom.

**Targets:** all; 32-bit targets use the same spellings but do not need 64-bit
pointers.

**Complexity/risk:** low-medium. The main risk is a compiler that lacks a
64-bit type (some 16-bit toolchains), which is a separate backend issue.

### 3.4 ABI and calling-convention selection

For ordinary Z98 functions, the C compiler selects the platform ABI. Z98 only
models `c` and `x86_stdcall`; `emitCallConv` writes `Z98_STDCALL` for the
latter (`sf/src/c89_emit.zig:1793-1798`), and `zig_compat.h` defines it only on
Windows (`sf/src/include/zig_compat.h:61-67`). On non-x86 targets, `stdcall`
is not meaningful and must be rejected, not silently ignored.

**Targets:** all non-x86 for `stdcall`; ARM/RISC-V only if calling handwritten
assembly or bare-metal entry points. Linux/Android/Windows ordinary C calls
need no new callconv.

**Complexity/risk:** low for validation, medium if target-specific calling
conventions (AAPCS variants, RISC-V ILP32E/LP64D, Windows ARM64) become part
of the language surface.

### 3.5 Syscall and PAL layers

**What:** select syscall numbers, `struct stat`/`timeval` layouts, file APIs,
console, network byte order, and startup per target.

**Evidence:** `sf/src/std_file.zig:80` (`SYS_LLSEEK=140`),
`:82-98` (i386 stat probe), `:206` (`pal.syscall`),
`sf/src/std_file_pal.zig:43-69` (POSIX extern surface),
`sf/src/std_time_pal.zig:15` (32-bit timeval),
`sf/src/std_net.zig:42-50` (host byte order helpers),
`sf/src/include/zig_pal.c:6-20` and `:241-348` (Win32/POSIX split).

**Targets:** every target. AArch32 happens to share `_llseek` 140 with i386;
RV32/RV64 use generic 62; x86-64 uses `lseek` 8; AArch64 uses `lseek`.
**`struct stat` and `timeval` must be probed or generated per target; copying
the i386 offsets is wrong.** The sibling doc 13 already establishes the
pattern for platform-profile work.

**Complexity/risk:** medium. The risk is silent ABI corruption (wrong struct
offset) rather than a clean link error.

### 3.6 Endianness

All currently discussed targets are little-endian. The emitted C delegates
object layout to the target C compiler, so ordinary typed accesses are
endian-correct. The exceptions are explicit byte-order code:

- `std_file.zig`'s `leU32At` (`sf/src/std_file.zig:124-132`) is little-endian
  by construction. It is used for `st_mtime`/FILETIME; on a big-endian target
  it would be wrong unless the host stat field is handled natively.
- `std_net.zig`'s `htonsManual`/`htonlManual` (`sf/src/std_net.zig:45-50`)
  implement little-endian byte swapping. On a big-endian host, `htons` and the
  manual variant have different behavior; this must be audited if big-endian is
  ever added.
- Bit-field/packed-struct layout rules differ on big-endian; the current
  packed load/store code assumes a byte order.

**Targets:** none of the required targets. **AArch32 BE, ARM BE8, RV32/RV64
big-endian, and s390x are out of scope** unless explicitly added. If added,
endianness becomes a first-class target property, not a compile-time constant.

**Complexity/risk:** low for the current list; high if big-endian is added.

### 3.7 Async/coroutine frame assumptions

The coroutine `Context` header is 16 bytes with `used` at offset 0,
`capacity` at offset `1*sizeof(usize)`, and `oom` at `2*sizeof(usize)`
(`sf/src/async_state_machine.zig:63-75`). The compiler uses its own
`@sizeOf(usize)`, which is currently 4, and the library documents
`ctx+0`, `ctx+4`, `ctx+8`, `ctx+16`
(`sf/src/std_async.zig:42-51`, `:59-60`). If `usize` becomes 8 on a 64-bit
target, the header layout becomes 8/8/8 + padding and `CTX_POOL_OFF` must
change; the two sides must move together or frames corrupt.

Frame fields are pointer-sized (`step`, `ctx`, `child`, `result`), and every
frame is 8-byte padded (`sf/docs/tech_docs/12_async_coroutines.md` §3). On
64-bit, frames grow, and `saveAllFields`/`reloadAllFields` copy more bytes per
suspend/resume (`sf/src/async_state_machine.zig:265-...`). This is correct if
layout is parameterized, but it is a performance and memory-budget factor.

**Targets:** all 64-bit. 32-bit targets keep the current 16-byte header.

**Complexity/risk:** medium-high. The failure mode is silent frame corruption,
not a type error.

### 3.8 Compiler self-emission and seed portability

The seed recipe is x86-32 gcc with a two-hop fixed point
(`scripts/seed/build_from_seed.sh:18-29`, `:91-102`, `:150-168`), and the
developer build is `gcc -m32` (`docs/sf/AGENTS.md:458`). Self-hosting on
another architecture requires:

- a C compiler for the target that accepts the emitted C89,
- a target `zig_pal.c` / runtime / prelude set,
- adjusting the build recipe away from `-m32` (and away from the x86 host
  assumptions in `pal.zig` / `zig_pal.c`),
- re-running the fixed-point closure. The md5 fixed point is **not portable
  across architectures or C compilers**; the closure must be re-established
  and recorded per target. Codegen differences between gcc versions already
  make this a moving target.

The bootstrap-staging constraint (`docs/sf/AGENTS.md:481-502`) means new
compiler features must be understandable by the current seed. A target-width
model or `asm` grammar cannot be used until a seed that understands it has
been rotated. That forces staged work: first C/PAL changes, then language
changes, then seed rotation.

**Targets:** all self-host targets. 32-bit ARM/RV32 are the easiest because
the compiler's own pointer/`usize` model already matches the target. 64-bit
self-hosting is blocked by §3.1.

**Complexity/risk:** high. A self-host port that compiles but miscompiles is
worse than a cross-compile-only port; the fixed-point gate is the safety net.

### 3.9 Memory budget and static pool

The compiler's 16 MB peak budget is a project constraint
(`docs/sf/AGENTS.md:21-22`, `:99`; `sf/src/allocator.zig:257-258`), but the
actual arena is a 256 MiB static array (`sf/src/allocator.zig:247-248`) with a
default 64 MB `-mm` limit (`sf/src/allocator.zig:260`,
`sf/src/main.zig:2043`). On a 32-bit Win9x/NT host, the 256 MiB BSS is a
virtual-memory reservation; on a small bare-metal or 16-bit target it is
impossible. A self-host port to a memory-constrained target must either:

- shrink/replace the pool with a platform allocator,
- make the pool size a compile-time or run-time configuration, and
- keep the 16 MB allocation budget.

**Targets:** bare-metal, 16-bit DOS, small embedded. Linux/Android/Windows
self-host can keep the static pool, subject to the 16 MB check.

**Complexity/risk:** medium. The risk is OOM at startup, not miscompilation.

### 3.10 Win32-specific PAL

`-osw` is a Windows profile (`sf/src/main.zig:1810-1831`) with a Win9x/NT
split (`sf/src/include/zig_pal.c:299-348`,
`sf/docs/tech_docs/13_windows_support.md`). It is irrelevant to non-Windows
targets but would matter for Windows on ARM64 or for a non-x86 Windows target:
`__stdcall`, `KERNEL32` imports, `GetCommandLineA`, no-CRT startup, and the
import whitelist are all x86/Win32-specific.

**Targets:** Windows ARM64 only if that is ever pursued. **Complexity/risk:**
medium and strictly separate from the Unix-like ports.

## 4. New compiler features required

This is the concrete feature list. "Yes" means the feature is needed for that
target; "no" means it can be skipped for a first port.

| Feature | AArch32 | RV32 | AArch64 | RV64 | x86-64 | 16-bit DOS |
|:--|:--:|:--:|:--:|:--:|:--:|:--:|
| Target triple/profile plumbing | yes | yes | yes | yes | yes | yes (different backend) |
| Width-parameterized `usize`/`isize`/pointer | no | no | yes | yes | yes | yes (segmented) |
| Layout/alignment model (`@sizeOf`, slices, optionals, `va_list`) | audit | audit | yes | yes | yes | yes |
| Pointer/integer cast width | no | no | yes | yes | yes | yes |
| 64-bit literal/arith portability | audit | audit | yes | yes | yes | yes (no native 64-bit) |
| ABI/callconv selection | audit | audit | yes (reject stdcall) | yes | yes | yes (memory model) |
| Endianness property | no (LE) | no (LE) | no (LE) | no (LE) | no (LE) | no |
| Target-specific PAL/syscall hooks | yes | yes | yes | yes | yes | yes |
| Build-recipe emission per target | yes | yes | yes | yes | yes | yes |
| Inline asm | only bare-metal | only bare-metal | only bare-metal | only bare-metal | rarely | likely |
| Compiler self-host PAL port | optional | optional | later | later | later | no |

### 4.1 Target triple/profile plumbing

**What:** a first-class target descriptor carried from CLI parsing
(`sf/src/main.zig`) through module registry, type registry, lowering, async
layout, C emission, and build-script emission. Minimum fields:

- `arch` (`x86`, `x86_64`, `arm`, `aarch64`, `riscv32`, `riscv64`, `m68k`?),
- `os` (`linux`, `windows`, `android`, `none`),
- `abi` (`sysv`, `mingw`, `aapcs`, `ilp32`, `lp64`, `ilp32d`, `lp64d`),
- `pointer_width` (4/8/2),
- `endian` (little/big),
- `char_signed` (true/false),
- `callconv` support set,
- `syscall`/PAL profile.

**CLI:** keep `-osl`/`-osw` working; add `--target <triple>` or `-arch` +
existing OS flags. `--help` must be truthed up
(`sf/src/main.zig:2051-2059`).

**Threading:** the emitter currently receives `target_is_windows` and
`win_profile` only (`sf/src/main.zig:1646`). Every consumer of
`@isWindows` (`sf/src/comptime_eval.zig:1579-1580`,
`sf/src/lower.zig:6137`, `sf/src/semantic_analyzer.zig`) must become
target-aware, or a new predicate set must be added. A simple boolean
`host_is_windows` is insufficient.

**Complexity/risk:** medium. The risk is inconsistent target state (e.g. the
emitter says 64-bit but the type registry still says 4-byte pointers).

### 4.2 Width-parameterized type and layout model

**What:** replace the constants in §3.1 with values derived from the target
descriptor. Specific pieces:

- `Type.size`/`alignment` for primitives, pointers, slices, optionals,
  error unions, tuples, tagged unions, arrays, and functions.
- Field offset computation in `layoutCompute`
  (`sf/src/type_resolver.zig:278-405`).
- `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf` folding
  (`sf/src/type_resolver.zig:1255-1273`).
- Slice emission (`sf/src/c89_emit.zig:1726-1742`) with a pointer-width
  length and natural alignment.
- Optional/error-union emission and field offsets.
- `va_list` size/alignment and C spelling.
- Array-size arithmetic (`Type.size` is `u32`; 64-bit objects can exceed it
  only if a single type is >4 GiB, which is unlikely but should be checked).

**Complexity/risk:** very high. This is the feature that makes 64-bit targets
real; without it, 64-bit output compiles but miscomputes every layout.

### 4.3 Pointer/integer casts

**What:** make `@ptrToInt` produce the target `usize` type, and
`@intToPtr` emit a cast through the target pointer-width integer type (or a
direct pointer cast), not `(unsigned int)`. The literal-fit check must use the
target `usize` range. The IR already records `ptr_to_int`/`int_to_ptr`; the
emitter change is small, but it must be coupled to §4.2.

**Complexity/risk:** medium. Silent truncation is the failure mode.

### 4.4 64-bit arithmetic

The 64-bit spelling layer exists (`z64`/`zu64`, `Z98_ALIGN8`). The remaining
work is target verification: C89 compilers that lack `long long` (some 16-bit
toolchains) need a different strategy, and 64-bit shifts/division must use the
toolchain's helpers. No `i128` is required by any target in scope; adding it
would expand the backend without a demonstrated need.

**Complexity/risk:** low-medium.

### 4.5 ABI/callconv validation

**What:** keep `extern "c"` as the default; validate `extern "stdcall"` only
on x86 Windows; reject it on non-x86; add target ABI names only if a real
external interface needs them. Ensure function-pointer typedefs and
`emitCalleeExpr` (`sf/src/c89_emit.zig:1820-1843`) match the C compiler's
expectations.

**Complexity/risk:** low for validation; medium for adding AAPCS/RISC-V
variants to the language surface.

### 4.6 Target-specific PAL hooks

**What:** a target PAL layer for file I/O, time, environment, console, network,
process exit, and startup. Today the split is compile-time `_WIN32` inside
`sf/src/include/zig_pal.c` and the prelude headers. A clean port needs a
descriptor-driven PAL, not more `#ifdef`s. The emitted support mirrors in
`sf/src/emit_support.zig` must stay byte-identical to
`sf/src/include/*` (`scripts/check_emit_support.sh`), so both copies change
together.

**Minimum per target:**

- syscall numbers / libc entry points (open/read/write/close/lseek/stat/
  gettimeofday/unlink/rename/access/socket/...),
- `struct stat`, `struct timeval`, `sockaddr` layouts,
- console/stdout/stderr writes,
- environment and argv,
- executable path for `<exe_dir>/lib`,
- exit/abort/trap,
- Windows profile if `os == windows`.

**Complexity/risk:** medium. The risk is ABI mismatch; probes are required.

### 4.7 Build-recipe emission

**What:** emit a target-appropriate `build_target.sh`/`.bat` with:

- cross compiler name (`arm-linux-gnueabihf-gcc`, `riscv32-...`,
  `aarch64-...`, native `gcc`, etc.),
- target flags (`-march`, `-mabi`, `-mfloat-abi`, `-m32`/`-m64`),
- optimization (`-O2` for release, `-O0` for bring-up),
- linker/startup options for bare-metal,
- the correct runtime/support object set.

Today the emitter hard-codes `-m32` and only `linux`/`mingw`
(`sf/src/c89_emit.zig:8556-8565`, `:8769-8795`). **Complexity/risk:** low.

### 4.8 Inline asm (optional; see §5)

**What:** a language `asm` construct if bare-metal targets genuinely need it.
Otherwise put asm in the C PAL and expose it through `extern "c"`. **Targets:**
primarily bare-metal startup/syscalls and CPU feature probes. **Complexity/
risk:** high if added to Z98; low if confined to C helpers.

### 4.9 Not required

- `i128`: no target in scope needs it; C89 has no portable 128-bit type.
- SIMD/vector types: not required for correctness; the C compiler can
  auto-vectorize, and Z98 has no vector surface.
- Garbage collection, exceptions, or reflection: unrelated.
- A full register allocator/optimizer: the C compiler is the optimizer; the
  current backend intentionally emits simple C.

## 5. Inline assembly: where it is real, and a minimal design

### 5.1 Where asm is genuinely required

**Genuinely required (no portable C equivalent):**

1. **Bare-metal startup.** Reset vector, initial stack pointer, BSS zeroing,
   relocation, and the jump to `main`. This is usually a small `.S` file or
   a `naked` function, not general inline asm. It can live outside Z98 in the
   PAL/startup file.
2. **Bare-metal system calls.** RISC-V SBI `ecall`, ARM semihosting `svc`/
   `bkpt`, or a target-specific trap. A C helper with inline asm is the
   practical route.
3. **CPU feature discovery and barriers.** `cpuid` on x86, `mrs` on AArch64,
   `csrr`/`fence` on RISC-V, cache/TLB maintenance, and atomic
   compare-and-swap on targets whose C compiler lacks the needed builtins.
4. **Targets whose C toolchain lacks required intrinsics.** Some embedded/
   DOS compilers. The main Linux/Android/Windows toolchains have builtins or
   libc for normal work.

**Not required:**

- Linux/Android/Windows ordinary programs: libc/Win32 provide file, time,
  console, network, and process services. The compiler already uses C/PAL
  helpers.
- Atomic builtins on GCC/Clang: `__sync_*`/`__atomic_*` or C11 atomics (not
  C89, but a compiler extension) are usually enough. Z98 currently has no
  atomics surface; if added, a C helper is the first choice.
- Floating point: the C compiler emits the right instructions/libcalls.
- `int3`/trap: `pal_trap` already uses compiler-specific asm in C
  (`sf/src/include/zig_pal.c:139-161`), guarded by architecture macros.
  That pattern can be extended without a Z98 `asm` feature.

### 5.2 Why not add Z98 `asm` first

Adding `asm` to Z98 is expensive:

- Lexer/parser/AST: string-literal templates, operand lists, constraint
  strings, clobber lists, `volatile`, optional labels.
- Semantic analysis: output operands must be lvalues; constraints must match
  operand types; clobbers must not overlap; target-specific validation.
- LIR: a new instruction carrying template/operands/clobbers; DCE and
  copy propagation must treat it as having side effects; the async transform
  must not move it across suspensions.
- C89 emission: GCC/Clang use `__asm__ __volatile__` (a GNU extension, not
  C89); MSVC uses `__asm` (x86 only); OpenWatcom has its own `#pragma aux`
  or `_asm`. There is no portable C89 spelling. The emitted code stops being
  strict C89.
- Bootstrap: the current seed cannot parse `asm`, so the feature cannot be
  used in `sf/src` until a seed rotation. It would be a language change with
  a seed dependency.
- Safety: the compiler cannot validate the template; a bad constraint or
  clobber is undefined behavior. The project's `-fsafe` model cannot help.

### 5.3 Minimal design if it is still needed

A conservative Zig-like surface:

```zig
asm volatile (
    "template with %0, %1"
    : [out] "=r" (out_var),   // outputs
    : [in]  "r"  (in_var),    // inputs
    : "cc", "memory"          // clobbers
);
```

Design rules:

- **Statement only** in the first version (no asm expressions), plus an
  optional `volatile`.
- **Constraints:** a fixed subset (`r`, `m`, `i`, `=&r`, `+r`) with
  target-specific extensions gated by the target descriptor.
- **Clobbers:** register names plus `cc` and `memory`.
- **No `asm goto`** initially.
- **Target gate:** reject at semantic analysis if the target is not in the
  supported asm set.
- **Emission:** write the host compiler's spelling:
  - GCC/Clang: `__asm__ __volatile__("..." : ... : ... : ...);`
  - MSVC x86: `__asm { ... }` (no operand constraints); this is a different
    surface and may be rejected in v1.
  - OpenWatcom: reject in v1 or use `#pragma aux` helpers.
- **C89 mode:** document that inline asm is an extension and that the emitted
  C is no longer strict C89. `-ffast` does not change asm semantics; `-fsafe`
  must not insert checks into the asm block.
- **Relaxed mode:** if `-ffast` implies "no checks", it still must not delete
  `volatile` asm.

**Recommended alternative (lower risk):** keep asm in C support files. Add
target-specific `extern "c"` helpers such as `pal_cpu_features()`,
`pal_atomic_cas()`, `pal_startup()`, and `pal_syscall()`, implemented in
`zig_pal.c`/new PAL C files with the compiler's inline asm or builtins. Z98
code calls them normally. This works today, does not change the language, and
does not require a seed rotation. Add Z98 `asm` only if a bare-metal target
cannot be expressed through C helpers.

## 6. Targeting another architecture vs self-hosting the compiler

These are different projects. Do not conflate them.

### 6.1 (a) Emit C for another target (cross-compile)

The compiler stays an x86-32 binary. It emits C for the target, and a cross
C compiler builds it.

**Work:**

1. Target descriptor/CLI (§4.1).
2. Width/layout model if the target is 64-bit (§4.2).
3. Pointer/cast width (§4.3).
4. Target PAL/syscall/prelude (§4.6).
5. Target build recipe (§4.7).
6. Cross toolchain + runtime objects.
7. Target test corpus/goldens (new, not the 32-bit ones).

**What is reused:** the lexer, parser, semantic analysis, lowering, async
transform, C emitter, and most of the stdlib. The stdlib's OS-specific modules
(`std_file`, `std_os`, `std_time`, `std_net`, `pal.zig`) need PAL branches.
The compiler's own host PAL is irrelevant to the emitted program (the emitted
program links the emitted runtime, not the compiler's host runtime).

**Effort:** AArch32/RV32 Linux is medium (mostly PAL/build/goldens); 64-bit is
high (type model). This is the recommended first path.

### 6.2 (b) Build and run the compiler on the target (self-host)

The compiler itself runs on the target, so it needs a host C compiler, a host
PAL, and enough memory.

**Additional work on top of (a):**

1. **Host PAL port.** `pal.zig` and `sf/src/include/zig_pal.c` provide file
   I/O, args, time, directory existence, executable path, trap/abort, and
   console. On the target these must use the target OS/libc (or bare-metal
   shims). The compiler's own `fopen/fread/fwrite/fseek/ftell` and
   `open/read/write` wrappers must work.
2. **Host C compiler.** The target must have a C89 compiler that accepts the
   emitted C. On bare-metal, that means a cross toolchain and a runtime; on
   Linux/Android, gcc/clang is available.
3. **Build recipe.** `scripts/seed/build_from_seed.sh` and the developer
   recipe are `gcc -m32`; they must be parameterized by target and must not
   assume x86.
4. **Seed portability.** The committed seed is an x86 binary. A target
   self-host needs either a cross-built seed or a target-native seed. The
   fixed-point md5 is target/compiler-specific and must be re-established
   (`scripts/seed/build_from_seed.sh:18-29`, `:150-168`).
5. **Memory budget.** The compiler's static 256 MiB pool
   (`sf/src/allocator.zig:247-248`) and 16 MB budget
   (`docs/sf/AGENTS.md:99`) must fit the target. Linux/Android with virtual
   memory can reserve the pool; a bare-metal or 16-bit target cannot.
6. **Self-host correctness.** The compiler must compile itself and close the
   fixed point. A cross-compiled compiler that cannot self-emit is not a
   self-host port; it is only a cross compiler.
7. **Pointer-width consistency.** The compiler's own `usize` is 4 bytes. On a
   32-bit target this matches the machine, which is why ARMv7/RV32 Linux are
   the easiest self-host targets. On a 64-bit target, the compiler itself
   would be compiled with 8-byte pointers while its internal `usize` typedef
   is 4 bytes (`sf/src/include/zig_compat.h:50`), corrupting its own data
   structures. **64-bit self-hosting is blocked until the compiler's type
   model is target-width-parameterized and the compiler is rebuilt with it.**

**Effort:** 32-bit ARM/RV32 Linux self-host is medium-high (PAL + build +
seed + tests); 64-bit self-host is very high (after §4.2); bare-metal
self-host is very high (no OS, no libc, memory constraints) and probably not
worth it.

## 7. Performance

No benchmarks were run. The following are the real limiters, in rough order.

1. **Optimization flags.** The emitted build scripts use `-O0`
   (`sf/src/c89_emit.zig:8556`, `:8560-8565`), and the seed/compiler build is
   also `-O0` (`scripts/seed/build_from_seed.sh:91-102`). This is the largest
   immediate performance lever. A release target should use the toolchain's
   `-O2`/`-O3` (and optionally LTO), with the existing gates re-run to catch
   optimizer-exposed UB. The project may deliberately keep `-O0` for
   bring-up/determinism; that is a separate policy decision.
2. **C compiler quality.** The backend emits straightforward C with hoisted
   temps and explicit locals. GCC/Clang at `-O2` can clean up most of it, but
   the generated code is not tuned for any specific microarchitecture. On
   embedded cores, code size and register pressure matter more than on
   desktop x86.
3. **32-bit vs 64-bit data model.** A 32-bit target matches Z98's current
   `usize`/pointer model: no extra extensions/truncations, 8-byte slices,
   16-byte async headers. A 64-bit target has more registers and native
   64-bit arithmetic, but doubles pointer/slice/frame sizes and requires
   correct width parameterization. If the model is left at 32 bits on a
   64-bit machine, pointer arithmetic truncates and performance suffers from
   repeated extension; correctness fails first.
4. **64-bit arithmetic on 32-bit targets.** `i64`/`u64` operations use the C
   compiler's 64-bit helpers on 32-bit targets; on 64-bit targets they are
   native. Z98's workload (compiler, file/network/audio code) has some 64-bit
   math but is not dominated by it.
5. **PAL/libc overhead.** The emitted file layer uses `open/read/write` and
   `_llseek`; `size`/`seek` on POSIX may perform multiple seeks
   (`sf/src/std_file.zig:206-...`, `sizeHandle`). On Windows it uses
   `pal_file_size`/`pal_file_seek64`. These are ordinary syscall/libc costs,
   not architectural bottlenecks. Direct syscalls or larger buffers can
   reduce overhead, but the C compiler/libc is usually fine.
6. **Async frame copying.** Every suspend saves and every resume reloads all
   live frame fields (`sf/src/async_state_machine.zig:265-...`). Larger
   64-bit frames make this more expensive. A future optimization could copy
   only dirty fields or use a stackful coroutine model, but that is not
   required for correctness and is outside this report.
7. **Win32/PAL profile overhead.** The Win9x no-CRT path uses hand-written
   helpers (`sf/docs/tech_docs/13_windows_support.md` §4-§6); these are small
   and should not dominate. The `-O0` and C compiler quality still dominate.
8. **Console/audio/network paths.** z9play's hot paths are PAL calls (audio,
   console, file). The architecture mostly affects the C compiler's ability
   to optimize the surrounding code; the PAL's syscall/API choice matters
   more. No numbers are claimed.

**Realistic path to "as close/performant as possible" without emulation:**

- Start with AArch32/RV32 Linux, where the data model already matches.
- Use a good native/cross C compiler at `-O2` (or `-O3`/LTO) for release.
- Keep the 32-bit model for 32-bit targets; do not force 64-bit just for
  pointer size.
- For 64-bit targets, do the width parameterization first, then measure.
- Optimize PAL hot paths with target-appropriate APIs; keep the C emitter
  simple and let the C compiler optimize.
- Treat any performance claim as requiring a benchmark on real hardware;
  none is made here.

## 8. Phasing, effort, risks, and file-level change list

### 8.1 Recommended order

**Phase 0 — target descriptor plumbing (no behavior change).**
Add the target struct/CLI, thread it to the emitter/build scripts, keep the
current x86-32/Linux/Windows outputs byte-identical. Add a target-agnostic
build-script generator. No type-model change. *Effort: small-medium.*

**Phase 1 — AArch32 and RV32 Linux (cross-compile only).**
The 32-bit model already fits. Port/verify the POSIX PAL: syscall numbers
(`_llseek` 140 on ARM, 62 on RV32), `struct stat`/`timeval` layouts, `char`
signedness, `std_net` byte order, `std_os`, `std_time`, `std_file`. Emit
target build recipes. Cross-compile the corpus and add target probes. Run on
qemu or hardware. *Effort: medium.* This is the best first deliverable: it
proves the PAL/build path without touching the type model.

**Phase 2 — AArch32/RV32 bare-metal (optional).**
Add startup, linker scripts, a minimal PAL, and asm or C helpers for SBI/
semihosting. No OS. *Effort: high.* Only if bare-metal is a real goal.

**Phase 3 — 64-bit cross-compile (AArch64/RV64/x86-64).**
Implement the width-parameterized type/layout model, pointer casts, `va_list`,
slice/optional/error-union/async layout, syscall/PAL differences, and build
recipes. Add 64-bit goldens/probes. *Effort: very high.* This is the
make-or-break phase.

**Phase 4 — 32-bit self-host (AArch32/RV32 Linux).**
Port the compiler's host PAL, parameterize the seed/build recipe, re-establish
the fixed point, and verify self-emission on the target. Keep the 16 MB
budget. *Effort: medium-high.*

**Phase 5 — 64-bit self-host.**
Only after Phase 3 and the compiler's own type model is width-parameterized.
Port host PAL, seed, fixed point, memory. *Effort: very high.*

**Phase 6 — 16-bit DOS.**
Do not start as an extension. If pursued, design a separate 16-bit backend/
memory model, or scope it as 32-bit protected-mode DOS with an extender.
*Effort: very high / not recommended.*

### 8.2 Dependencies

- Target descriptor before any per-target code.
- Width/layout model before 64-bit codegen or 64-bit self-host.
- PAL and build recipe before cross-compile tests.
- Seed rotation after any compiler-language feature; new syntax cannot be
  used in `sf/src` before the seed understands it.
- 64-bit self-host after 64-bit cross-compile works.

### 8.3 File-level change list

The exact set depends on the phase; this is the full surface.

**CLI/orchestration**

- `sf/src/main.zig` — target/profile parsing, help, context threading.
- `sf/src/config.zig` — target descriptor if a shared config belongs there.
- `sf/src/module_registry.zig` — target polarity for conditional imports,
  replacing the single `target_is_windows` boolean.
- `sf/src/comptime_eval.zig`, `sf/src/lower.zig`,
  `sf/src/semantic_analyzer.zig`, `sf/src/parser.zig` — `@isWindows` and
  conditional-import handling; add target predicates if required.

**Type/layout/lowering**

- `sf/src/type_registry.zig` — primitive/pointer/slice/optional/`va_list`
  sizes, alignments, widths, C spellings, literal-fit ranges.
- `sf/src/type_resolver.zig` — layout math, `@sizeOf`/`@alignOf`/`@offsetOf`,
  optional/error-union layout.
- `sf/src/c89_plan.zig` — carry target facts into spelling (carrier widths,
  const carriers) if needed.
- `sf/src/lower.zig` — pointer/integer cast recording, literal facts,
  target-aware checks.
- `sf/src/lir.zig`, `sf/src/lir_opt_pass.zig`, `sf/src/spill_store.zig` — only
  if new IR instructions (e.g. `asm`) are added; otherwise unchanged.
- `sf/src/comptime_eval.zig` — target-width literal/`@sizeOf` folds.

**Async**

- `sf/src/async_analysis.zig`, `sf/src/async_frame_layout.zig`,
  `sf/src/async_state_machine.zig`, `sf/src/std_async.zig` — pointer-sized
  frame fields, `Context` header offsets, frame sizing/padding, frame
  save/restore; must move together to keep the compiler/runtime ABI in sync.

**C emission**

- `sf/src/c89_emit.zig` — pointer/int cast spelling, slice/optional/error-
  union emission, `va_list`, target build scripts, `stdcall` gating,
  `@intToPtr` cast width, prelude selection.
- `sf/src/emit_support.zig` — mirror every runtime/PAL change byte-for-byte
  (`scripts/check_emit_support.sh`).

**Runtime/PAL**

- `sf/src/include/zig_compat.h` — target width typedefs, pointer-width
  integer types, `Z98_ALIGN8` policy, `char` signedness.
- `sf/src/include/zig_pal.c` — target PAL branches, syscall/file/time/console,
  startup, trap.
- `sf/src/include/zig_nocrt.c` — Windows no-CRT only; no change for non-
  Windows.
- `sf/src/include/zig_runtime.c`, `sf/src/include/zig_runtime.h` — 64-bit
  helpers, `va_list`, target-specific builtins.
- `sf/src/include/net_prelude.h`, `std_os_prelude.h`,
  `std_time_prelude.h` — target includes/prototypes/layouts.
- `sf/src/c_exit.c` — exit path if target-specific.
- `sf/src/pal.zig` — compiler host PAL (file I/O, args, time, path, trap).
- `sf/src/std_file.zig`, `std_file_pal.zig` — syscall numbers, stat/timeval,
  seek/size.
- `sf/src/std_os.zig`, `std_os_pal.zig` — env/cwd/args.
- `sf/src/std_time.zig`, `std_time_pal.zig` — clock/timeval.
- `sf/src/std_net.zig` — byte order, socket ABI, `gethostbyname` return
  width.
- `sf/src/std_io.zig`, `std_stdin.zig`, `std_stdin_pal.zig` — if target
  console/stdio differs.
- New: target PAL C files / startup `.S` files if needed.

**Build/seed**

- `sf/src/c89_emit.zig` build-script emitters — per-target CC/flags/link.
- `scripts/seed/build_from_seed.sh` — remove hard `-m32`; target parameter;
  fixed-point recording.
- `scripts/seed/archive_seed.sh`, `release/seed/CHANGELOG.md` — seed rotation
  after compiler changes.
- `sf/scripts/memory_profile.sh` — target/budget probes if cross-run.

**Tests/goldens**

- Existing 32-bit corpus/goldens are not valid for 64-bit layout.
- Add per-target C compile probes, `@sizeOf`/`@alignOf`/slice/optional/
  `va_list` layout probes, pointer-roundtrip tests, async frame probes, and
  a small runtime smoke test per target.
- Add target-specific PAL probes (file/stat/time/socket) on real hardware or
  qemu.

**Docs**

- `sf/docs/tech_docs/Other_arch_supp.md` (this file), `INDEX.md`.
- `sf/docs/tech_docs/10_c_runtime.md`, `13_windows_support.md`,
  `08_c89_emission.md`, `12_async_coroutines.md`, `03_type_resolution.md` —
  truth-up if the work is implemented.

### 8.4 Risk register

| Risk | Likelihood | Impact | Mitigation |
|:--|:--|:--|:--|
| Silent layout corruption on 64-bit | High if done piecemeal | Critical | Do §4.2 as one change; add layout probes; don't ship until `@sizeOf`/`@alignOf` and struct offsets match the C compiler |
| Pointer truncation via `(unsigned int)` | High | Critical | Couple §4.3 to §4.2; add pointer round-trip tests on 64-bit |
| Async frame/`Context` ABI mismatch | High | Critical | Change compiler and `std_async` together; add frame-size/offset probes |
| `struct stat`/`timeval` wrong offsets | High per target | High | Probe layouts per ABI or avoid opaque offsets; test on real target/qemu |
| `char` signedness mismatch | Medium | Medium | Pin or audit `c_char`; test C string/sign paths |
| Seed/fixed-point divergence | High | High | Re-establish per target; record md5; use `-O0` for bootstrap determinism |
| New language feature not seed-compatible | High | High | Stage features until a seed understands them; prefer C helpers |
| 16 MB budget / 256 MiB pool | Medium | High | Configurable pool; measure on target; don't self-host on bare-metal without a plan |
| Cross-target goldens drift | Medium | Medium | Separate target goldens; explicit pass/fail; don't reuse x86 goldens |
| Toolchain/ABI mismatch (float ABI, LP64 vs ILP32) | Medium | High | Build all objects with one `-mabi`/`-mfloat-abi`; record it in the build script |
| Inline asm breaks C89 portability | Medium if added | High | Prefer C PAL helpers; if added, gate by target and document the extension |
| Performance regression from `-O0` | High | Medium | Release `-O2` once gates pass; measure, don't assume |
| Hardware unavailable for verification | High | Medium | Use qemu for Linux user-mode; label hardware results as pending |
| Scope creep into optimizing backend | Medium | High | Stay on C89 + C compiler; revisit only if performance is proven insufficient |

### 8.5 What would make this not worth doing

- **Only Win9x/z9play matters.** If the product goal is a Win9x demo and no
  other target has a user, the 64-bit work is not justified. The 32-bit
  ARM/RV32 cross-compile path is the only low-cost extension, and even that
  needs a PAL/goldens owner.
- **"Run x86 binaries on X" is the actual goal.** That is emulation/binary
  translation, explicitly out of scope. If the requirement is compatibility
  rather than native code, this report does not apply.
- **64-bit is required but the project insists on the 32-bit semantic model.**
  A 64-bit target with 32-bit `usize`/pointers is not a correct 64-bit port;
  it will truncate addresses. Either do the width model or stay 32-bit.
- **Bare-metal or 16-bit DOS is required.** Both need a different runtime/
  backend and a much smaller compiler. The current compiler's 256 MiB pool and
  16 MB budget make 16-bit self-host especially unattractive.
- **No hardware or qemu coverage.** Without target execution, the work is
  unverified cross-compilation. The project's gate culture should not accept
  "it compiles" as target support.
- **Inline asm is required everywhere.** If a target's C toolchain cannot
  express the needed operations and the project will not maintain a target
  PAL, the port is a compiler-backend project, not a C89 target profile.
- **Performance parity is the only goal.** The current C89 backend is simple
  and `-O0` by default; achieving parity may require a real optimizing
  backend or aggressive C flags. If the C compiler at `-O2` is not enough,
  the cost is a new backend, not a target profile.

## 9. Evidence and sources

### 9.1 Repo facts

| Claim | File:line |
|:--|:--|
| `usize`/`isize` 4 bytes, 32-bit width | `sf/src/type_registry.zig:337`, `:1146-1147` |
| `usize`/`isize` C spellings | `sf/src/type_registry.zig:544-545` |
| Pointer/many-pointer size 4 align 4 | `sf/src/type_registry.zig:750-753`, `:772-775` |
| Slice size 8; emitted `{ Elem *ptr; unsigned int len; }` | `sf/src/type_registry.zig:800`, `sf/src/c89_emit.zig:1726-1742` |
| i64/u64/f64 size 8 align 8 pinned | `sf/src/include/zig_compat.h:5-9`, `:29-30`, `:49`; `sf/src/c89_emit.zig:1699-1716` |
| Optional/error-union 4-byte tag/alignment math | `sf/src/type_resolver.zig:365-377` |
| `va_list` size 4 | `sf/src/type_registry.zig:1155` |
| `@sizeOf`/`@alignOf` read registry size/alignment | `sf/src/type_resolver.zig:1255-1273` |
| `usize` literal cap 4294967295 | `sf/src/type_registry.zig:2181` |
| `@ptrToInt` result `usize`; `@intToPtr` casts through `(unsigned int)` | `sf/src/c89_emit.zig:7949-7955`, `:3597-3603` |
| Only `@isWindows` target predicate | `sf/src/main.zig:650`, `sf/src/comptime_eval.zig:1579-1580`, `sf/src/lower.zig:6137` |
| POSIX `_llseek` 140 and i386 stat probe | `sf/src/std_file.zig:80-98`, `:206` |
| POSIX file externs | `sf/src/std_file_pal.zig:43-69` |
| Win32/POSIX PAL split | `sf/src/include/zig_pal.c:6-20`, `:241-348` |
| Compiler 16 MB budget; 256 MiB static pool; 64 MB default | `docs/sf/AGENTS.md:21-22`, `:99`; `sf/src/allocator.zig:247-248`, `:257-260`; `sf/src/main.zig:2043` |
| Async `Context` offsets and `std_async` comments | `sf/src/async_state_machine.zig:63-75`; `sf/src/std_async.zig:42-51`, `:59-60` |
| Seed build `gcc -m32` and fixed point | `scripts/seed/build_from_seed.sh:18-29`, `:91-102`, `:150-168` |
| Emitted build scripts only linux/mingw, `-m32`, `-O0` | `sf/src/c89_emit.zig:8556-8565`, `:8769-8795` |
| Windows no-CRT/profile split (reference) | `sf/docs/tech_docs/13_windows_support.md` §2-§7 |

### 9.2 External references

- **Arm AAPCS32** — https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst
  - Fundamental types: data pointer 4 bytes/4 align; double-word 8/8.
  - C mapping: `char` = unsigned byte, note "LDRB is unsigned".
  - Stack: "SP mod 8 = 0" at a public interface.
- **RISC-V psABI** — https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-abi.adoc
  - Defines ILP32/LP64 and the default ABIs.
- **RISC-V calling convention** — https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-cc.adoc
  - Integer register convention: `sp` 128-bit aligned at procedure entry.
  - C type tables: ILP32 `void *` 4/4, LP64 `void *` 8/8; `long` 4 vs 8.
  - "char is unsigned"; `va_list` section: same representation as `void *`;
    variadic rules.
- **x86-64 System V psABI** — https://github.com/hjl-tools/x86-psABI/blob/master/low-level-sys-info.tex
  - Scalar types: `signed long (LP64)` 8/8, pointer `any-type * (LP64)` 8/8.
  - `size_t` is `unsigned long` for LP64, `unsigned int` for ILP32.
- **Linux ARM syscall table** — https://github.com/torvalds/linux/blob/master/arch/arm/tools/syscall.tbl
  - `140 common _llseek sys_llseek`.
- **Linux generic syscall table** — https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/unistd.h
  - Header comment: "New architectures should use this file".
  - `#define __NR3264_lseek 62`; on 32-bit `__NR_llseek __NR3264_lseek`.
- **Linux x86-64 syscall table** — https://filippo.io/linux-syscall-table/
  - `lseek` is syscall 8; there is no `_llseek` entry on x86-64.
- **GCC extended asm** — https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html
  - "The `asm` keyword is a GNU extension."
  - "When writing code that can be compiled with `-ansi` and the various
    `-std` options, use `__asm__` instead of `asm`."
  - Operand/clobber/`volatile` semantics.
- **OpenWatcom C/C++ User's Guide** — https://open-watcom.github.io/open-watcom-v2-wikidocs/cguide.html
  - `WCC` is the 16-bit compiler; `WCC386` is the 32-bit compiler.
  - 16-bit memory models: small/medium/compact/large/huge; `zp{1,2,4,8,16}`
    structure packing.
  - `zl` suppresses library names/references (relevant to no-CRT builds).

### 9.3 Unverified

- Actual availability/version of each cross toolchain in this environment
  (no cross compilers were invoked).
- Exact AArch32/AArch64/RV32/RV64 `struct stat` and `struct timeval` offsets.
  These must be probed on the target ABI; the repo's current values are the
  i386/glibc probe in `sf/src/std_file.zig:82-98`.
- Exact OpenWatcom 16-bit type sizes/promotions beyond the documented memory
  models; the emitted C would need a probe.
- All performance expectations. No benchmark was run; the statements are
  qualitative and based on the data model and toolchain flags.
- Hardware behavior (Win9x/ARM/RISC-V boards). The project's existing status
  for Win9x is "design-verified; hardware verification pending"
  (`sf/docs/tech_docs/13_windows_support.md`); the same standard applies here.
