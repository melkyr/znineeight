# Win-hosted zig1 investigation — Phases 1–2 report

**Status: Phase 1 PASS. Phase 2a FAIL. Phase 2b FAIL. Investigation complete for phases 1–2; phases 3–7 still required.**

- Repo: `/workspace/znineeight`, branch `zig1_improvements`, HEAD `c13de0bc`
- Date: 2026-10-25
- Mode: investigation only; all probes under `/tmp/inv`; no production edits, no commits,
  no changes to `release/seed/*`, `run.err`, `.opencode/memory`, or the untracked P4 docs.
- Host: Linux, Wine 8.0 (Debian `8.0~repack-4`), `i686-w64-mingw32-gcc` GCC 12-win32,
  host gcc 12.2.0. Wine GUI-driver noise suppressed with `WINEDEBUG=-all` for the
  pass/fail runs; one `WINEDEBUG=+seh` diagnostic was used for the 2a trap.

## Artifacts and hashes

| Artifact | Path | md5 |
|---|---|---|
| Linux seed compiler (used in Phase 1) | `/tmp/seed_v121/zig1_5_clean` | `11de43a053bdde3be3ddc61caac31df6` |
| Seed tgz (uncommitted v121) | `release/seed/zig1-seed.tgz` | `38d3fb06ecd88b9f07e18f50b6139be4` |
| Win9x companion zip (uncommitted v121) | `release/seed/zig1_seed_w9.zip` | `3480f6a8a7d1edac3a43f2b34e422f7e` |
| Phase 1 hello exe | `/tmp/inv/hello/prog.exe` | `97381311cf2688b84df7e4046d3f361e` |
| Phase 1 lisp exe | `/tmp/inv/lisp/prog.exe` | `1d71a5bfba1fe8ee3e8314574b39d40d` |
| 2a zip-built compiler | `/tmp/inv/w9/zig1-seed-w9/zig1.exe` | `7d7b095770ff81f2522870ba643b497f` |
| 2b MinGW-built Linux-gen compiler | `/tmp/inv/genwin/zig1.exe` | `9033ebaa434e0bc80343be99da3b9b4c` |
| 2a diagnostic `-ffast -osw` compiler | `/tmp/inv/w9fast/zig1.exe` | `5100befbdc2187e0b88102b8960e1adb` |

Relevant generated C hashes:

| File | md5 |
|---|---|
| Phase 1 `/tmp/inv/hello/main_B90321E3.c` | `083d24ae4356cd8eceac4d68b7866380` |
| Phase 1 `/tmp/inv/hello/greetings_EE7AA80A.c` | `faef61aa138b3a22594b4c706a1114ca` |
| Phase 1 `/tmp/inv/lisp/main_E4A745E1.c` | `383c2df827c7417a04713912091750ba` |
| 2a zip `win/lexer_23F0DAD4.c` (`-fsafe`) | `447253daebf57cc669ef8e322c82d31b` |
| 2b `/tmp/seed_v121/gen` `lexer_23F0DAD4.c` (`-ffast`) | `d48c7cb11ab38a04aedbbea8f3a6110f` |
| 2a diagnostic `-ffast -osw` `lexer_23F0DAD4.c` | `d48c7cb11ab38a04aedbbea8f3a6110f` |

The 2a diagnostic `-ffast -osw` lexer C is byte-identical to the Linux `gen` lexer C
(`d48c…`); the shipped zip lexer C differs (`4472…`) because it is the `-fsafe` emission.

## Phase 1 — baseline: PASS

### Commands and output dirs

```bash
mkdir -p /tmp/inv/hello /tmp/inv/lisp /tmp/inv/logs
cd /workspace/znineeight
/tmp/seed_v121/zig1_5_clean -osw -o /tmp/inv/hello examples/z98/hello/main.zig
/tmp/seed_v121/zig1_5_clean -osw -o /tmp/inv/lisp  examples/z98/lisp_interpreter_curr/main.zig
```

- hello emit: rc=0. stdout only `Z98 Compiler 2026 (map: off)`; stderr empty.
  `/tmp/inv/hello` contains `main_B90321E3.c`, `greetings_EE7AA80A.c`, runtime/PAL C,
  headers, and the generated `build_target.sh`.
- lisp emit: rc=0. stdout `Z98 Compiler 2026 (map: off)`; stderr was 116
  `warning[3037]: potential null pointer dereference` lines and nothing fatal.
  `/tmp/inv/lisp` contains the 9 lisp module C/H pairs plus `std_io_05353D91.c` and
  the runtime/PAL C.

### Build

```bash
cd /tmp/inv/hello && sh build_target.sh mingw
cd /tmp/inv/lisp  && sh build_target.sh mingw
```

