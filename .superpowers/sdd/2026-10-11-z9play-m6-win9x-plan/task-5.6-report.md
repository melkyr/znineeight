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

---

## Fix round 1

### Investigation: optional/error-union layout

The original report claimed the `+4` tag steps in
`sf/src/type_resolver.zig:365-377` were 32-bit assumptions and that the tag
"must become 8 bytes where payload alignment is 8." That was wrong. The tag is
emitted as C `int`, and the layout formula pads rather than widening the tag.

**Tool:** `/tmp/t55/zig1_5_clean`
(md5 `b299b4b435e624d0ddbd2edde681cbc3`, identical to `/tmp/t54`).
**Command:** `-ffast --dump-c89 --output-dir <dir> <probe>.zig`.

Probe source:

```zig
const S = struct { a: u64 };
const E = error{ Foo };

var g_opt_u64: ?u64 = null;
var g_opt_ptr: ?*void = null;
var g_opt_struct: ?S = null;
var g_eu_u64: E!u64 = 0;
var g_eu_ptr: E!*void = null;
var g_eu_struct: E!S = undefined;

pub fn main() void { }
```

Emitted `zig_special_types.h` definitions (verbatim, names retained):

```c
typedef struct { zT_79FAE712_u64 value; int has_value; } zT_BBEE1AC1_Opt_11;
typedef struct { void* value; int has_value; } zT_AFEBC946_Opt_25;
typedef struct { zT_D60C1322_S value; int has_value; } zT_B2EBCDFF_Opt_22;
typedef struct { union { zT_79FAE712_u64 payload; int err; } data; int is_error; } zT_3F70E806_EU_11;
typedef struct { union { void* payload; int err; } data; int is_error; } zT_D67AD017_EU_52;
typedef struct { union { zT_D60C1322_S payload; int err; } data; int is_error; } zT_44732E7C_EU_22;
```

The tag field is `int has_value` / `int is_error`, emitted at
`sf/src/c89_emit.zig:1761` and `:1785`.

A second probe used `@sizeOf` in value position (array-size position rejects
with `error[3050]`, an existing `@sizeOf` fold limitation, not a layout
result). The compiler emitted these constants:

```text
?u64         16
?*void        8
?struct{u64} 16
E!u64        16
E!*void       8
E!struct{u64} 16
```

Compiling the emitted header with the host C compiler produced:

```text
int=4 voidp=4 u64=8 S=8          # gcc -m32
?u64 size=16 value@0 tag@8
?*void size=8 value@0 tag@4
?S size=16 value@0 tag@8
E!u64 size=16 payload@0 err@0 is_error@8
E!*void size=8 payload@0 err@0 is_error@4
E!S size=16 payload@0 err@0 is_error@8

int=4 voidp=8 u64=8 S=8          # gcc -m64
?u64 size=16 value@0 tag@8
?*void size=16 value@0 tag@8
?S size=16 value@0 tag@8
E!u64 size=16 payload@0 err@0 is_error@8
E!*void size=16 payload@0 err@0 is_error@8
E!S size=16 payload@0 err@0 is_error@8
```

**Conclusion:** the tag is 4 bytes on both ILP32 and LP64. `?u64`, `?S`,
`E!u64`, and `E!S` are already 16 bytes with tag offset 8 on both ABIs. Only
pointer-containing optional/error-union types differ: 8 bytes in the current
Z98 model vs 16 bytes in LP64 C, because the registry still models pointers as
4 bytes. Fixing pointer width makes the existing formula correct; the tag must
**not** be widened to 8 bytes.

**Doc change:** replaced the claim in §2.3 item 3; added §2.7 with the probe
source, emitted structs, `@sizeOf` constants, `sizeof`/`offsetof` table, and
audit recommendation; updated §1.2, §2.5, §3.1, §4.2, and §9.1 accordingly.

### Other fix-round items

1. **`@intCast`/`-fsafe` width coverage:** added §3.2.1. `-fsafe` lowers to
   `int_cast_checked` only for narrowing/sign-changing casts
   (`sf/src/lower.zig:6586-6610`), maps to
   `zig_cast_checked_s/u((zu64)src, src_width, src_signed, dst_width)`
   (`sf/src/c89_emit.zig:7544-7570`), and the helper already supports
   `dw == 64` (`sf/src/include/zig_runtime.h:258-283`). The registry must
   report width 64 and widen the `usize` literal cap; `-ffast` omits checks.
   Arithmetic overflow uses `*_with_overflow` + `check_trap{kind=6}`
   (`sf/src/lower.zig:905-940`). Legacy `std_checked_cast_*` are
   upper-bound-only and not emitted (`sf/src/include/zig_runtime.h:157-170`).
2. **`leU32At` cite:** corrected to `sf/src/std_file.zig:117-123`.
3. **Build-script scope:** corrected to the emitted POSIX/mingw
   `build_target.sh` (`sf/src/c89_emit.zig:8555-8599`), with the `-osw`
   MSVC/OpenWatcom `.bat` emitters cited separately
   (`sf/src/c89_emit.zig:8601-8738`, `:8769-8826`).
4. **External citations:** added AAPCS64 `va_list` (3 pointers + 2 ints =
   32 bytes on LP64), x86-64 SysV `va_list` (24 bytes), and DOS 640 KiB /
   real-mode 64 KiB segment / 1 MiB address-space sources with quotes.
5. **`m68k?`:** removed from the target descriptor example.
6. **`gethostbyname`:** reworded as a generic LP64 issue for RV64, AArch64,
   and x86-64, not an RV64-only issue.
7. **Tests:** added per-target checked-cast/overflow boundary probes and the
   `-ffast` wrap/truncation counterpart to the file-change list.

### Fix-round concerns

- The probe verifies the host C compiler (`gcc -m32`/`-m64`) layouts, not a
  cross target ABI. Target `struct stat`/`timeval` offsets remain unverified.
- `@sizeOf` on optional/error-union is usable in value position but not in
  array-size position (`error[3050]`). This pre-existing fold limitation
  should be tracked separately if `@sizeOf(?T)` is needed at comptime.
- No source/test changes; docs only. `run.err`/`run.out`/`progress.md` left
  alone.
