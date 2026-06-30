# Z98 Compiler Quick Reference

## Bootstrap Build (zig0 → zig1)

```bash
cd /workspace/znineeight
rm -rf out_release && mkdir -p out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1
```

Debug build:
```bash
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1
```

## LISP refactor testing building zig1 pipeline

How the LISP / sema-refactor work actually builds and tests `zig1` (differential vs `zig0`).
`zig1` is fully determined by **`sf/src/main.zig` (+ its imports)** and **`sf/build/zig0`** — the
output directory and gcc *warning* flags do NOT change the resulting compiler.

**1. Build zig1 from the current source (isolated output dir):**
```bash
OUT=/tmp/z1
rm -rf "$OUT" && mkdir -p "$OUT"          # always clean: stale .c/.h cause false Slice_* type errors
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig   # emits 35 per-module .c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c -o "$OUT/zig1"
```
Debug build (for GDB): append `-g -O0 -Wno-implicit-function-declaration` to the gcc line.

- zig0 emits **35 per-module `.c` files** into `$OUT` (gcc globs `"$OUT"/*.c`; there is no single `zig1.c` object).
- The bootstrap `-Iinclude` above is **stale** (no root `include/` dir exists) — omit it. `-Wno-pointer-sign`
  only mutes warnings. Gate on the `error:` count, never warnings.
- Always build from the **repo** `sf/src/main.zig`, never a `/tmp` `git worktree` (those hold older source = a different/older zig1).

**2. Compile + run an example with that zig1:**
```bash
"$OUT/zig1" --dump-c89 examples/lisp_interpreter_curr/main.zig > /tmp/lisp.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Isf/src/include \
    /tmp/lisp.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/lisp 2>&1 | grep -c 'error:'
# add sf/src/include/net_runtime.c for mud_server; use `gcc -c` (no link) for no-main repros
```

**3. Differential / gate (what "passing" means):**
- `zig0` is the reference oracle: `./sf/build/zig0 -o DIR/out.c repro.zig` (emits per-module `repro.c` in `DIR`).
- Refactor gate: `man/gol/mud/lisp --dump-c89` **byte-identical** to baselines + `lisp` `error:` count == `12` + self-host gcc `0` errors.
- Current baselines (HEAD `c3d61919`): `man c379bd194d73d06a9dbac02431a82b2d`, `gol 8aa260ce9d467995f657e46552712fb1`,
  `mud 35051e34cd0ba883a08ff60569ae262f`, `lisp 74a721caef6f121fe6d744870dbb7c37`; `zig1` ≈ `621772` bytes.
- Markers: `"$OUT/zig1" --markers --dump-c89 <entry> 2>mk` then `grep -ac '^PREFIX' mk`
  (watch prefix collisions: `FS:C`/`FS:CK`, `IFST:K`/`IFST:K2` → use the `:N` variant).

## Compile Examples with zig1

```bash
./out_release/zig1 --dump-c89 examples/mandelbrot/mandelbrot.zig > out.c
./out_release/zig1 --dump-c89 examples/game_of_life/main_lin.zig > out.c
./out_release/zig1 --dump-c89 examples/mud_server/main.zig > out.c
```

With markers (diagnostic output to stderr):
```bash
./out_release/zig1 --markers --dump-c89 examples/mud_server/main.zig > out.c 2>diag.txt
```

## GCC Compile + Link

```bash
gcc -m32 -std=c89 -Wno-pointer-sign \
  -Iout_release -Isf/src/include \
  out.c \
  sf/src/include/zig_runtime.c \
  sf/src/include/zig_pal.c \
  -o app
```

## Build mud_server (full cycle)

```bash
cd /workspace/znineeight
rm -rf out_release && mkdir -p out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1
./out_release/zig1 --dump-c89 examples/mud_server/main.zig > /tmp/mud.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  /tmp/mud.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c \
  sf/src/include/net_runtime.c -o /tmp/mud
```

Check error count:
```bash
gcc ... 2>&1 | grep -c "error:"
```

## Build and Run Tests

```bash
cd /workspace/znineeight && ./sf/scripts/build_test.sh
```

## Debug with GDB on zig1

### Build with debug symbols
```bash
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1
```

### Find function in generated C
```bash
grep -n "function_name_part" out_release/semantic_analyzer.c | head -5
```

### Find line for breakpoint
```bash
grep -n "keyword" out_release/semantic_analyzer.c | head -20
```

