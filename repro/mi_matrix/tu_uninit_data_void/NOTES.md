# A2: Hand-rolled Tagged Union — Uninitialized Union Data for Void-Variant Tag

**Pattern:** Struct with `tag: Tag` + `data: Data` (union). When tag is Nil, the union data field is uninitialized. Full struct copy reads potentially undefined data.

**Category:** A2 — uninitialized union data for void-variant tag

**Note:** All hand-rolled `struct{tag, data: union}` patterns trigger error[3043] on field-store to union members. No GREEN variant exists for this category.
