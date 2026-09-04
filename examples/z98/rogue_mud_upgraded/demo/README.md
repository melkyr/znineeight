# rogue_mud_upgraded — demo feeds

This directory holds the closeout demo feeds for the upgraded rogue MUD
(single-player entry `main.zig`):

- `canonical_feed.txt` / `canonical_expected.txt` — the Task 1 baseline (`q`;
  boot text only). Output is fully deterministic (md5 `3fb6709e…`).
- `canonical_move_feed.txt` / `canonical_move_expected.txt` — the Task 1
  move baseline (`d`/`l`/`q`; exercises a render + look + quit). Fully
  deterministic (md5 `b3c5b0e1…`).
- `demo_feed.txt` / `demo_expected.txt` — the Task 5 observable demo surface
  (`i`/`q`). Deterministic; golden is the 3×-verified capture (md5 `7361d248…`).

Neither canonical feed contains `i`.

## The `i` info command

`main.zig` registers a local-input prong `'i', 'I' => demoInfo()` in the
single-player input switch. `demoInfo()` (module-level helper next to
`injectInt`) prints a deterministic, layout-only info block (no
position/timing dependence) plus two module-level helper fns it calls:

| Output line | What it demonstrates | Contract |
|---|---|---|
| `off Entity.hp=… off Entity.x=… size Entity=… bits bool=… off Room_t.h=…` | `@offsetOf`/`@sizeOf`/`@bitSizeOf` over `entity_mod.Entity` and `room_mod.Room_t` | recorded actuals (see below) |
| `bitcast(i32,0xFFFFFFFF)=-1` | `@bitCast` of `u32 0xFFFFFFFF` to `i32` | `-1` |
| `container-of=true` | `@fieldParentPtr` over the module-scope `Local{tag:u8,payload:u32}` struct | `true` |
| `render_calls=…` | the cross-module `ui_mod.render_calls` counter (Task 4) | 0 on the demo feed (no render before input) |
| `110` / `20` | `demoRangeClassifier` case-range switches: `(3,'x')` → `1...5`+`'a'...'z'` = `10+100`, `(7,'!')` → `6...9` only = `20` | `110` then `20` |

The `Local` container-of struct is module-scope (not a local struct binding)
because zig1 does not support local struct type declarations (AMENDMENT 3).

Recorded layout actuals for the current build (`/tmp/fx_subfolder/zig1` ref,
commit `…Task-5`): `off Entity.hp=4 off Entity.x=8 size Entity=16 bits bool=1
off Room_t.h=3`. Field offsets (`hp=4`, `x=8`, `Room_t.h=3`) and `bits bool=1`
match the hand contract; `size Entity=16` (not the hand-computed `12`) is the
program's compile-time constant and equals the emitted C `sizeof` — zig1 widens
the trailing `active: bool` struct field to `int` storage, and
`EntityType`'s `union(enum)` tag lowers to a `unsigned int`, so the natural
layout is 4(typ) + 2+2(hp/max_hp) + 1+1(x/y) + 4(active int) = 16. The
compiler is the source of truth; this value is stable 3× and layout-coupled —
regenerate `demo_expected.txt` if the struct layout ever changes.

## Demo feed and golden

`demo_feed.txt` is:

```
i
q
```

The `i` prints the info block above; `q` quits. Its stdout is the original
program's boot bytes (the same 6 lines / 221 bytes as the `q` canonical feed)
followed by the `i` info block — nothing else is printed between boot and the
`q` exit, because both keys are already pending on stdin when the loop starts
(no timeout render fires, so `render_calls` stays 0). Verified: the first
221 bytes of `demo_expected.txt` are byte-identical to
`canonical_expected.txt`.

Determinism: 3× harness runs (`scripts/closeout/run_upgraded.sh
/tmp/fx_subfolder/zig1 examples/z98/rogue_mud_upgraded/main.zig
demo/demo_feed.txt`) produce byte-identical stdout (md5 `7361d248…`,
RUNRC=0 each); `demo_expected.txt` is that capture. Unlike the lisp `(address)`
demo, nothing in this demo prints a runtime address, so there is no PIE/ASLR
variance — the golden is a whole-file byte gate.