Both: rc=0, output `Building for mingw...` / `Built: prog.exe`.
The generated script names the default MinGW binary `prog.exe`, not `hello.exe`;
the brief's `wine hello.exe` was therefore run as `wine prog.exe`.
Build stderr was compiler warnings only (unused static runtime helpers etc.); no errors.

### Run under Wine

```bash
cd /tmp/inv/hello && WINEDEBUG=-all wine prog.exe
cd /tmp/inv/lisp  && printf '(+ 1 2)\n' | WINEDEBUG=-all wine prog.exe
```

| Program | rc | stdout | stderr | Verdict |
|---|---:|---|---|---|
| hello | 0 | `Hello, world!\n` | empty | PASS |
| lisp | 0 | hex `3e 20 33 0a 3e 20` = `> 3\n> ` | empty | PASS |

The lisp output includes its `> ` prompt; the expected result `3` is present.
**Phase 1 conclusion: PASS.** The Linux seed compiler emits valid `-osw` C for both
programs, MinGW compiles that C, and the resulting Win32 binaries run correctly under
Wine. This rules out the emitted C, the MinGW CRT compile, and the Wine runtime as the
cause of the Windows-hosted compiler failure.

## Phase 2a — Windows-target compiler C from the zip: FAIL

### Extract and build

```bash
rm -rf /tmp/inv/w9 && mkdir -p /tmp/inv/w9
cd /tmp/inv/w9 && unzip -q /workspace/znineeight/release/seed/zig1_seed_w9.zip
# zig1-seed-w9/win: 52 .c + 51 .h; zig1-seed-w9/lib: 48 entries (47 .zig + manifest.md5)
cd /tmp/inv/w9/zig1-seed-w9/win
i686-w64-mingw32-gcc -m32 -std=c89 -O0 -DZIG_WIN32 -I . -c *.c
i686-w64-mingw32-gcc -m32 *.o -o ../zig1.exe -lkernel32 -lwinmm -lwsock32
```

- Compile: rc=0, no `error:` lines. Stderr had 8 lines: one implicit `fwrite`
  declaration warning plus its note/context.
- Link: rc=0, no linker errors. `../zig1.exe` produced.
- `-DZIG_WIN_NT` was **not** needed; it was not used and both commands linked cleanly.

### Usage

```bash
cd /tmp/inv/w9/zig1-seed-w9
WINEDEBUG=-all wine zig1.exe
```

rc=0. The usage text went to stderr, starting `Z98 Compiler 2026 (map: off)` and
showing the `-osl` / `-osw [9x|nt]` options. Usage works.

### Compile hello: exact first failure

```bash
mkdir -p /tmp/inv/w9/zig1-seed-w9/examples/z98/hello
cp /workspace/znineeight/examples/z98/hello/main.zig \
   /workspace/znineeight/examples/z98/hello/greetings.zig \
   /tmp/inv/w9/zig1-seed-w9/examples/z98/hello/
mkdir -p /tmp/inv/w9/zig1-seed-w9/out_hello
cd /tmp/inv/w9/zig1-seed-w9
WINEDEBUG=-all wine zig1.exe -osw -o out_hello examples/z98/hello/main.zig
```

Result: **rc=3**. stdout contained the Wine crash banner and module/thread dump;
the fatal stderr line was:

```text
Z98 Compiler 2026 (map: off)
wine: Unhandled exception 0x80000003 in thread 24 at address 007E165C (thread 0024), starting debugger...
```

`out_hello/` contained **no files** (0 entries). A `WINEDEBUG=+seh` run confirmed
`code=80000003` at `addr=007E165C ip=007e165c`, i.e. the `int $3` in `pal_trap`
(`_pal_trap` at `0x7e161e`).

### 2a backtrace and trap location (corrects prior cnameDedupKey attribution)

`winedbg --gdb` gave the crash stack (top frames):

```text
#0  0x007e165d in pal_trap ()
#1  0x0059381d in zF_8EC79679_parseU64 ()
#2  0x005909d0 in zF_EF8134BD_lexerScanNumber ()
#3  0x0058dc43 in zF_B976BEC9_lexerNextToken ()
#4  0x006e691b in zF_7C3FD09B_parserPullOne ()
...
#22 0x00583787 in zF_EEBAC601_moduleRegistryParse ()
#23 0x00584af1 in zF_A46C0B58_moduleRegistryResol ()
#24 0x006a81c2 in zF_E2BA93CE_phase_ImportResolut ()
#25 0x006a6770 in zF_74055C03_runCompiler ()
#26 0x006a65e7 in zF_EA90E208_main ()
```

The return address `0x59381d` is immediately after the `call pal_trap` at
`0x593818` in `parseU64`. Disassembly at that site is the safe-mode guard for

```c
max_u64 = 0;
max_u64 -= 1;
```