### GDB with batch script
```bash
cat > /tmp/gdb.txt <<'EOF'
set pagination off
break out_release/semantic_analyzer.c:LINENO
run examples/mud_server/main.zig > /dev/null 2> /dev/null
print varname
print another_var
continue
quit
EOF
gdb -batch -x /tmp/gdb.txt --args ./out_release/zig1 --dump-c89
```

### Filter output to variable values
```bash
gdb -batch ... 2>&1 | grep "^\$"
```

### Common breakpoints in resolveSwitchExpr (line numbers may shift after edits)
| Purpose | Approx C Line | Look for |
|---------|---------------|----------|
| Function entry | search for `static unsigned int zF_...manticAnalyzerResolveSwitchExpr` | Declaration line + 14 = unified init |
| Loop start | search for `__loop_0_start` in function body | `if (!(i < prongs.len))` |
| `unified = bt` (i==0) | ~2225 | `un_box[0] = bt;` or `unified = bt;` |
| `bt == unified` check | ~2227 | `bt == un_box[0]` or `bt == unified` |
| TYPE_VOID return | ~2267 | `return zC_..._TYPE_VOID;` |
| Loop exit | ~2275 | `__loop_0_end:` label |

### Verify zig0 C89 variable corruption theory
Replace suspect scalar variable with `[1]u32` box array. If behavior unchanged → corruption theory disproven. Example:
```zig
// Before: var unified: u32 = 0;
// After:  var un_box: [1]u32 = [1]u32{0};   // use un_box[0] everywhere
```

### itoa-based diagnostic markers — use palMarkerWriteInt
```zig
// BEFORE (15+ local vars, zig0 C89 budget risk):
var m: []const u8 = "LABEL:n"; pal_mod.markerWrite(m);
var nb: [10]u8 = undefined; var nl = itoa_mod.itoa(val, nb[0..]);
var ns: usize = @intCast(usize, 9) - @intCast(usize, nl);
pal_mod.markerWrite(nb[ns..@intCast(usize, 9)]);
var e: []const u8 = "\n"; pal_mod.markerWrite(e);

// AFTER (2 local vars, safe everywhere):
// IMPORTANT: zig0 C89 cannot pass string literal directly as []const u8 argument.
// Always use named var before markerWriteInt call.
var m: []const u8 = "LABEL:n"; pal_mod.markerWriteInt(m, val);
```
palMarkerWriteInt defined at pal.zig:99-106. Uses internal 12-byte buf + itoa_mod.itoa.
Output: `LABEL:n<value>\n`.

### Marker extraction — use `grep -a`, NOT `strings`

**CRITICAL:** `strings` strips null bytes and can silently drop entries.
Always use `grep -a` (binary-as-text) on the raw stderr file.

```bash
# Capture markers to file
./out_release/zig1 --markers --dump-c89 examples/mud_server/main.zig > out.c 2>/tmp/markers.bin

# Extract specific markers
grep -a "^PREFIX:" /tmp/markers.bin

# Count entries (reliable)
grep -a -c "^PREFIX:" /tmp/markers.bin

# Sort unique numeric values
grep -a "^PREFIX:" /tmp/markers.bin | sed 's/PREFIX: *//' | sort -n

# Multi-prefix extraction preserving order
grep -a "^IFST:\|^PBD:\|^EBLK:" /tmp/markers.bin
```

### Common marker labels in sema.zig (all use markerWriteInt)

| Marker | Meaning | Example |
|--------|---------|---------|
| STX:N | resolveExpr entry (node_idx) | STX:N   453 |
| STX:K | resolveExpr entry (kind) | STX:K    24 |
| STX:R | resolveExpr entry (result type) | STX:R    10 |
| A4:N/K/R | STB stored (non-VOID result) | A4:N   453 |
| STB:N/R | STB confirmation | STB:N   453 |
| BLK:N | resolveStmtDepth block handler entry | BLK:N   727 |
| BLK:C | Block child count | BLK:C    11 |
| BCK:B | Block child — block node_idx | BCK:B   727 |
| BCK:I | Block child — index | BCK:I     0 |
| BCK:N | Block child — child node_idx | BCK:N   345 |
| BCK:K | Block child — child kind | BCK:K    30 |
| EBLK:N | resolveExpr block handler entry | EBLK:N  753 |
| IFST:N | if_stmt handler — if_stmt node | IFST:N  427 |
| IFST:C | if_stmt handler — child_1 node | IFST:C  426 |
| IFST:K | if_stmt handler — child_1 kind | IFST:K   79 |
| IFST:2 | if_stmt handler — child_2 node | IFST:2    0 |
| IFST:K2 | if_stmt handler — child_2 kind | IFST:K2   0 |
| WST:N | while_stmt handler — node_idx | WST:N   726 |
| WST:K | while_stmt handler — body kind | WST:K    76 |
| WST:D | while_stmt handler — depth | WST:D     3 |
| PBD:N | resolveSwitchExpr prong body node | PBD:N   753 |
| PBD:K | resolveSwitchExpr prong body kind | PBD:K    76 |

