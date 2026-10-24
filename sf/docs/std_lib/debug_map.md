# Debug map — `.z98dbg.*` sidecars

| | |
|---|---|
| **Producer** | `zig1 -d` / `--debug` (opt-in) |
| **Consumer** | `z9dbg` (map reader + session layer) |
| **Location** | next to the root-module C output, named `<root-stem>.z98dbg.*` |
| **Default** | OFF — no sidecars, no emitted-C change |

## Overview

The debug map is the compiler-to-debugger contract added in P3-M1. It is a
**compiler-development tool**, not part of the default output: without `-d` the
compiler emits exactly the same `.c`/`.h` set it emitted before the feature.

`-d` writes three files beside the primary output:

| File | Contents |
|:--|:--|
| `<stem>.z98dbg.syms` | source symbols `(kind, src_line, src_name, module_stem, src_file)` |
| `<stem>.z98dbg.lines` | emitted-C line runs grouped per output file: `(src_line, out_start, out_count)` |
| `<stem>.z98dbg.cnames` | optional source-name → C-identifier map (`zF_…`) |

The formats are little-endian, versioned (`version == 1`), and length-prefixed;
`map_reader.zig` validates counts, offsets, and exact EOF before use. A missing
`.cnames` is not an error (it only limits backtrace names).

## Quick start

```sh
zig1 -d --output-dir out examples/z98/hello/main.zig
# out/main_<HASH>.c/.h plus out/main_<HASH>.z98dbg.{syms,lines,cnames}
```

`-d` without `--output-dir` is a clean error (`rc=2`, no C, no map). The map is
written next to the root module's C stem and honours `--output-dir`.

## Usage contract

- **Source lines** — a source line may map to several emitted-C runs; the
  debugger plants an `int3` at every machine address of every run (M3 caps:
  4096 addresses/line, 65536 machine breakpoints, 1024 spans/line, with a
  diagnostic instead of silent truncation).
- **Path matching** — every file string is normalized before comparison:
  `\` → `/`, an `X:` drive prefix and a leading `./` are stripped, matching is
  by basename or path suffix, and ASCII case is folded when the debugger runs on
  Windows.
- **No `#line`** — the emitter still writes none. The sidecar supplies the
  source mapping; generated C remains ordinary C89.
- **Cost** — the M1 measurement (`-q -ffast`, 3 runs) is ≈0.2 MB RSS on small
  programs and ≈880 KiB on the largest function set (z9torr); no-`-d` runs
  allocate and scan nothing.

## Limits

- The map is a line/symbol map, not a variable-location format: `dump variables`
  prints registers, the current frame, and mapped globals (spec §7).
- Async rows are function-declaration granular in v1.
- Sidecar paths are compiler-build-relative source paths; moving sources breaks
  display, not the address math.
- The debugger reads DWARF 2/3/4 plus embedded COFF (MSVC `/Z7`) and DWARF-in-PE
  (mingw/OpenWatcom). PDB/CodeView and DWARF 5 are out of v1.

See `sf/docs/std_lib/z9dbg.md` for the debugger commands and build recipes.
