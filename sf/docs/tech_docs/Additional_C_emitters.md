# Additional C emitters: Borland bcc32 / Digital Mars dmc

**Status:** research note, read-only. No code or build-script changes were made.
**Date:** 2026-11-18.
**Scope:** what is required to add Borland C++ 5.5 (`bcc32`/`ilink32`) and
Digital Mars C/C++ 8.5x (`dmc`) as C89 backends for Z98-emitted C, alongside
MinGW, OpenWatcom, and MSVC. z9gb is the driving example, but the notes cover
the shared compiler/runtime layer.

## Bottom line

- CRT-linked `bcc32` and `dmc` support is a contained change: compiler-macro
  branches, new build scripts, and a small DirectX-header shim.
- No-CRT support is a real port: compiler-specific import thunks, custom
  entry/startup, linker entry rules, and 64-bit helper libraries.
- The main technical risk is not syntax. It is `@offsetOf` and struct layout:
  the z9gb dynarec folds numeric offsets at Z98 compile time, and `Cart` has
  `i64` fields before `rom0_off`/`romx_off`. If a compiler aligns 64-bit
  fields differently, dynarec reads the wrong fields.
- Recommended order: Borland CRT first, DMC CRT second, no-CRT last.

## 1. Compiler-macro layer

The emitted `sf/src/include/zig_compat.h` is generated from
`sf/src/emit_support.zig`; change the source of truth and regenerate the
include snapshots. Do not hand-edit the generated headers or snapshots.

| Site | Required change | Class |
|:--|:--|:--|
| `sf/src/include/zig_compat.h:10-16` | Add `__BORLANDC__` and `__DMC__` to the default 8-byte alignment branch (`Z98_ALIGN8`). Verify each compiler really aligns `i64/u64/f64` to 8. | macro |
| `sf/src/include/zig_compat.h:18-33` | Add compiler branches for `z64`/`zu64` and `Z98_I64_C`/`Z98_U64_C`. Borland: `__int64`/`unsigned __int64` with `i64`/`ui64`; DMC: verify `long long`/`unsigned long long` with `LL`/`ULL`. | macro |
| `sf/src/include/zig_compat.h:73-79` | Add `__BORLANDC__`/`__DMC__` to `Z98_STDCALL` as `__stdcall`. The current fallback is `__attribute__((stdcall))`, which bcc32 does not accept. | macro |
| `sf/src/emit_support.zig:18-95` | Apply the same three changes in the generator. Regenerate `sf/src/include/zig_compat.h` and snapshots. | source |
| `scripts/check_emit_support.sh:56-61` | The 8/8 byte-equality gate must be refreshed after regeneration. | test |
| `scripts/gen_emit_support.sh:55-70` | Regeneration path. | test/build |

`c89_emit.zig` already routes 64-bit literals and stdcall typedefs through
these macros (`1932-1958`, `1446-1490`, `1820-1822`, `2028-2031`,
`6399-6401`), so no direct per-compiler spelling should be added there.

## 2. Runtime and no-CRT shim

| Site | Required change | Class |
|:--|:--|:--|
| `sf/src/include/zig_nocrt.c:8-13` | Add bcc/dmc FILE/stdio branch. For CRT builds this file's normal body is not used. | source |
| `sf/src/include/zig_nocrt.c:18-22` | Add bcc/dmc `_iob`/`__iob` equivalent, or remove symbol-name coupling. | source |
| `sf/src/include/zig_nocrt.c:29-39` | GCC inline-asm import thunks for `__imp____acrt_iob_func` must not compile for bcc/dmc. | source |
| `sf/src/include/zig_nocrt.c:41-49` | `z98_stream_handle` needs a bcc/dmc stream-identity branch. | source |
| `sf/src/include/zig_nocrt.c:143-149` | GCC asm `__imp___time32` thunk: same treatment. | source |
| `sf/src/include/zig_nocrt.c:151-156` | Dummy-definition/typedef branch: include bcc/dmc as needed. | source |
| `sf/src/emit_support.zig:271-330, 413-425` | Apply the same changes in the generator. | source |
| `sf/src/include/zig_pal.c:7-23` | Windows path is already `<windows.h>` only; POSIX headers are under `#ifndef _WIN32`. No change for Win32. | none |
| `sf/src/include/zig_pal.c:162-177` | Trap register capture is GCC/i386 only. bcc/dmc get zero-filled context; acceptable, or add compiler-specific asm. | source (small) |
| `sf/src/include/zig_pal.c:180-188` | `int3` branch: bcc likely accepts `__asm { int 3 }`; dmc needs its own form. Otherwise abort path. | source (small) |
| `sf/src/include/zig_pal.c:454-527` | No-CRT `mainCRTStartup`: CRT builds do not compile this block; no-CRT needs bcc/dmc entry/link rules. | source/build |
| `sf/src/emit_support.zig:1088-1111, 1380-1450` | Same PAL changes in the generator. | source |