## DISPROVEN zig0 C89 Bugs

Theories that were investigated and ruled out. Do NOT re-investigate.

| Theory | Disproof | Date |
|--------|----------|------|
| **C89 variable budget / stack slot reuse** — local variables corrupted at depth 3+ | Markers with wrong slice offset (`buf[0..vlen]`) produced garbled output, not codegen corruption. After fixing `palMarkerWriteInt`, all markers reliable at ALL depths. Verified with `[1]u32` box array test. | 2026-06-12 |
| **Struct-by-value return corruption** — `Slice_u32` returned by value gets corrupted at caller | 1024-element stress test: 510+ consecutive `getSlice()` calls alternating short(2)/long(63), nested outer-survives-inner, same-start-different-count. EXIT=0. zig0 C89 struct return IS correct. | 2026-06-12 |
| **Parser block truncation** — `parserParseBlock` drops children | Block 829 (.Go prong body) correctly has 8 children (payload start=273, count=8). `extra_children[273..281]` data is correct. Parser creates correct AST. | 2026-06-12 |
| **`astStoreGetExtraChildren` computation** — start/count wrong | GDB verified: payload=17891336, start=273, count=8, `start+count-start=8` in function. Returns `__make_slice_u32(items+273, 8)` correctly. | 2026-06-12 |
| **`astStoreAddExtraChildren` corruption** — appends wrong data | GDB verified: `extra_children[273..281]` = [758,771,784,797,810,818,822,828] — correct AST node indices. | 2026-06-12 |
| **TokenKind value mismatch between zig0 and C header** | C header enum values match Z98 enum order exactly (kw_var=54, kw_const=53, kw_return=68, kw_if=63). Verified via GDB + C define grep. | 2026-06-12 |
| **`strings` vs `grep -a`** — `strings` silently drops marker entries | Confirmed: `strings` strips null bytes. Use `grep -a "^PREFIX:" /tmp/markers.bin` instead. | 2026-06-12 |

## zig0 C89 Compilation Errors — Import/Missing Module Checklist

**DO NOT blame zig0 C89 limitations first.** When zig0 emits `use of undeclared identifier`, `unable to infer type`, or similar compile errors, follow this checklist IN ORDER before considering zig0 bugs:

1. **Missing `@import`** — `grep "const X = @import" <file>` vs `grep "X\." <file>`. If used but not imported, add the import.
2. **Wrong module alias** — files use different aliases for the same module: `lower.zig` → `const pal`, `semantic_analyzer.zig` → `const pal_mod`, `type_registry.zig` → `const pal_mod`. Check: `grep "const pal\|@import.*pal" <file>`.
3. **Stub file (never imported before)** — the file may have pre-existing bugs that were hidden because `main.zig` never imported it. Check: `grep "@import.*<filename>" sf/src/main.zig`.
4. **THEN consider zig0 limitations** — only after (1)-(3) are exhausted.

**Examples of false zig0-blaming (2026-06-27):**
- `pal_mod.markerWriteInt()` in `lower.zig` → "undeclared identifier" → blamed on C89 variable budget. Actual: `lower.zig` imports `const pal`, not `pal_mod`.
- `ast_mod.astStoreGetExtraChildren()` in `comptime_eval.zig` → "undeclared identifier" → blamed on type inference. Actual: `ast_mod` never imported in file (stub, never compiled before).

See AGENTS.md §9.1.1 for full rules. Memory [97cffe29](mnemoria).

## Non-Issues: Warnings That Are NOT Bugs or Blockers

Symptoms that look like failures but are EXPECTED. Do NOT treat them as
regressions, do NOT open blockers for them, and do NOT spend investigation
time chasing them.

