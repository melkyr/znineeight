## RED: typeres_unhandled_node (error[3002])

**Bisected minimal trigger:** `for (1..13) |i| { _ = i; }` — range-for expression.

**zig1 RED evidence:**
- `sf/build/out_release/zig1 --dump-c89 repro/mi_matrix/typeres_unhandled_node/main.zig` → dump rc=2
- stderr: `error[3002]: internal error: unhandled node kind in type resolution`

**Oracle (zig0):**
- `./sf/build/zig0 --header-priority-include -o /tmp/D1or/o.c repro/mi_matrix/typeres_unhandled_node/main.zig` → rc=0
- zig0 handles range-for in type resolution; zig1 does not.

**Layer:** type resolution

**Expected post-fix behavior:** zig1 `--dump-c89` returns rc=0 (or rc=1 with a proper user-facing error if semantics differ), no ICE.
