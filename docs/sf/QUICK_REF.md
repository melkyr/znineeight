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