| Symptom | Why it is NOT a bug | What to actually check |
|---------|---------------------|------------------------|
| **game_of_life: literal ANSI / terminal-clear escape codes appear in the output** | `system("clear")` writes terminal escape sequences to stdout. When output is piped or captured (not a live TTY), those sequences show up as literal bytes. **Both zig0 AND zig1 behave this way** — it is terminal behavior, not codegen. | Whether the patterns (glider, blinker, block, beehive, LWSS) and the `Generation: N` lines render correctly. The presence of escape codes is irrelevant. |
| **gcc *warnings* (as opposed to errors)** | Build commands intentionally suppress noise via `-Wno-long-long`, `-Wno-pointer-sign`, `-Wno-implicit-function-declaration`. Any remaining gcc *warnings* do not affect correctness of the produced binary. | Only the `error:` count matters. Gate builds on `gcc ... 2>&1 \| grep -c "error:"` equal to `0`. |

**Differential rule:** `zig0` is the reference oracle. A `zig1`-compiled
example is "correct" when its runtime output matches `zig0`'s output, modulo
the terminal-clear artifact described above.

## Memory Recall (DEPRECATED — use mnemoria instead)

> **DEPRECATED.** The old logfmt memory system has been migrated to `mnemoria`.
> See [Memory Recall via Mnemoria](#memory-recall-via-mnemoria) below.
> Logfmt files are preserved at `.opencode/memory/*.logfmt` for reference but
> are no longer the primary query mechanism.

Memory files local: `/workspace/znineeight/.opencode/memory/YYYY-MM-DD.logfmt`

### Read specific date:
```
Read filePath="/workspace/znineeight/.opencode/memory/2026-06-10.logfmt"
```

### Search across all dates:
```bash
grep -r "keyword" /workspace/znineeight/.opencode/memory/
```

### File format (logfmt):
```
ts=2026-06-10T01:14:11.343Z type=plan scope=project content="the memory text"
```

Types: decision, learning, preference, blocker, context, pattern
Scope: project (most common), build, api, database, etc.

### Read recent date files for current session context:
```bash
ls /workspace/znineeight/.opencode/memory/*.logfmt | sort -r | head -5
```

## Memory Recall via Mnemoria

Memories have been migrated from logfmt files to the `mnemoria` CLI tool.
Store at `.opencode/memory/` (managed by mnemoria; do NOT edit manually).

### Query Commands

```bash
# Stats
mnemoria --path .opencode/memory stats

# Search by keyword (semantic)
mnemoria --path .opencode/memory search "keyword"

# Ask a question (RAG-based)
mnemoria --path .opencode/memory ask "What issues were found?"

# Recent timeline
mnemoria --path .opencode/memory timeline --limit 10

# Filter by agent (legacy memories stored under two agents):
mnemoria --path .opencode/memory search --agent legacy-zni "keyword"
mnemoria --path .opencode/memory search --agent legacy-deleted "keyword"

# View timeline for specific agent
mnemoria --path .opencode/memory timeline --agent legacy-zni --limit 5
```

### Legacy Agent Names

| agent_name | Content | Count |
|---|---|---|
| `legacy-zni` | Active memories from pre-migration logfmt system | 1,498 entries |
| `legacy-deleted` | Previously deleted/forgotten memories, retained for reference | 431 entries |

### Type Mapping (logfmt types → mnemonia entry_type)

| logfmt type | mnemonia entry_type |
|---|---|
| learning | discovery |
| decision | decision |
| plan | intent |
| blocker | problem |
| pattern | pattern |
| context | discovery |
| preference | discovery |

### Adding New Memories

```bash
mnemoria --path .opencode/memory add \
  --agent my-agent-name \
  --type discovery \
  --summary "Brief description" \
  "Detailed content here"
```

> **Full reference:** `docs/sf/AGENTS.md` Section 9 covers all conventions, agent naming, and usage patterns in detail.

## Code Review via Superpowers Skill

Trigger the requesting-code-review skill when auditing completed changes.

**Manual review (in-session, plan mode):** `skill: requesting-code-review`
1. Obtain diff: `git diff` or `git diff BASE..HEAD`
2. Audit against template at `~/.cache/opencode/packages/superpowers@.../superpowers/skills/requesting-code-review/code-reviewer.md`
3. Checklist: plan alignment, code quality, architecture, edge cases, tests
4. Categorize: Critical / Important / Minor
5. Give clear verdict: Ready to commit / With fixes / Do not merge

**Subagent review (build mode):** Dispatch general-purpose subagent with `BASE_SHA`/`HEAD_SHA`, fill template from `code-reviewer.md`. Reviewer inspects `git diff BASE..HEAD`, returns Strengths + Issues + Assessment.

**Key principles:** Review early/often. Fix Critical before proceeding, Important before merge. Categorize by actual severity — not everything is Critical. Acknowledge strengths before listing issues.

## zig0 Runtime h/c Architecture

The zig0 bootstrap compiler has a two-tier runtime that supports **both**
the compilation of zig1 itself (zig0 → C89 → gcc link) and the programs
compiled *by* zig1 (zig1 → C89 → gcc link). Understanding this split is
critical when adding new runtime functions or debugging linker errors.

### File Layout

| Path | Role | Used by |
|------|------|---------|
| `src/include/zig_compat.h` | C89 type definitions (`i64`, `u64`, `ZIG_INLINE`, `ZIG_UNUSED`) | All C89 output |
| `src/include/zig_runtime.h` | **Inline** bootstrap helpers (`__bootstrap_X_from_Y` casts, panic, print) | All generated `.c` files |
| `src/runtime/zig_runtime.c` | **Non-inline** runtime (arena alloc, sleep, platform console) | Linked at build |
| `$OUT/zig_runtime.h` | **Copy** of `src/include/zig_runtime.h`, emitted by zig0 via `--header-priority-include` | gcc `#include` resolution |
| `$OUT/zig_runtime.c` | **Generated** runtime .c by zig0 (includes the header) | Linked into zig1 binary |

### How zig0 Copies Headers

zig0 `--header-priority-include` copies key headers from `src/include/`
into the output directory alongside the generated `.c` files. This is why
the gcc link command (`gcc $OUT/*.c`) works without `-I` — each `.c` can
`#include "zig_runtime.h"` relative to its own directory.

To make a new header available, place it in `src/include/` — zig0 copies
all `.h` files from that directory.

### `__bootstrap_X_from_Y` Cast Helpers (Inlines)

Zig0's `@intCast(u32, i64_expr)`, `@intCast(u8, usize_expr)`, etc.
emit calls to `__bootstrap_DSTTYPE_from_SRCTYPE(source)`. These are
**inline** functions defined in `src/include/zig_runtime.h` (lines 99–180).
They use `ZIG_INLINE ZIG_UNUSED` → `static` in C89, so each generated
`.c` file gets its own copy — **no linker symbol needed**.

**Pattern** (all helpers follow this):
```c
ZIG_INLINE ZIG_UNUSED u32 __bootstrap_u32_from_i64(i64 x) {
    if (x < 0 || x > (i64)4294967295U) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (u32)x;
}
```

**Win9x safety:** These functions are **pure arithmetic + panic call**.
They use no C standard library (no `stdio.h`, `string.h`, `stdlib.h`,
`malloc`, etc.). The types (`i64`, `u64`, `u32`, etc.) are defined
per-compiler in `zig_compat.h`:
- **MSC (win9x):** `typedef unsigned __int64 u64`
- **Watcom:** `typedef unsigned long long u64`
- **gcc:** `typedef unsigned long long u64`

The `ZIG_INLINE` macro expands to `static __inline` (MSC), `static __inline__`
(gcc), or `static` (other). The `ZIG_UNUSED` macro suppresses
`-Wunused-function`.

### `src/runtime/zig_runtime.c` (Non-Inline Symbols)

For functions that **cannot** be inline (arena alloc, sleep, platform I/O),
implementations live in `src/runtime/zig_runtime.c` as regular linkable symbols.
This file is compiled separately and linked into the final binary. Note that
**not** all bootstrap helpers need a non-inline version — the inline helpers
in the header are sufficient for most casts.

Some helpers exist in BOTH places (inline header + .c definition) as a
safety fallback — see `__bootstrap_u16_from_usize` (line 286 of the .c).

### Adding a New Runtime Definition

**For a new `@intCast` target pair (inline)**:
1. Add to `src/include/zig_runtime.h` following the pattern:
```c
ZIG_INLINE ZIG_UNUSED DST_T __bootstrap_DST_from_SRC(SRC_T x) {
    if (<range check>) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (DST_T)x;
}
```
2. Rebuild zig1 — zig0 copies the updated header to `$OUT`.

**For a non-inline function (linkable symbol)**:
1. Declare in `src/include/zig_runtime.h` (as `extern` or `ZIG_INLINE`).
2. Define in `src/runtime/zig_runtime.c` as a regular C function.
3. Ensure the zig1 build or zig0 runtime emission includes the `.c`.

**Common link error:** `undefined reference to '__bootstrap_U64_from_I64'`
→ This exact helper is **missing** from `src/include/zig_runtime.h`.
Add it per the inline pattern above. (Added 2026-06-29 for enum(u8) support.)