## 3. CRT vs no-CRT

### CRT-linked (recommended first target)

- Compile without `ZIG_NO_CRT`; `zig_nocrt.c` compiles only its dummy branch, so
  the GCC asm import thunks are not involved.
- `zig_pal.c` uses the normal PAL; GCC-only trap/startup blocks are excluded.
- Borland: `bcc32` in C mode, `ilink32` PE console target, Borland startup
  object plus static runtime (`cw32.lib`), and `import32.lib`.
- DMC: `dmc` driver with static runtime/startup, or `link` with the 8.5x
  `snn.lib`/`sn.lib` plus import libs.
- Emitted `main` is always present (`c89_emit.zig:3303`); no custom entry.

### No-CRT (defer)

- Entry is emitted `mainCRTStartup` only under `_WIN32 && ZIG_NO_CRT`
  (`zig_pal.c:454-527`).
- MinGW uses `-nostdlib -Wl,-e,_mainCRTStartup`; MSVC uses
  `/NODEFAULTLIB /entry:_mainCRTStartup@0`; OpenWatcom uses
  `option nodefaultlibs`/`option start=`.
- Borland `ilink32` has no MSVC-style `/entry`; a startup object or `.def`
  equivalent is needed. DMC's `/ENTRY`/no-default-lib support must be verified.
- Both still need 64-bit multiply/divide helpers. MinGW gets them from
  `-lgcc`; MSVC/OWC get helper members from the CRT; bcc/dmc no-CRT must link
  their own helper members.
- `zig_nocrt.c` import thunks are GCC/ELF-style asm and must be replaced or
  avoided.

## 4. DirectX headers

Do not reuse the standalone MinGW DirectX headers with bcc32/dmc. They depend
on MinGW/w32api semantics and GCC helpers (`_mingw_dxhelper.h` uses
`__extension__` and anonymous-union macros; `ddraw.h` pulls `objbase.h` and
GUID machinery). bcc32 rejects GCC attributes; DMC compatibility is unverified.

Vendor DirectX SDK headers are MSVC-oriented (`__declspec(uuid)`,
`CINTERFACE`, `DEFINE_GUID`, anonymous unions). BC5.5 may accept parts; DMC is
less certain.

Current z9gb does not need a full SDK port:

- `std_ddraw_pal.zig:22-23` includes `<windows.h>`/`<ddraw.h>`, but DDraw COM
  vtables, GUID bytes, `DDSURFACEDESC2`, and constants are local mirrors
  (`std_ddraw_pal.zig:92-...`, `201-300`, `326-329`); `ddraw.dll` is loaded
  dynamically (`468-474`).
- `std_dsound_pal.zig:34-36` includes `<windows.h>`, `<dsound.h>`,
  `<mmsystem.h>`; WAVEFORMATEX/WAVEHDR/DSBUFFERDESC are local, and
  `DirectSoundCreate`/waveOut are declared locally (`173-186`).
- `std_dinput_pal.zig:22` includes only `<windows.h>`; GUIDs and data formats
  are local (`90-...`, `223-227`).
- `std_gfx_pal.zig:26-27` includes `<ddraw.h>` but uses local DDraw types.

Minimal path: use the compiler's `<windows.h>` and supply a small include
directory with stub `ddraw.h`, `dsound.h`, `mmsystem.h` that include
`<windows.h>` (or vendor headers when available). Add it before system includes
in the bcc/dmc scripts. No `ddraw.lib`/`dsound.lib`/`dinput8.lib` is needed;
imports are `kernel32`, `user32`, `gdi32`, `winmm`, and `wsock32` when net.

If future std code starts using real DirectX header types, a vendor SDK
port/compat headers become mandatory.

## 5. stdcall, dynarec, and layout

`Z98_STDCALL` must be real `__stdcall` for bcc32/dmc. This is not cosmetic:

- Dynarec glue type is `extern "stdcall"` (`dynarec.zig:21`).
- Windows glue epilogue emits `ret 4` (`dynarec.zig:250-255`).
- Helper calls do not clean the stack on Windows because helpers are stdcall
  (`x86.zig:545-560`, `564-583`, `1512-1523`); helper definitions are
  `extern "stdcall"` (`helpers.zig:3, 67-87`).
- COM vtables and Win32 callbacks also depend on it.

Name decoration differs between MSVC/Borland/DMC; do not mix objects from
different compilers, and use each compiler's own import libraries.

