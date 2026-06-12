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
var m: []const u8 = "LABEL:n"; pal_mod.markerWriteInt(m, val);
```
palMarkerWriteInt defined at pal.zig:99-106. Uses internal 12-byte buf + itoa_mod.itoa.
Output: `LABEL:n<value>\n`.

## Memory Recall (when queries return stale results)

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
