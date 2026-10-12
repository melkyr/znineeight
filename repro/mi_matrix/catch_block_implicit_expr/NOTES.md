# C1: Catch Block with Implicit Expression Return

**Pattern:** `catch |err| { ...; value; }` — block expression used as catch default value.

**Note:** Both GREEN and RED variants compile successfully. The catch-block expression pattern works in zig1. No RED repro exists for this pattern.

**Category:** C1 — catch with block-expression return
