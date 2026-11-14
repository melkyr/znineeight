# array_tagged_union_read — RED (SEPARATE pre-existing bug, OUT OF SCOPE for tagged-union-payload plan)

## Form
Array of a payload-carrying tagged union, elements read back via `switch (arr[i])`:
```zig
var arr: [2]Command = [2]Command{ Command{ .Go = 3 }, Command{ .Go = 4 } };
// read arr[0].Go + arr[1].Go
```
`Command = union(enum) { Quit: void, Go: i32 }`.

## Expected
`7` (3 + 4).

## Empirical result on HEAD `5e2ccc9d` (Task 4 Step 4 investigation, 2026-07-09)
**RED — prints `6`, not `7`.** dump rc=0, gcc 0 errors, run rc=0 (links, wrong value).

## Why this is OUT OF SCOPE for the tagged-union-payload-store plan
This is NOT an anonymous-init bug and NOT a payload-STORE bug:
- The construction side is CORRECT: both elements write `.payload.Go._0` (verified: 2 payload writes,
  `zT_2.payload.Go._0 = 3`, `zT_6.payload.Go._0 = 4`).
- Uses EXPLICIT `Command{ .Go = N }` (not anonymous `.{}`), and the ANON form
  (`.{ .Go = 3 }`) produces the identical wrong value `6` — so it is independent of Task 4's
  anon-init inference (which is working here).
- The defect is in the array element read / indexed-tagged-union path (the `switch (arr[i])` read of an
  array element, or the array element copy `arr[_i] = zT_1[_i]`), producing a wrong payload on read-back.

This is a SEPARATE pre-existing array-of-tagged-union bug, to be handled in its own future plan. Recorded
here as a known-failing repro so it is not lost. Do NOT fix it inside the tagged-union-payload-store plan.

## Cross-links
- Discovered during Task 4 Step 4 (`.opencode/plans/2026-07-08-tagged-union-payload-store.md`).
- Anon-init inference (Task 4) is confirmed working; this is downstream of it.