i.e. `zig_overflow_flag_sub_u(max_u64, 1, 64)`, with `pal_trap()` when the subtraction
overflows. In the shipped zip C this is at
`/tmp/inv/w9/zig1-seed-w9/win/lexer_23F0DAD4.c:4345`/`4347`; the source is
`sf/src/lexer.zig:597-598`:

```zig
var max_u64: u64 = @intCast(u64, 0);
max_u64 -= 1;
```

This guard is deterministic: `max_u64` is zero and the subtraction is always
`0 - 1`. The trap therefore occurs on the **first integer literal lexed**, not in
`cnameDedupKey` and not after module emission. The zip C is the default `-fsafe`
emission, so this check is present. The working Linux seed compiler's C is `-ffast`
(no such guard), which is why Phase 1 does not hit it.

**Interpretation of 2a:** the shipped zip compiler traps because its compiler C was
emitted `-fsafe` and contains a checked underflow on an intentional wrapping
`max_u64 -= 1`. This is a compiler self-build profile/source issue, not a MinGW ABI
issue and not the `-osw` target emission itself.

### 2a diagnostic: `-ffast -osw` compiler C (clearly test-only)

To separate the safe-mode trap from the Windows-hosted compiler problem, the same
compiler source was emitted `-ffast -osw` and built with the same MinGW CRT recipe:

```bash
rm -rf /tmp/inv/w9fast && mkdir -p /tmp/inv/w9fast
cd /workspace/znineeight
/tmp/seed_v121/zig1_5_clean -ffast -osw -o /tmp/inv/w9fast sf/src/main.zig
cd /tmp/inv/w9fast && cp -r /tmp/seed_v121/lib ./lib
i686-w64-mingw32-gcc -m32 -std=c89 -O0 -DZIG_WIN32 -I . -c *.c
i686-w64-mingw32-gcc -m32 *.o -o zig1.exe -lkernel32 -lwinmm -lwsock32
mkdir -p out_hello
WINEDEBUG=-all wine zig1.exe -osw -o out_hello hsrc/main.zig
```

- Emit rc=0 (52 `.c`); compile rc=0; link rc=0.
- The `-ffast -osw` lexer C is byte-identical to the Linux `gen` lexer C
  (`d48c7cb11ab38a04aedbbea8f3a6110f`), confirming the only lexer difference from the
  zip is safe vs fast.
- `hello` compile: **rc=2**, out dir empty, first error:

```text
Z:\tmp\inv\w9fast/lib/std_async.zig:259:10: error[3060]: no field or member function named 'state' in type
    if (t.state != TaskState.done and t.state != TaskState.cancelled) {
          ^^^^^
```

So removing the safe-mode trap does not make the zip-style compiler work; it exposes
the same std/type-resolution failure seen in 2b.

## Phase 2b — Linux-target compiler C built with MinGW: FAIL

### Copy and build

```bash
rm -rf /tmp/inv/genwin && mkdir -p /tmp/inv/genwin
cp /tmp/seed_v121/gen/*.c /tmp/seed_v121/gen/*.h /tmp/inv/genwin/   # .o excluded
cp -r /tmp/seed_v121/lib /tmp/inv/genwin/lib
cd /tmp/inv/genwin
i686-w64-mingw32-gcc -m32 -std=c89 -O0 -DZIG_WIN32 -I . -c *.c
i686-w64-mingw32-gcc -m32 *.o -o zig1.exe -lkernel32 -lwinmm -lwsock32
```

- 52 `.c` + 51 `.h` copied; all `.o` excluded.
- Source tree md5 aggregate (`md5sum *.c *.h | md5sum`): `3cf1e14faa85329adbb0e5f78b0ad07d`.
- Compile: rc=0, no `error:` lines; only warning was implicit `fwrite` declaration
  (same class as 2a). No missing `write`/stdio symbols.
- Link: rc=0, no linker errors; `/tmp/inv/genwin/zig1.exe` produced.
- Usage under Wine: rc=0, same usage text on stderr.

### Compile hello: exact first failure

```bash
mkdir -p /tmp/inv/genwin/hsrc /tmp/inv/genwin/out_hello
cp /workspace/znineeight/examples/z98/hello/main.zig \
   /workspace/znineeight/examples/z98/hello/greetings.zig \
   /tmp/inv/genwin/hsrc/
cd /tmp/inv/genwin
WINEDEBUG=-all wine zig1.exe -osw -o out_hello hsrc/main.zig
```

Result: **rc=2**. No stdout. stderr begins:

```text
Z98 Compiler 2026 (map: off)
Z:\tmp\inv\genwin/lib/std_async.zig:259:10: error[3060]: no field or member function named 'state' in type
    if (t.state != TaskState.done and t.state != TaskState.cancelled) {
          ^^^^^
Z:\tmp\inv\genwin/lib/std_async.zig:259:40: error[3060]: no field or member function named 'state' in type
    if (t.state != TaskState.done and t.state != TaskState.cancelled) {
                                        ^^^^^
Z:\tmp\inv\genwin/lib/std_async.zig:262:21: error[3060]: no field or member function named 'count' in type
```