`@offsetOf` is folded to a numeric constant at Z98 compile time
(`comptime_eval.zig:1440-1489`), not emitted as C `offsetof`. Emitted structs
use natural layout (`c89_emit.zig:1648-1695`) with `Z98_ALIGN8` on 64-bit/f64
carriers (`1932-1958`). The C compiler's layout must match Z98's model.

Risk sites:

- `Cpu` offsets (`x86.zig:46-57`, `dynarec.zig:32-33`): `cycles` is `u64` and
  last; probably safe.
- `Bus`/`Page` offsets (`x86.zig:59-68`, `dynarec.zig:34-36`): fields occur
  before APU `u64` state; probably safe.
- **`Cart` offsets** (`dynarec.zig:37-38`): `rom0_off`/`romx_off` come after
  `Rtc` `i64 anchor`/`fixed_unix` (`cart.zig:29-42`). If bcc32/dmc align 64-bit
  fields to 4, these offsets move and dynarec reads/writes the wrong fields.
- General: any emitted struct with `i64/u64/f64` fields can move.

Mitigation: pin alignment for bcc/dmc; add a generated C layout probe comparing
Z98 `@offsetOf`/`@sizeOf` constants with C `offsetof`/`sizeof`; keep the z9gb
`--dynarec` vs `--no-dynarec` framebuffer parity test. Compile emitted `.c` as
C, not C++: `zig_compat.h:51` only defines `bool` etc. outside `__cplusplus`;
C++ `bool` is 1 byte and breaks layout.

## 6. Build-script emission

Add four emitters near the existing MSVC/OWC/MinGW ones and register them in
`emitBuildScripts` (`c89_emit.zig:9752-10324`, call site `10279-10324`):

- `build_bcc_nocrt.bat` / `build_bcc_crt.bat`
- `build_dmc_nocrt.bat` / `build_dmc_crt.bat`
- optional aliases matching the existing alias pattern.

Mirror the existing shape:

- Hardcode `prog.exe`; log every command and stdout to `00.txt`; keep
  `:z98_fail`/`:z98_done`; CRLF; command.com-safe; `if errorlevel 1 goto`.
- CRT scripts: no `ZIG_NO_CRT`. No-CRT scripts: `ZIG_NO_CRT` plus compiler
  entry/link rules.
- Compile all reachable module `.c` plus `zig_runtime.c`, `zig_pal.c`,
  `zig_nocrt.c`, `c_exit.c`.
- Libs: `kernel32`, `winmm`; add `wsock32` when net, `user32`/`gdi32` when
  gfx; no DirectX import libs.

Borland specifics:

- `bcc32`, C mode, compile-only `-c`, `-I.`, defines
  `-D_WIN32 -DZIG_WIN32 -DWINVER=0x0410 -D_WIN32_WINNT=0x0410
  -D_CRT_SECURE_NO_WARNINGS -D_CRT_NONSTDC_NO_DEPRECATE`, `-O2`, alignment
  matching 8-byte model.
- `ilink32` PE console target; CRT startup object; no MSVC `/entry`.
- `bcc32 @z98_cc.rsp` / `ilink32 @z98_link.rsp` if 5.5 supports them; otherwise
  explicit lines plus a chunked link.
- Libraries: `import32.lib` + `cw32.lib` for CRT; verify winmm/wsock32/user32/
  gdi32 coverage.

DMC specifics:

- `dmc -c ...` (or driver one-shot), C mode, same defines, `-I.`, `-O2`,
  alignment matching 8-byte model.
- `link` or the `dmc` driver; CRT static `snn.lib`/`sn.lib`; verify no-CRT
  `/NOD`/`/ENTRY` support.
- Response files if supported; otherwise explicit compile lines and a
  response/chunked link.
- Libraries: DMC Win32 import libs (`win32.lib` and/or specific ones); no DX
  import libs.

Command-line length: existing scripts already split object sets/use response
files because command.com is limited. Preserve the 900-char non-REM line rule
from `gate_win_compat.sh`.

`build_target.sh` is Linux/MinGW only; bcc32/dmc are Windows-hosted. No Linux
cross target is realistic without Wine/Windows.

## 7. Tests, gates, dump pins

- `scripts/check_emit_support.sh:56-61`: refresh after `emit_support.zig`
  changes.
- The 8-pin `--dump-c89` table (`docs/sf/QUICK_REF.md:468-490`) should not
  change from compat/header/build-script work because stdout dumps do not
  include support headers or build scripts; verify.
- Seed/fixed point: changing `emit_support.zig` changes compiler source; follow
  the seed model and rotate at closeout (`docs/sf/AGENTS.md:480-505`,
  `docs/sf/QUICK_REF.md:33-58`).
