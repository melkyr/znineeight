# Task 9 Phase 1 Report — generated fallback + module splits

Status: complete. Phase 2 (render decoupling) intentionally not started.

## Content single source

- Added `undtool --emit-fallback <outdir>` backed by `fallback_emit.zig`. It
  loads `data.z98` (never the compiled fallback), requires a successful load,
  and writes `<outdir>/fallback_rows.zig` deterministically.
- Generated `fallback_rows.zig` contains explicit-typed arrays for `DEFS`
  (19 `def.CreatureDef`), `RULES` (7 `behavior.Rule`), `TOOLS`, `UPGRADES`,
  `COSMETICS`, `ZONE_COST`, `ZONE_IS_BOSS`, `ENCOUNTERS` (Z1–Z3 populated,
  Z4–Z8/D empty), and the exported role/stat/family/grudge/part/phase
  vocabulary. No id definitions owned by `def.zig` were reintroduced.
- `creatures_t1.zig` and `tables_t1.zig` now consume `fallback_rows.zig` and
  keep their public API (`DEFS`, `defAt`, `defCount`, `rules`, `rows`, `tools`,
  `upgrades`, `cosmetics`, `zoneCost`, `zoneIsBoss`, override behavior).
  Hand-authored row builders/rows were deleted.
- `tests/tier_m9_px.sh` regenerates twice to `$OUT/fallback_rows.zig` and
  `$OUT/fallback_b`, proves determinism, and `cmp`s the first against the
  checked-in module.

## Module splits (behaviour-preserving)

- `render_text.zig`: cell canvas, `msgLine`, `speedRevealed`, tool status,
  modal/help copy and text-block helpers. `render_term.zig` and
  `render_art.zig` import it.
- `fight_rules.zig` + `fight_tools.zig`: derived-stat/effect/threshold math and
  equipped-tool predicates. `fight.zig` keeps the action state machine and
  forwards the public API.
- `data_scan.zig` + `data_load.zig`: scanner and loader. `data.zig` is the hub
  with forwarding wrappers and the public `g_tables`/`err_line` state.
- `save_scan.zig` + `save_io.zig`: save read path and image builder/CRC
  verifier. `persist.zig` is the hub and keeps the `fs_*` fault-injection seams
  and temp/bak/rename lifecycle.

Z98 note: aliases to functions (`pub const f = sub.f`) emit invalid C globals in
this compiler, so hubs use thin forwarding wrappers. Values/arrays still alias
directly.

## Final file sizes (lines)

| file | lines |
|---|---:|
| render_term.zig | 854 |
| render_text.zig | 367 |
| fight.zig | 707 |
| fight_rules.zig | 251 |
| fight_tools.zig | 22 |
| data.zig | 121 |
| data_scan.zig | 113 |
| data_load.zig | 1256 |
| persist.zig | 152 |
| save_scan.zig | 601 |
| save_io.zig | 295 |
| fallback_rows.zig (generated) | 1394 |

`data_load.zig` remains the large loader (schemas + parsers + dump); `data.zig`
itself is now a 121-line hub. LOC warnings only, no failures.

## Verification

- `TIER_M9 PASS 65 passed / 0 failed` from a fresh `OUT`, including nested
  M8 → M7 → … → M1.
- All `--dump-grid` M8 terminal goldens and the art/perf goldens byte-identical.
- `--emit-fallback` deterministic over two runs and `cmp`-equal to the checked-in
  file.
- `tier_edit` PASS with lexer md5
  `dcc81009e9a36c86e4d90e104c439871` (3x).
- `quality_smells.sh` PASS 5/0/12 warnings.

## Concerns

- `data_load.zig` is still 1256 lines; a future pass could move dump/schema
  tables into `data_dump.zig`/`data_parse.zig` if stricter LOC targets apply.
- Function forwarding wrappers are required by the Z98 alias limitation noted
  above; they duplicate signatures only, not bodies.