Further errors include `std_debug.zig:28`/`:64` `no field or member function named
'ptr'` / `'len'` on slices. `out_hello/` contains only `.zig1_*.tmp` files; no module
C/H was emitted.

The first failure is an analyzer/type-registry field-resolution failure on a struct
(`Task.state`) and on slices (`ptr`/`len`), not a lexer trap and not a MinGW link
failure. It matches the prior `-ffast` Windows dump failure on `std_debug.zig:64`
(`tag.len`) and is the same first failure as the 2a `-ffast -osw` diagnostic.

## Conclusion for phases 1–2

1. **Phase 1 PASS.** The Linux seed compiler's `-osw` C for hello and lisp compiles
   with MinGW and runs under Wine with correct output. The emitted-C path and the
   MinGW/Wine runtime are sound.
2. **Phase 2a as shipped FAILS for a different reason than previously recorded.**
   The zip compiler C is `-fsafe`; `parseU64` contains a checked underflow on the
   intentional wrapping expression `max_u64 -= 1` (`sf/src/lexer.zig:597-598`,
   generated C `lexer_23F0DAD4.c:4345-4347`). The first integer literal lexed traps
   in `pal_trap`. This is deterministic and host-independent in the generated C; it
   is a compiler **self-build profile/source** problem, not `cnameDedupKey`, not
   MinGW ABI, and not the `-osw` emitter.
3. **Phase 2b FAILS.** The same compiler source emitted `-ffast` (Linux `gen`) and
   built with the MinGW CRT gets past lexing but mis-resolves struct/slice fields in
   `std_async.zig` / `std_debug.zig` (`no field or member function named 'state'`,
   `'ptr'`, `'len'`). The 2a `-ffast -osw` diagnostic fails identically, so this is
   not specific to the Linux-target or Windows-target compiler C.
4. **Combined interpretation:** both compiler builds fail under the Windows-hosted
   path, but at two different layers. The deeper, non-packaging problem is the
   **Windows-hosted compiler's analyzer/type registry behavior when its C is built
   with MinGW** (category "both fail → compiler C/ABI under MinGW"). The shipped
   `-fsafe` profile additionally masks that with an earlier safe-mode trap. Fixing
   the profile alone will not make `hello` compile; fixing the Windows-hosted
   compiler alone will still leave the `-fsafe` trap unless the lexer underflow or
   the seed profile changes.
5. **The v121 zip must not be committed as working.** The prior report's claim that
   the 2a trap is the `cnameDedupKey` multiply-overflow guard is not what this build
   shows; the exact 2a trap is `parseU64`'s `max_u64 -= 1` subtraction guard.

## Focus for phases 3–7

- **Phase 3 (layout conformance):** still the main hypothesis for the 2b failure.
  Compare `@sizeOf`/`@offsetOf` and struct field tables under Linux gcc vs MinGW,
  especially slice/struct/type-registry types used by the analyzer. The first
  observable failure is `Task.state` in `std_async.zig:259`; prioritize the type
  registry and struct/slice representation.
- **Phase 4 (binary diagnosis):** use `-g -O0` MinGW builds, break in the analyzer's
  field-resolution/type-registry code on the first `std_async` access, and separately
  break `parseU64` to confirm the safe-mode underflow. Capture the bad slice/type id.
- **Phase 5 (differential flags):** test `-mms-bitfields` vs `-mno-ms-bitfields`,
  `-malign-double`, `-O0/-O2`, `-fno-strict-aliasing`, `-fwrapv`, and
  `-DZIG_WIN32` vs `-DZIG_WIN_NT`. Also test `-fsafe` vs `-ffast` on the same
  compiler C to document the two layers.
- **Phase 6 (reproducers):** minimal `std_debug`/`std_async` field-access reproducer,
  slice-parameter `.len` reproducer, and a no-std/`@sizeOf`/`@offsetOf` probe.
- **Phase 7 (verdict):** decide whether the Windows-hosted analyzer issue is
  MinGW-specific or common, whether the `max_u64 -= 1` safe-mode trap is a compiler
  source bug and/or a seed-profile bug (the working seed is `-ffast`), and only then
  decide the seed artifact. Keep the v121 zip uncommitted until then.

## Caveats

- No MSVC or OpenWatcom probe was run; MSVC/OW behavior remains a prediction.
- No production fixes, commits, or seed-artifact changes were made.
- 2a's `-DZIG_WIN_NT` variant was not needed for linking and was not run.
- 2b's `-DZIG_WIN32` build is the requested differential; it is a Windows-hosted
  build of the Linux-target compiler C, not a claim of Win9x validity.
- Logs are under `/tmp/inv/logs/` (not committed).
