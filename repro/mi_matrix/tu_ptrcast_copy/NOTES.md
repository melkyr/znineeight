# A3: Hand-rolled Tagged Union — Full Copy via @ptrCast Pointer

**Pattern:** Copy of a hand-rolled `struct{tag, data: union}` through `@ptrCast(*Value, ...)` pointer using `ptr.* = v`.

**Category:** A3 — hand-rolled union copy through pointer

**Note:** All hand-rolled `struct{tag, data: union}` patterns trigger error[3043] on field-store to union members. No GREEN variant exists for this category. `union(enum)` full copy works (see lisp_interpreter_curr), but the hand-rolled equivalent does not.
