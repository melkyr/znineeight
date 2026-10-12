# mud_server — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `bf5d3636`

**MD5 (`--dump-c89`):** `fd0fdaa42a419b0e72cfdb3226a54c4a` [updated: 2026-08-13]
(Re-baselined 2026-08-13 F6 REVIEW: `emitSocketOptPtrValue` null-coalesce (commit `25fb7ce1`)
changes the emitted `select` — optional fd args now `(NAME.has_value ? NAME.value : NULL)`.
Previous `3abbcd5c…` (post-migration) stale. mud_server is NOT an MD5 gate per the operator.)
(Re-baselined 2026-08-13 F6: the 12 `plat_*` externs + `plat_fd_set` in `main.zig` → `std_net`
(local `std_net.zig` copy), `net_runtime.h` cInclude + `net_runtime.c` link REMOVED — the F6
builtin-emitted socket C replaces it. Runtime output byte-identical to pre-F6 (verified by
diff of pre-migration vs migrated socket interaction: "MUD server listening on port 4000",
welcome + look/north responses identical; mud_server is NOT an MD5 gate per the operator).
Per F-5 AMENDMENT B the gate is runtime behavior, not byte-identity. Previous `ecd40869…` stale.)
(Re-baselined 2026-08-08 F4: `std_debug.zig` `__bootstrap_print` extern → `std.io.print` (local
`std.zig`/`std_io.zig` copies). Runtime output byte-identical to pre-F4, per F-5 AMENDMENT B.
Previous `4644ad13…` stale.)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/mud_server/main.zig -o build/mud_server
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/mud_server/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
MUD server listening on port 4000
```
(then timeout)

## Notes
Multi-file: `main.zig` imports `std.zig`, `util.zig`, and `std_net.zig` (local copy of
`sf/src/std_net.zig`). **[F6 2026-08-13:** the 12 `plat_*` externs + `plat_fd_set` are replaced
by `std_net` calls; `net_runtime.c` link REMOVED — the F6 builtin-emitted socket C replaces it.
Socket interaction re-verified (python client: welcome + look/north responses identical to the
pre-migration build; the "north → You cannot go that way." behavior is pre-existing, unchanged
by F6).]**
[F4 2026-08-08: `std_debug.zig` `__bootstrap_print` extern → `std.io.print` via local `std.zig`/`std_io.zig` copies. Local `std.zig` = `io` + `debug` (NO `arena` re-export — mud_server/rogue_mud don't use `std.arena`, and importing std_arena in the rogue_mud build exposes a pre-existing module-instance≥1 struct-type emission bug).]