- `scripts/compiler/gate_win_compat.sh:396-398` and per-toolchain checks near
  `333-390`: add new scripts and shape checks.
- `scripts/compiler/gate_crlf.sh:68-71, 138`: add new `.bat` names.
- `scripts/seed/archive_seed.sh:222-225, 251-295, 409-414`: if shipping in the
  Win9x zip, add required/removed lists and README text.
- Add bcc/dmc build/run gates. They are Windows-hosted; realistically
  operator-run like MSVC/OWC, which are design-verified only in-repo
  (`sf/docs/tech_docs/13_windows_support.md:144-147`). Linux CI can only run
  them under Wine with a prepared toolchain.
- Import gate: `scripts/win32_cross/check_win9x_imports.sh` uses
  `i686-w64-mingw32-objdump`, which can inspect any PE32; extend the whitelist/
  profile for bcc/dmc CRT imports. The 9x profile still rejects `msvcrt.dll`.
- z9gb: parameterize `scripts/win32_cross/cross_nocrt.sh` or add tier wrappers;
  keep the dynarec/no-dynarec framebuffer hash parity
  (`examples/z98/z9gb/tests/tier_win32.sh:318-401`). That is the best
  end-to-end detector of `@offsetOf`/stdcall breakage.
- `scripts/win32_cross/stdcall_callback/host.c:42-44` uses GCC inline asm to
  measure ESP; make it portable or add bcc/dmc host variants.
  `run_stdcall_callback.sh:64-86` assumes GCC/objdump.
- Compile-RSS 16 MB gate: header/build-script changes are tiny; rerun z9edit/
  z9gb gates (`docs/sf/QUICK_REF.md:394-401`,
  `examples/z98/z9edit/tests/tier_edit_gui.sh:191-212`).

## 8. Risk and effort

| Compiler | CRT effort | No-CRT effort | Overall risk | Rough days |
|:--|--:|--:|:--|--:|
| Borland C++ 5.5 `bcc32` | low-medium | medium-high | medium | 3-6 |
| Digital Mars 8.5x `dmc` | medium | medium-high | medium-high | 4-8 |

Recommended order:

1. Common compat layer: `__BORLANDC__`/`__DMC__` in `zig_compat.h`, regenerate
   snapshots. (0.5-1 d)
2. Borland CRT console + build scripts: hello/stdio first, import gate, then
   z9gb GUI. (2-4 d)
3. DMC CRT: same gates. (2-4 d)
4. Layout/ABI hardening: layout probe for `@offsetOf`/`@sizeOf`, dynarec ABI
   fixture, z9gb dynarec tier. (1-2 d)
5. No-CRT for each compiler: startup/entry, import thunks, helper libs.
   (2-4 d each)

Borland is the era-authentic, best-documented Win9x toolchain and supports
`__int64`/`__stdcall`; DMC has better C99/long-long support but less certain
Win32/DirectX header vintage. CRT first avoids `zig_nocrt.c` entirely.

## 9. Potential non-starters

1. **64-bit alignment/layout.** If bcc32 or dmc cannot pin 8-byte alignment for
   `i64/u64/f64`, struct layout diverges. z9gb can be patched around `Cart` by
   reordering/repacking fields, but general Z98 layout support would need a
   real fix. This is the main gating risk.
2. **Strict 9x import gate.** If the bcc/dmc static CRT pulls `msvcrt.dll` or
   non-whitelisted DLLs, the CRT path is not a valid 9x profile; no-CRT then
   becomes mandatory and inherits its linker/helper risks.
3. **No-CRT linker/entry.** Borland `ilink32` lacks MSVC-style `/entry`; DMC
   may lack a clean no-default-lib/entry mode. If no startup object/.def or
   helper path works, no-CRT is blocked for that compiler.
4. **C++ mode.** Compiling emitted `.c` as C++ changes `bool` to 1 byte and
   breaks layout. Force C mode.
5. **DirectX headers** are not a non-starter: current z9gb uses local mirrors
   and dynamic loading; stub headers work. Only future real DX-type use would
   force a vendor SDK header port.

No non-starter found for CRT-linked z9gb support on either compiler, assuming
8-byte-aligned 64-bit scalars can be pinned.

## 10. Evidence and open questions

- The report is based on source inspection only. There is no local bcc32 or dmc
  installation, so no compiler probe was run.
- Verify on the target: exact bcc32/dmc flags, response-file support, CRT library
  names, `import32.lib` coverage, `/ENTRY`/no-default-lib support, and 64-bit
  alignment.
- If a probe shows a different alignment, the `Cart` workaround may still let
  z9gb build, but it does not close the general layout issue.
- This note does not authorize code changes. It is a requirements inventory for
  a future plan.
