# Task 1 Report: Revert v2-T4 return hack and v2-T2 var_decl materializeInto call

**Status:** DONE

## Changes
- `sf/src/lower.zig` `return_stmt` handler (~3317): reverted v2-T4 block. Restored `lowerExpr(self, node.child_0)` (was `lowerExprImpl`), replaced the coercion/`materializeInto` wrapping logic with the pre-v2-T4 original `getTempType`/RET_GAP marker + `type_id` relabel path.
- `sf/src/lower.zig` `var_decl` init (~3462): removed the v2-T2 line `init_val = materializeInto(self, init_val, decl_type);`.
- `materializeInto` FUNCTION untouched (still exists, now unreachable). No other changes.

## Verification
- Both regions matched the brief's "current" snippet exactly before editing.
- Main build: **OK** (`[release] Done` marker present; only pre-existing main_dump.zig/source_manager.zig noise).
- Lisp gate error count after revert: **9** (EXPECTED — the two `value_to_env_real` `return null` sites go back to broken; re-fixed in Task 4).

## Files changed
- `sf/src/lower.zig`

## Commit
- `a7641aba` — revert(lower): drop v2-T4 return hack and v2-T2 var_decl materializeInto call; applyCoercion is sole wrapper again
