# Pointer-Only Type Classification for C89 Emission — v2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Classify aggregate types as pointer-only (all non-primitive fields accessed through pointers/slices/wrappers — safe to emit after forward declarations) or value-embedding (needs field types fully defined first). C89 emitter splits pass 2 into 2a/2b using this classification, resolving define-before-use for recursive `union(enum)` types like `{ Array: []Self }` without touching the layout dependency graph.

**Architecture:** Two new functions in `type_resolver.zig`. `fieldEmbedsByValue(kind)` returns true for the 5 compound kinds that embed payloads by value (struct, tagged_union, union, array, tuple). `classifyTypeEmissionGroups` scans types and builds a wrapper-parent adjacency list from optional/error_union field payloads, then propagates non-pointer-only status outward via a worklist — no recursion, no second Kahn's sort, no cycles. The emitter's `emitSpecialTypes` pass 2 splits into sub-pass 2a (pointer-only) and 2b (value-embedding). A separate minimal edge fix in Task 5a removes slice/ptr edge counting from `tstEdgesCount`/`tstEdgesFill` so cycle-stuck pointer-only types enter the sorted array and reach pass 2a.

**Why previous approaches failed (memories):**
1. `isValueDependency` edge fix (`ee7a0905`) — reverted. Broke define-before-use: named structs emitted before their anonymous slice/optional/EU typedefs (both indegree=0, arbitrarily ordered by Kahn's queue).
2. Two-pass anonymous-first/named-second — failed. Anonymous types embedding named types by-value (e.g., `E!SomeStruct`) emitted in pass 2a BEFORE `SomeStruct` body defined.
3. Full dep graph in `type_resolver` with passthrough to emitter — 4 commits reverted. `types_len` grows after build, scratch allocator dangling pointers, `sorted_items` never wired properly.

This plan avoids all three: edge rules stay (Task 5a is a minimal removal, not a replacement), classification is structural not name-based (handles `E!SomeStruct` correctly via propagation), and classification uses permanent arena, not scratch.

**Tech Stack:** zig0 C89 bootstrap compiler (Z98 dialect)

## Global Constraints

- Dep graph edge rules unchanged except Task 5a minimal removal (slice/ptr branches only)
- Type registry unchanged (no new fields, no flags bits)
- Existing sorted_items from Kahn sort unchanged
- Manual edits only (no sed/python/replace-all)
- `fastedit` per AGENTS.md X.7: re-read region before every edit; edit bottom-to-top
- Z98 string literal rule: named `var` for each literal used in function arguments
- Gate baselines: mandelbrot, game_of_life, mud_server MUST produce 0 gcc errors AND byte-identical C output to pre-fix HEAD
- Gate: json_parser MUST compile with 0 gcc errors AND run correctly against test.json
- Build: `./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig` then `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1`
- Stop on any gate failure, present results, do not continue without explicit authorization

---

## File Structure

| File | Change | Purpose |
|------|--------|---------|
| `sf/src/type_resolver.zig` | ADD `fieldEmbedsByValue` + `classifyTypeEmissionGroups` | Classification logic |
| `sf/src/main.zig:103` | MODIFY `CompilerContext` struct | Add `pointer_only_ids`/`pointer_only_len` |
| `sf/src/main.zig:316` | MODIFY `phase_TypeResolution` | Call classification after type resolver |
| `sf/src/c89_emit.zig:399` | MODIFY `C89Emitter` struct | Add `pointer_only_map` |
| `sf/src/c89_emit.zig:809-853` | MODIFY `emitSpecialTypes` pass 2 | Split into sub-pass 2a / 2b |
| `sf/src/c89_emit.zig:1394` | MODIFY `emitModule` signature | Accept pointer_only arrays |
| `sf/src/main.zig:679` | MODIFY `phase_C89Emission` | Pass pointer_only arrays to emitter |
| `sf/src/c89_emit.zig:658-663` | MODIFY `tstEdgesCount` | Remove slice_type / ptr_type edge counting |
| `sf/src/c89_emit.zig:700-709` | MODIFY `tstEdgesFill` | Remove slice_type / ptr_type edge filling |

---

### Task 1: Add `fieldEmbedsByValue` and `classifyTypeEmissionGroups` to type_resolver.zig

**Files:**
- Modify: `sf/src/type_resolver.zig` (add two new functions after `typeResolverResolve`)

**Interfaces:**
- Consumes: `self.registry` — `types_len`, `types_items`, `st_items`, `tu_items`, `un_items`, `fe_items`, `array_items`, `opt_items`, `eu_items`
- Produces: `struct { ids: [*]u32, len: u32 }` — pointer-only type IDs allocated on passed permanent arena

**Classification algorithm (no recursion, no second Kahn's):**

**Phase A — Direct scan:** For each type T, iterate fields. If a field's kind is in `fieldEmbedsByValue` (struct, tagged_union, union, array, tuple) → T is NOT pointer-only. If a field is `optional_type` or `error_union_type` → record payload_tid as a wrapper-parent of T in a dynamically-grown adjacency list. All other kinds (ptr, many_ptr, slice, fn, primitives, enum, error_set) → continue.

**Phase B — Propagation via worklist:** Seed worklist with all types already marked NOT pointer-only. While worklist not empty, pop T. For each parent P that has `?T` or `!T` field → mark P NOT pointer-only, push to worklist. This handles `?Struct` wrapping, `!Struct` wrapping, and chains like `?!?DeepStruct`.

`fieldEmbedsByValue` explicitly excludes `optional_type` and `error_union_type` — they are handled by Phase B propagation, not direct classification. This is the key architectural distinction from `isValueDependency`.

**Why no recursion, no cycles:** The worklist only visits types whose pointer-only status changes (0 → 1 never happens). A wrapper-only cycle (TypeA has `?TypeB`, TypeB has `?TypeA`) with no value-embedding fields anywhere → both stay pointer-only (correct). A cycle with at least one value-embedding type → that type seeds the worklist → propagates to all reachable parents → finite.

**Dynamic growth pattern for wrapper-edge arrays:** Each wrapper-edge append checks `wp_count >= wp_edge_cap`. If full, allocate `new_cap = wp_edge_cap * 2`, copy old `wp_to`/`wp_next` contents, update pointers. Initial capacity = `tl * 4`.

- [ ] **Step 1: Read insertion point**

Read `sf/src/type_resolver.zig:1-30` for imports. Read `sf/src/type_resolver.zig:305-320` for end of `typeResolverResolve`.

- [ ] **Step 2: Add `fieldEmbedsByValue` helper**

Insert after `typeResolverResolve` closing brace:

```zig
fn fieldEmbedsByValue(kind: TypeKind) bool {
    if (kind == TypeKind.struct_type) return true;
    if (kind == TypeKind.tagged_union_type) return true;
    if (kind == TypeKind.union_type) return true;
    if (kind == TypeKind.array_type) return true;
    if (kind == TypeKind.tuple_type) return true;
    return false;
}
```

**Excluded types and why:**
- `optional_type` — wraps payload. `?*T` is pointer-only; `?Struct` is not. Classified by Phase B propagation.
- `error_union_type` — wraps payload. `!*T` is pointer-only; `!Struct` is not. Classified by Phase B.
- `ptr_type`, `many_ptr_type`, `slice_type`, `fn_type` — embed pointer, never by-value.
- `enum_type`, `error_set_type`, all primitives — fixed size, no payload.

- [ ] **Step 3: Add `classifyTypeEmissionGroups`**

Insert after `fieldEmbedsByValue`. The function builds wrapper-parent adjacency and propagates non-pointer-only status via worklist. Full implementation below.

```zig
pub fn classifyTypeEmissionGroups(self: *TypeResolver, perm_alloc: *Sand) struct { ids: [*]u32, len: u32 } {
    var tl: usize = self.registry.types_len;

    // pointer_only flags: 1 byte per type
    var po_raw = alloc_mod.sandAlloc(perm_alloc, 1 * tl, 1) catch unreachable;
    var pointer_only: [*]u8 = @ptrCast([*]u8, po_raw);

    // Wrapper-parent adjacency: linked-list-per-payload_tid, dynamically grown
    var wp_edge_cap: usize = tl * 4;
    var wp_to_raw = alloc_mod.sandAlloc(perm_alloc, 4 * wp_edge_cap, 4) catch unreachable;
    var wp_to: [*]u32 = @ptrCast([*]u32, wp_to_raw);
    var wp_next_raw = alloc_mod.sandAlloc(perm_alloc, 4 * wp_edge_cap, 4) catch unreachable;
    var wp_next: [*]u32 = @ptrCast([*]u32, wp_next_raw);
    var wp_head_raw = alloc_mod.sandAlloc(perm_alloc, 4 * tl, 4) catch unreachable;
    var wp_head: [*]u32 = @ptrCast([*]u32, wp_head_raw);
    var whi: usize = 0;
    while (whi < tl) : (whi += 1) { wp_head[whi] = @intCast(u32, 4294967295); }
    var wp_count: u32 = @intCast(u32, 0);

    // Worklist for Phase B propagation
    var wl_raw = alloc_mod.sandAlloc(perm_alloc, 4 * tl, 4) catch unreachable;
    var worklist: [*]u32 = @ptrCast([*]u32, wl_raw);
    var wl_head: u32 = @intCast(u32, 0);
    var wl_tail: u32 = @intCast(u32, 0);

    // Phase A: scan all types, mark by-value embeddings, record wrapper-parent edges
    var ti: usize = 0;
    while (ti < tl) : (ti += 1) {
        var ty = self.registry.types_items[ti];
        var is_po: u8 = @intCast(u8, 1);

        // === struct_type ===
        if (ty.kind == TypeKind.struct_type) {
            var sp = self.registry.st_items[@intCast(usize, ty.payload_idx)];
            var fi: usize = 0;
            while (fi < @intCast(usize, sp.fields_count) and is_po != 0) : (fi += 1) {
                var ft_id = self.registry.fe_items[@intCast(usize, sp.fields_start) + fi].type_id;
                var ft = self.registry.types_items[@intCast(usize, ft_id)];
                if (fieldEmbedsByValue(ft.kind)) {
                    is_po = @intCast(u8, 0);
                } else if (ft.kind == TypeKind.optional_type) {
                    var payload = self.registry.opt_items[@intCast(usize, ft.payload_idx)].payload;
                    if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next: new_cap=wp_edge_cap*2, alloc+copy, update pointers+cap] }
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    var payload = self.registry.eu_items[@intCast(usize, ft.payload_idx)].payload;
                    if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        // === tagged_union_type ===
        } else if (ty.kind == TypeKind.tagged_union_type) {
            var tp = self.registry.tu_items[@intCast(usize, ty.payload_idx)];
            var fi: usize = 0;
            while (fi < @intCast(usize, tp.fields_count) and is_po != 0) : (fi += 1) {
                var ft_id = self.registry.fe_items[@intCast(usize, tp.fields_start) + fi].type_id;
                var ft = self.registry.types_items[@intCast(usize, ft_id)];
                if (fieldEmbedsByValue(ft.kind)) {
                    is_po = @intCast(u8, 0);
                } else if (ft.kind == TypeKind.optional_type) {
                    var payload = self.registry.opt_items[@intCast(usize, ft.payload_idx)].payload;
                    if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    var payload = self.registry.eu_items[@intCast(usize, ft.payload_idx)].payload;
                    if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        // === union_type (bare) ===
        } else if (ty.kind == TypeKind.union_type) {
            var up = self.registry.un_items[@intCast(usize, ty.payload_idx)];
            var fi: usize = 0;
            while (fi < @intCast(usize, up.fields_count) and is_po != 0) : (fi += 1) {
                var ft_id = self.registry.fe_items[@intCast(usize, up.fields_start) + fi].type_id;
                var ft = self.registry.types_items[@intCast(usize, ft_id)];
                if (fieldEmbedsByValue(ft.kind)) {
                    is_po = @intCast(u8, 0);
                } else if (ft.kind == TypeKind.optional_type) {
                    var payload = self.registry.opt_items[@intCast(usize, ft.payload_idx)].payload;
                    if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                } else if (ft.kind == TypeKind.error_union_type) {
                    var payload = self.registry.eu_items[@intCast(usize, ft.payload_idx)].payload;
                    if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                    wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                    wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                    wp_head[@intCast(usize, payload)] = wp_count;
                    wp_count += @intCast(u32, 1);
                }
            }
        // === array_type ===
        } else if (ty.kind == TypeKind.array_type) {
            var et = self.registry.array_items[@intCast(usize, ty.payload_idx)].elem;
            var et_ty = self.registry.types_items[@intCast(usize, et)];
            if (fieldEmbedsByValue(et_ty.kind)) {
                is_po = @intCast(u8, 0);
            } else if (et_ty.kind == TypeKind.optional_type) {
                var payload = self.registry.opt_items[@intCast(usize, et_ty.payload_idx)].payload;
                if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            } else if (et_ty.kind == TypeKind.error_union_type) {
                var payload = self.registry.eu_items[@intCast(usize, et_ty.payload_idx)].payload;
                if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            }
        // === error_union_type ===
        } else if (ty.kind == TypeKind.error_union_type) {
            var eup = self.registry.eu_items[@intCast(usize, ty.payload_idx)].payload;
            var eup_ty = self.registry.types_items[@intCast(usize, eup)];
            if (fieldEmbedsByValue(eup_ty.kind)) {
                is_po = @intCast(u8, 0);
            } else if (eup_ty.kind == TypeKind.optional_type) {
                var payload = self.registry.opt_items[@intCast(usize, eup_ty.payload_idx)].payload;
                if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            } else if (eup_ty.kind == TypeKind.error_union_type) {
                var payload = self.registry.eu_items[@intCast(usize, eup_ty.payload_idx)].payload;
                if (wp_count >= @intCast(u32, wp_edge_cap)) { [grow wp_to/wp_next] }
                wp_to[@intCast(usize, wp_count)] = @intCast(u32, ti);
                wp_next[@intCast(usize, wp_count)] = wp_head[@intCast(usize, payload)];
                wp_head[@intCast(usize, payload)] = wp_count;
                wp_count += @intCast(u32, 1);
            }
        }

        pointer_only[ti] = is_po;
        if (is_po == @intCast(u8, 0)) {
            worklist[@intCast(usize, wl_tail)] = @intCast(u32, ti);
            wl_tail += @intCast(u32, 1);
        }
    }

    // Phase B: propagate non-pointer-only via wrapper-parent edges
    while (wl_head < wl_tail) {
        var cur = worklist[@intCast(usize, wl_head)];
        wl_head += @intCast(u32, 1);
        var e: u32 = wp_head[@intCast(usize, cur)];
        while (e != @intCast(u32, 4294967295)) {
            var parent_tid = wp_to[@intCast(usize, e)];
            if (pointer_only[@intCast(usize, parent_tid)] != @intCast(u8, 0)) {
                pointer_only[@intCast(usize, parent_tid)] = @intCast(u8, 0);
                worklist[@intCast(usize, wl_tail)] = parent_tid;
                wl_tail += @intCast(u32, 1);
            }
            e = wp_next[@intCast(usize, e)];
        }
    }

    // Collect pointer-only type IDs into result array
    var ids_raw = alloc_mod.sandAlloc(perm_alloc, 4 * tl, 4) catch unreachable;
    var ids: [*]u32 = @ptrCast([*]u32, ids_raw);
    var plen: u32 = @intCast(u32, 0);
    ti = 0;
    while (ti < tl) : (ti += 1) {
        if (pointer_only[ti] != @intCast(u8, 0)) {
            ids[@intCast(usize, plen)] = @intCast(u32, ti);
            plen += @intCast(u32, 1);
        }
    }

    // Classification markers for diagnostics
    var cls_m: []const u8 = "CLS:c"; pal.markerWrite(cls_m);
    var cls_b: [10]u8 = undefined;
    var cls_l = itoa_mod.itoa(plen, cls_b[0..]);
    var cls_s: usize = @intCast(usize, 9) - @intCast(usize, cls_l);
    pal.markerWrite(cls_b[cls_s..@intCast(usize, 9)]);
    var cls_nl: []const u8 = "\n"; pal.markerWrite(cls_nl);
    // Per-type markers: CLS:p<tid>k<kind> = pointer-only, CLS:v<tid>k<kind> = value-embedding
    ti = 0;
    while (ti < tl) : (ti += 1) {
        var pfx: []const u8 = undefined;
        if (pointer_only[ti] != @intCast(u8, 0)) {
            pfx = "CLS:p";
        } else {
            pfx = "CLS:v";
        }
        pal.markerWrite(pfx);
        var ctb: [10]u8 = undefined;
        var ctl = itoa_mod.itoa(@intCast(u32, ti), ctb[0..]);
        var cts: usize = @intCast(usize, 9) - @intCast(usize, ctl);
        pal.markerWrite(ctb[cts..@intCast(usize, 9)]);
        var ck: []const u8 = "k";
        pal.markerWrite(ck);
        var ckb: [10]u8 = undefined;
        var ckl = itoa_mod.itoa(@intCast(u32, @enumToInt(self.registry.types_items[ti].kind)), ckb[0..]);
        var cks: usize = @intCast(usize, 9) - @intCast(usize, ckl);
        pal.markerWrite(ckb[cks..@intCast(usize, 9)]);
        var cnl: []const u8 = "\n"; pal.markerWrite(cnl);
    }

    var result: struct { ids: [*]u32, len: u32 } = .{ .ids = ids, .len = plen };
    return result;
}
```

**Implementation note on `[grow wp_to/wp_next]` blocks:** Each `[grow wp_to/wp_next]` placeholder above should be replaced with:

```zig
var new_cap: usize = wp_edge_cap * 2;
var new_to = alloc_mod.sandAlloc(perm_alloc, 4 * new_cap, 4) catch unreachable;
var new_nx = alloc_mod.sandAlloc(perm_alloc, 4 * new_cap, 4) catch unreachable;
var ci: usize = 0;
while (ci < @intCast(usize, wp_count)) : (ci += 1) {
    new_to[ci] = wp_to[ci];
    new_nx[ci] = wp_next[ci];
}
wp_to = @ptrCast([*]u32, new_to);
wp_next = @ptrCast([*]u32, new_nx);
wp_edge_cap = new_cap;
```

This block appears 8 times in the Phase A scan (2 wrapper kinds × 4 struct/tagged_union/union locations for struct/tagged_union/union types, plus 1 each for array and error_union). In implementation, extract to a local helper function to avoid duplication. Total wrapper edges in practice: ~field count across all types × fraction of optional/EU fields. Initial capacity `tl * 4` handles the common case; growth only triggers for inputs with many wrapper fields.

**Markers produced:**
- `CLS:c<N>` — count of pointer-only types
- `CLS:p<tid>k<kind>` — type is pointer-only
- `CLS:v<tid>k<kind>` — type is value-embedding

- [ ] **Step 4: Build zig1 — verify 0 gcc errors**

```bash
OUT=/tmp/zptr_v2 && rm -rf $OUT && mkdir -p $OUT
./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig 2>&1 >/dev/null
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1 2>&1 | grep -c 'error:'
```
Expected: `0`

- [ ] **Step 5: Verify classification markers on json_parser**

```bash
$OUT/zig1 --markers --dump-c89 json_parser/main.zig > /dev/null 2>/tmp/cls_markers.txt
grep "^CLS:" /tmp/cls_markers.txt
echo "=== pointer-only ===" && grep "^CLS:p" /tmp/cls_markers.txt | wc -l
echo "=== value-embedding ===" && grep "^CLS:v" /tmp/cls_markers.txt | wc -l
```
Expected: `CLS:c<N>` present. `CLS:p` count >= 4 (slice types + tagged union JsonValue + struct JsonItem). `CLS:v` count >= 0.

- [ ] **Step 6: Commit**

```bash
git add sf/src/type_resolver.zig
git commit -m "feat: add fieldEmbedsByValue + classifyTypeEmissionGroups with wrapper-propagation"
```

---

### Task 2: Wire classification into CompilerContext and phase_TypeResolution

**Files:**
- Modify: `sf/src/main.zig:103` (CompilerContext struct)
- Modify: `sf/src/main.zig:158` (init defaults)
- Modify: `sf/src/main.zig:316` (call classification)

**Interfaces:**
- Consumes: `classifyTypeEmissionGroups(&tr, &ctx.alloc.permanent)` from Task 1
- Produces: `ctx.pointer_only_ids: [*]u32`, `ctx.pointer_only_len: u32`

- [ ] **Step 1: Read CompilerContext struct area**

Read `sf/src/main.zig:95-115` for struct fields. Read `sf/src/main.zig:150-165` for init defaults. Read `sf/src/main.zig:310-320` for phase_TypeResolution call site.

- [ ] **Step 2: Add pointer_only fields to CompilerContext**

After `comptime_values` field:

```zig
    pointer_only_ids: [*]u32,
    pointer_only_len: u32,
```

- [ ] **Step 3: Add init defaults**

```zig
    .pointer_only_ids = undefined,
    .pointer_only_len = @intCast(u32, 0),
```

- [ ] **Step 4: Call classification after type resolution**

After `type_resolver.typeResolverResolve(&tr)`:

```zig
    var ptr_grp = type_resolver.classifyTypeEmissionGroups(&tr, &ctx.alloc.permanent);
    ctx.pointer_only_ids = ptr_grp.ids;
    ctx.pointer_only_len = ptr_grp.len;
```

- [ ] **Step 5: Build zig1 — verify 0 errors**

Same build as Task 1 Step 4. Expected: `0`.

- [ ] **Step 6: Commit**

```bash
git add sf/src/main.zig
git commit -m "feat: wire pointer-only classification into CompilerContext"
```

---

### Task 3: C89 emitter uses pointer_only for two-sub-pass emission

**Files:**
- Modify: `sf/src/c89_emit.zig:399` (C89Emitter struct — add `pointer_only_map`)
- Modify: `sf/src/c89_emit.zig:401` (c89EmitterInit — init map)
- Modify: `sf/src/c89_emit.zig:1394` (emitModule signature + lookup map build)
- Modify: `sf/src/c89_emit.zig:809-853` (emitSpecialTypes pass 2 — split into 2a/2b)
- Modify: `sf/src/main.zig:679` (phase_C89Emission — pass arrays to emitModule)

**Interfaces:**
- Consumes: `pointer_only_ids: [*]u32`, `pointer_only_len: u32` from CompilerContext
- Produces: C89 output with define-before-use type emission order

**Emission order:**
- Pass 1 (unchanged): Forward-declare named struct/tagged_union/union
- Pass 2a (new): Iterate sorted array, emit types IN pointer_only set
- Pass 2b (existing logic): Iterate sorted array, emit types NOT IN pointer_only set
- Each sub-pass uses identical skip logic (primitives, anonymous non-exempted kinds, dedup key check)

- [ ] **Step 1: Read current C89Emitter struct and init**

Read `sf/src/c89_emit.zig:390-410`. Read `sf/src/c89_emit.zig:1390-1410` for emitModule. Read `sf/src/c89_emit.zig:809-853` for current pass 2 loop.

- [ ] **Step 2: Add pointer_only_map to C89Emitter**

After `emitted_type_set` field:

```zig
    pointer_only_map: U32ToU32Map,
```

In `c89EmitterInit` after `emitted_type_set` init:

```zig
    .pointer_only_map = hash_mod.u32ToU32MapInit(alloc),
```

- [ ] **Step 3: Change emitModule signature and build lookup map**

Change signature from:
```zig
pub fn emitModule(emitter: *C89Emitter, name: []const u8, fns: []LirFunction) void {
```
To:
```zig
pub fn emitModule(emitter: *C89Emitter, name: []const u8, fns: []LirFunction, ptr_only_ids: [*]u32, ptr_only_len: u32) void {
```

At start of emitModule body, build the lookup map:

```zig
    var poi: u32 = @intCast(u32, 0);
    while (poi < ptr_only_len) : (poi += 1) {
        hash_mod.u32ToU32MapPut(&emitter.pointer_only_map, ptr_only_ids[@intCast(usize, poi)], @intCast(u32, 1));
    }
```

- [ ] **Step 4: Restructure emitSpecialTypes pass 2**

Replace the single pass 2 loop (currently lines 809-853) with two sub-loops. The membership check is `hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) != null`. Each sub-pass uses the EXACT same skip logic (primitives, anonymous non-exempted, dedup key). Markers are `E2A:` for sub-pass 2a and `E2B:` for sub-pass 2b. The existing `D2:` tagged_union marker in pass 2b is preserved.

Replace lines 809-853 with the two-sub-pass code from the `c89-emitter-two-pass-types.md` plan, modified to use `pointer_only_map` membership check instead of `name_id` check:

```zig
    // Sub-pass 2a: emit pointer-only types first
    // (fields all through pointers/slices/wrappers — forward decls sufficient)
    tsi = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) == null) continue;
        var ty = reg.types_items[@intCast(usize, tid)];
        var e2m: []const u8 = "E2A:t"; pal.markerWrite(e2m); var e2b: [10]u8 = undefined; var e2l = itoa_mod.itoa(tid, e2b[0..]); var e2s: usize = @intCast(usize, 9) - @intCast(usize, e2l); pal.markerWrite(e2b[e2s..@intCast(usize, 9)]); var e2k: []const u8 = "k"; pal.markerWrite(e2k); var e2kb: [10]u8 = undefined; var e2kl2 = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), e2kb[0..]); var e2ks: usize = @intCast(usize, 9) - @intCast(usize, e2kl2); pal.markerWrite(e2kb[e2ks..@intCast(usize, 9)]); var e2nl2: []const u8 = "\n"; pal.markerWrite(e2nl2);
        if (ty.kind == TypeKind.void_type) continue;
        if (ty.kind == TypeKind.bool_type) continue;
        if (ty.kind == TypeKind.noreturn_type) continue;
        if (ty.kind == TypeKind.null_type) continue;
        if (ty.kind == TypeKind.undefined_type) continue;
        if (ty.kind == TypeKind.integer_literal_type) continue;
        if (ty.kind == TypeKind.type_type) continue;
        if (ty.kind == TypeKind.module_type) continue;
        if (ty.name_id == @intCast(u32, 0)) {
            if (ty.kind != TypeKind.slice_type and
                ty.kind != TypeKind.optional_type and
                ty.kind != TypeKind.error_union_type and
                ty.kind != TypeKind.tagged_union_type and
                ty.kind != TypeKind.union_type and
                ty.kind != TypeKind.array_type and
                ty.kind != TypeKind.fn_type)
            {
                var est_m: []const u8 = "ESTA:t"; pal.markerWrite(est_m); var est_b: [10]u8 = undefined; var est_l = itoa_mod.itoa(tid, est_b[0..]); var est_s: usize = @intCast(usize, 9) - @intCast(usize, est_l); pal.markerWrite(est_b[est_s..@intCast(usize, 9)]); var est_km: []const u8 = "k"; pal.markerWrite(est_km); var est_kb: [10]u8 = undefined; var est_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), est_kb[0..]); var est_ks: usize = @intCast(usize, 9) - @intCast(usize, est_kl); pal.markerWrite(est_kb[est_ks..@intCast(usize, 9)]); var est_nm: []const u8 = "n"; pal.markerWrite(est_nm); var est_nb: [10]u8 = undefined; var est_nl2 = itoa_mod.itoa(ty.name_id, est_nb[0..]); var est_ns: usize = @intCast(usize, 9) - @intCast(usize, est_nl2); pal.markerWrite(est_nb[est_ns..@intCast(usize, 9)]); var est_nl: []const u8 = "\n"; pal.markerWrite(est_nl);
                continue;
            }
        }
        var cname = getCTypeName(reg, emitter.mangler, tid);
        var dedup_key: u32 = @intCast(u32, 0);
        var h_ci: usize = @intCast(usize, 0);
        while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
            dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
        }
        if (hash_mod.u32ToU32MapGet(&emitter.emitted_type_set, dedup_key)) |_| continue;
        hash_mod.u32ToU32MapPut(&emitter.emitted_type_set, dedup_key, @intCast(u32, 1));
        emitTypeDefinition(emitter, tid);
    }

    // Sub-pass 2b: emit value-embedding types
    // (types that embed field types by value — need dependents defined first)
    tsi = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) != null) continue;
        var ty = reg.types_items[@intCast(usize, tid)];
        var e2m: []const u8 = "E2B:t"; pal.markerWrite(e2m); var e2b: [10]u8 = undefined; var e2l = itoa_mod.itoa(tid, e2b[0..]); var e2s: usize = @intCast(usize, 9) - @intCast(usize, e2l); pal.markerWrite(e2b[e2s..@intCast(usize, 9)]); var e2k: []const u8 = "k"; pal.markerWrite(e2k); var e2kb: [10]u8 = undefined; var e2kl2 = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), e2kb[0..]); var e2ks: usize = @intCast(usize, 9) - @intCast(usize, e2kl2); pal.markerWrite(e2kb[e2ks..@intCast(usize, 9)]); var e2nm: []const u8 = "n"; pal.markerWrite(e2nm); var e2nb: [10]u8 = undefined; var e2nl3 = itoa_mod.itoa(ty.name_id, e2nb[0..]); var e2ns: usize = @intCast(usize, 9) - @intCast(usize, e2nl3); pal.markerWrite(e2nb[e2ns..@intCast(usize, 9)]); var e2nl2: []const u8 = "\n"; pal.markerWrite(e2nl2);
        if (ty.kind == TypeKind.tagged_union_type) {
            var d2m: []const u8 = "D2:t"; pal.markerWrite(d2m);
            var d2b: [20]u8 = undefined; var d2l = itoa_mod.itoa(tid, d2b[0..]); var d2s: usize = @intCast(usize, 19) - @intCast(usize, d2l); pal.markerWrite(d2b[d2s..@intCast(usize, 19)]);
            var d2nn: []const u8 = "n"; pal.markerWrite(d2nn);
            var d2nb: [20]u8 = undefined; var d2nl = itoa_mod.itoa(ty.name_id, d2nb[0..]); var d2ns: usize = @intCast(usize, 19) - @intCast(usize, d2nl); pal.markerWrite(d2nb[d2ns..@intCast(usize, 19)]);
            var d2mm: []const u8 = "m"; pal.markerWrite(d2mm);
            var d2mb: [20]u8 = undefined; var d2ml = itoa_mod.itoa(ty.module_id, d2mb[0..]); var d2ms: usize = @intCast(usize, 19) - @intCast(usize, d2ml); pal.markerWrite(d2mb[d2ms..@intCast(usize, 19)]);
            var d2nl2: []const u8 = "\n"; pal.markerWrite(d2nl2);
        }
        if (ty.kind == TypeKind.void_type) continue;
        if (ty.kind == TypeKind.bool_type) continue;
        if (ty.kind == TypeKind.noreturn_type) continue;
        if (ty.kind == TypeKind.null_type) continue;
        if (ty.kind == TypeKind.undefined_type) continue;
        if (ty.kind == TypeKind.integer_literal_type) continue;
        if (ty.kind == TypeKind.type_type) continue;
        if (ty.kind == TypeKind.module_type) continue;
        if (ty.name_id == @intCast(u32, 0)) {
            if (ty.kind != TypeKind.slice_type and
                ty.kind != TypeKind.optional_type and
                ty.kind != TypeKind.error_union_type and
                ty.kind != TypeKind.tagged_union_type and
                ty.kind != TypeKind.union_type and
                ty.kind != TypeKind.array_type and
                ty.kind != TypeKind.fn_type)
            {
                var est_m: []const u8 = "ESTB:t"; pal.markerWrite(est_m); var est_b: [10]u8 = undefined; var est_l = itoa_mod.itoa(tid, est_b[0..]); var est_s: usize = @intCast(usize, 9) - @intCast(usize, est_l); pal.markerWrite(est_b[est_s..@intCast(usize, 9)]); var est_km: []const u8 = "k"; pal.markerWrite(est_km); var est_kb: [10]u8 = undefined; var est_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), est_kb[0..]); var est_ks: usize = @intCast(usize, 9) - @intCast(usize, est_kl); pal.markerWrite(est_kb[est_ks..@intCast(usize, 9)]); var est_nm: []const u8 = "n"; pal.markerWrite(est_nm); var est_nb: [10]u8 = undefined; var est_nl2 = itoa_mod.itoa(ty.name_id, est_nb[0..]); var est_ns: usize = @intCast(usize, 9) - @intCast(usize, est_nl2); pal.markerWrite(est_nb[est_ns..@intCast(usize, 9)]); var est_nl: []const u8 = "\n"; pal.markerWrite(est_nl);
                continue;
            }
        }
        var cname = getCTypeName(reg, emitter.mangler, tid);
        var dedup_key: u32 = @intCast(u32, 0);
        var h_ci: usize = @intCast(usize, 0);
        while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
            dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
        }
        if (hash_mod.u32ToU32MapGet(&emitter.emitted_type_set, dedup_key)) |_| continue;
        hash_mod.u32ToU32MapPut(&emitter.emitted_type_set, dedup_key, @intCast(u32, 1));
        emitTypeDefinition(emitter, tid);
    }
```

- [ ] **Step 5: Update call site in phase_C89Emission**

Read `sf/src/main.zig:670-685`. Change:

```zig
    c89_mod.emitModule(&emitter, module_name, fns, ctx.pointer_only_ids, ctx.pointer_only_len);
```

- [ ] **Step 6: Build zig1**

Same build as Task 1. Expected: `0`.

- [ ] **Step 7: Commit**

```bash
git add sf/src/c89_emit.zig sf/src/main.zig
git commit -m "feat: c89 emitter two-sub-pass emission using pointer-only classification"
```

---

### Task 4: Integration gate — baselines + json_parser classification (cycle still present)

**Files:** None (verification only)

**Goal:** Prove the classification wiring and two-sub-pass emission are correct. The cycle from `tstEmitPrimitiveKind` still blocks JsonValue/JsonItem from `sorted[]` — json_parser is expected to have ~279 gcc errors. This isolates the remaining blocker to the edge rules alone.

- [ ] **Step 1: Verify baselines byte-identical**

```bash
OUT=/tmp/zptr_v2
# Build pre-fix baseline zig1
git stash
BASELINE_OUT=/tmp/zptr_base && rm -rf $BASELINE_OUT && mkdir -p $BASELINE_OUT
./sf/build/zig0 --header-priority-include -o $BASELINE_OUT/zig1.c sf/src/main.zig 2>&1 >/dev/null
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $BASELINE_OUT/*.c -o $BASELINE_OUT/zig1 2>&1 >/dev/null
git stash pop

for EXAMPLE in mandelbrot game_of_life mud_server; do
  BASE=$($BASELINE_OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  FIX=$($OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  if [ "$BASE" = "$FIX" ]; then echo "$EXAMPLE: MATCH"; else echo "$EXAMPLE: DIFFER $BASE vs $FIX"; fi
done
```
Expected: All three `MATCH`.

- [ ] **Step 2: Verify 0 gcc errors on all examples**

```bash
for EXAMPLE in mandelbrot game_of_life; do
  $OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig > /tmp/${EXAMPLE}_g.c 2>/dev/null
  gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/${EXAMPLE}_g.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/${EXAMPLE}_g 2>&1 | grep -c 'error:'
done
# mud_server needs net_runtime.c
$OUT/zig1 --dump-c89 examples/mud_server/main.zig > /tmp/mud_g.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/mud_g.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c sf/src/include/net_runtime.c -o /tmp/mud_g 2>&1 | grep -c 'error:'
```
Expected: All `0`.

- [ ] **Step 3: json_parser — verify ~279 errors (cycle not yet broken)**

```bash
$OUT/zig1 --dump-c89 json_parser/main.zig > /tmp/json_v2_pre.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/json_v2_pre.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/json_v2_pre 2>&1 | grep -c 'error:'
```
Expected: ~279 errors (JsonValue/JsonItem still not emitted — cycle from `tstEmitPrimitiveKind` blocks them from `sorted[]`). This confirms classification wiring is clean; only the cycle remains.

- [ ] **Step 4: Classification marker sanity check**

```bash
$OUT/zig1 --markers --dump-c89 json_parser/main.zig > /dev/null 2>/tmp/cls_check.txt
echo "pointer-only:" && grep "^CLS:p" /tmp/cls_check.txt | wc -l
echo "value-embedding:" && grep "^CLS:v" /tmp/cls_check.txt | wc -l
echo "pass 2a emitted:" && grep "^E2A:t" /tmp/cls_check.txt | wc -l
echo "pass 2b emitted:" && grep "^E2B:t" /tmp/cls_check.txt | wc -l
```
Expected: `CLS:p` count >= 4. Note that cycle-stuck types won't appear in `E2A:`/`E2B:` (not in `sorted[]`). This proves the gap before Task 5a.

- [ ] **Step 5: STOP — present results. Do NOT continue to Task 5a without explicit authorization.**

---

### Task 5a: Remove slice/ptr edge counting from emitter graph

**Files:**
- Modify: `sf/src/c89_emit.zig:658-660` (tstEdgesCount — remove slice_type branch)
- Modify: `sf/src/c89_emit.zig:661-663` (tstEdgesCount — remove ptr_type branch)
- Modify: `sf/src/c89_emit.zig:700-704` (tstEdgesFill — remove slice_type branch)
- Modify: `sf/src/c89_emit.zig:705-709` (tstEdgesFill — remove ptr_type branch)

**Rationale:** `tstEmitPrimitiveKind` treats `slice_type` and `ptr_type` as non-primitive. `tstEdgesCount` and `tstEdgesFill` create edges from `Slice_JsonValue → JsonValue` and `Ptr_JsonValue → JsonValue`. These create `tagged_union ↔ slice_type` cycles blocking both from Kahn's sorted output. Slice types have fixed 8-byte size, pointer types have fixed 4-byte size — no layout dependency on their element/base type exists. Removing edge counting makes them indegree-0, entering `sorted[]`. The two-sub-pass emission from Task 3 ensures pointer-only types (all slices/ptr typedefs) emit in 2a before value-embedding types in 2b, preventing the `ee7a0905` regression.

`tstIsDep` is UNCHANGED — it's consulted only for already-counted edges.

- [ ] **Step 1: Read tstEdgesCount slice/ptr branches**

Read `sf/src/c89_emit.zig:655-668`.

- [ ] **Step 2: Remove slice_type and ptr_type branches from tstEdgesCount**

Delete the `else if (ty.kind == TypeKind.slice_type)` block (lines 658-660) and the `else if (ty.kind == TypeKind.ptr_type)` block (lines 661-663).

Before:
```zig
    } else if (ty.kind == TypeKind.array_type) {
        var et = reg.array_items[@intCast(usize, ty.payload_idx)].elem;
        if (!tstEmitPrimitiveKind(reg.types_items[@intCast(usize, et)].kind) and et != ti) c += 1;
    } else if (ty.kind == TypeKind.slice_type) {
        var et = reg.slice_items[@intCast(usize, ty.payload_idx)].elem;
        if (!tstEmitPrimitiveKind(reg.types_items[@intCast(usize, et)].kind) and et != ti) c += 1;
    } else if (ty.kind == TypeKind.ptr_type) {
        var pt = reg.ptr_items[@intCast(usize, ty.payload_idx)].base;
        if (!tstEmitPrimitiveKind(reg.types_items[@intCast(usize, pt)].kind) and pt != ti) c += 1;
    } else if (ty.kind == TypeKind.error_union_type) {
```

After:
```zig
    } else if (ty.kind == TypeKind.array_type) {
        var et = reg.array_items[@intCast(usize, ty.payload_idx)].elem;
        if (!tstEmitPrimitiveKind(reg.types_items[@intCast(usize, et)].kind) and et != ti) c += 1;
    } else if (ty.kind == TypeKind.error_union_type) {
```

- [ ] **Step 3: Read tstEdgesFill slice/ptr branches**

Read `sf/src/c89_emit.zig:695-715`.

- [ ] **Step 4: Remove slice_type and ptr_type branches from tstEdgesFill**

Same pattern — delete the `else if (ty.kind == TypeKind.slice_type)` block (lines 700-704) and `else if (ty.kind == TypeKind.ptr_type)` block (lines 705-709). Keep array_type and error_union_type branches.

- [ ] **Step 5: Build zig1**

```bash
OUT=/tmp/zptr_v2a && rm -rf $OUT && mkdir -p $OUT
./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig 2>&1 >/dev/null
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1 2>&1 | grep -c 'error:'
```
Expected: `0`

- [ ] **Step 6: Gate — baselines byte-identical, 0 gcc errors**

```bash
for EXAMPLE in mandelbrot game_of_life mud_server; do
  $OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig > /tmp/${EXAMPLE}_5a.c 2>/dev/null
  gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/${EXAMPLE}_5a.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/${EXAMPLE}_5a 2>&1 | grep -c 'error:'
done
```
Expected: All `0`. Also verify byte-identical against pre-fix baseline (`md5sum` comparison).

- [ ] **Step 7: json_parser — verify 0 gcc errors**

```bash
$OUT/zig1 --dump-c89 json_parser/main.zig > /tmp/json_v2_final.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/json_v2_final.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/json_v2_final 2>&1 | grep -c 'error:'
```
Expected: `0` (JsonValue/JsonItem now emitted via pass 2a — cycle broken).

- [ ] **Step 8: json_parser runtime — verify correct output**

```bash
cd /workspace/znineeight/json_parser && /tmp/json_v2_final 2>&1 | head -15
```
Expected: Parsed JSON output with test.json contents.

- [ ] **Step 9: Verify typedef order in json_parser C output**

```bash
grep -n 'typedef struct ' /tmp/json_v2_final.c | head -5
grep -n '^struct zT_' /tmp/json_v2_final.c | head -10
```
Expected: `typedef struct { ... } Slice_*` and anonymous compound typedefs BEFORE `struct zT_*` struct body definitions.

- [ ] **Step 10: STOP — present results. If any gate fails, revert Task 5a and report. Do NOT continue.**

---

### Task 5b: (Future separate plan) Full `isValueDependency` replacement

Not executed in this plan. Replace `tstEmitPrimitiveKind` with `isValueDependency` across all 3 functions (`tstEdgesCount`, `tstEdgesFill`, `tstIsDep`), then remove `tstEmitPrimitiveKind` entirely. Remove `enum_type` from `isValueDependency` per design doc prose. This is a separate plan gated on Task 5a success and json_parser working.

---

## Self-Review

1. **Spec coverage:** All requirements covered — classification function with `fieldEmbedsByValue` predicate and wrapper-propagation graph, CompilerContext wiring, emitter two-sub-pass split, integration gate, cycle-edge fix. Task 4 proves wiring before edge fix. Task 5a is minimal (4 branches removed), independently revertable.

2. **Placeholder scan:** No TBD, TODO, or vague steps. Every step has exact file:line, code, command with expected output. The `[grow wp_to/wp_next]` pattern is explained once with explicit replacement code — implementers replace all 8 occurrences.

3. **Type consistency:** `classifyTypeEmissionGroups` returns `struct { ids: [*]u32, len: u32 }` → CompilerContext stores same types → `emitModule` takes `ptr_only_ids: [*]u32, ptr_only_len: u32` → `phase_C89Emission` passes `ctx.pointer_only_ids, ctx.pointer_only_len`. Fully consistent across all 4 tasks.

4. **Marker instrumentation:** `CLS:c/p/v` (classification — count/pointer-only/value-embedding), `E2A:`/`E2B:` (sub-pass emitted), `ESTA:`/`ESTB:` (anonymous skip), `D2:` preserved (tagged union detail in pass 2b). All markers have distinct, grep-able prefixes.

5. **Risk management:** Task 4 verifies classification wiring with current edges intact (json_parser expected ~279 errors — confirms only the cycle remains). Task 5a removes 6 lines from 2 functions — minimal blast radius, independently revertable via git revert. `tstIsDep` untouched. Two-sub-pass ordering (Task 3) prevents the `ee7a0905` regression class (named structs before anonymous typedefs).

6. **Algorithm verification:** `fieldEmbedsByValue` excludes `optional_type` and `error_union_type` — they are handled by wrapper propagation (Phase B). This correctly classifies `?*T` as pointer-only and `?Struct` as value-embedding. `isValueDependency` (layout dep graph, in type_registry.zig) includes those kinds — the two functions serve different architectural layers and the naming is unambiguous.
