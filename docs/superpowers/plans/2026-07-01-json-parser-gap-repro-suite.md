# JSON Parser Gap Reproduction Suite

> **Goal:** Create 5 minimal repro programs under `repro/` that each isolate a single pipeline gap found in json_parser compilation at baseline 5b HEAD (commit 9c40be74).

**Tech Stack:** zig0 C89 bootstrap compiler (Z98 dialect) → gcc 32-bit C89

**Build command:**
```
./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1
```

**Repro compile command:**
```
$OUT/zig1 --dump-c89 repro/<gap_dir>/main.zig > /tmp/repro.c
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/repro.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/repro 2>&1 | grep 'error:'
```

**Gate for each repro:** gcc produces ONLY the targeted error type(s). No other errors.

---

## File Structure

```
repro/
  eu_void_payload/      main.zig    (Gap A)
  var_declared_void/    main.zig    (Gap B)
  optional_non_struct/  main.zig    (Gap C)
  zT_1_undeclared/      main.zig    (Gap D)
  tagged_field_path/    main.zig    (Gap E)
```

---

## Baseline Errors (8 unique gcc errors, 5 categories)

From json_parser build at commit 9c40be74:

1. `'zT_08A61393_EU_1' has no member named 'data'` — EU void-payload `.data` access (16 instances)
2. `variable or field 'zT_10' declared void` — void-typed local
3. `variable or field 'f' declared void` — void-typed local
4. `request for member 'has_value' in something not a structure or union` — optional on non-struct (cascade from void)
5. `request for member 'value' in something not a structure or union` — cascade
6. `'zT_1' undeclared` — TYPE_VOID typedef missing
7. `'zT_E9CE9840_JsonValue' has no member named 'key'` — tagged union prong capture field path
8. `'zT_E9CE9840_JsonValue' has no member named 'value'` — tagged union prong capture field path

---

## Gap A: EU void-payload `.data` access

**Root cause:** `c89_emit.zig:3105` and `:3116` — `unwrap_error_payload` and `unwrap_error_code` always emit `.data.payload`/`.data.err`. But void-payload error unions have typedef `{int err; int is_error;}` with no `data` member (line 1263-1268). The `wrap_error_ok`/`wrap_error_err` already handle this (lines 3125, 3154), but the unwrap paths do not.

**Fix area:** `sf/src/c89_emit.zig` — in `unwrap_error_payload` and `unwrap_error_code`, check payload==void_type and emit `.err`/`.is_error` directly instead of `.data.err`/`.data.payload`.

### Repro: `repro/eu_void_payload/main.zig`

```zig
const MyError = error {
    Foo,
    Bar,
};

fn mayFail() MyError!void {
    return error.Foo;
}

pub fn main() void {
    mayFail() catch |err| {
        _ = err;
    };
}
```

**Expected gcc errors:** ONLY `zT_<hash>_EU_<N>' has no member named 'data'` — no other errors.

---

## Gap B: Variable declared void

**Root cause:** Lowerer emits temps with TYPE_VOID when void-returning functions are assigned to variables. `c89_emit.zig:3281` uses `getCTypeName(dl.type_id)` which returns "void" for TYPE_VOID — producing `void x;` which is illegal C89 (incomplete type cannot be completed). The lowerer should skip emission for void-typed variables or the emitter should skip them.

**Fix area:** `sf/src/c89_emit.zig:3263-3289` — skip `decl_local` emission when `dl.type_id == TYPE_VOID`. Or `sf/src/lower.zig:316` — don't create temps for void-typed expressions.

### Repro: `repro/var_declared_void/main.zig`

```zig
fn noop() void {
    return;
}

pub fn main() void {
    var x = noop();
    _ = x;
}
```

**Expected gcc errors:** ONLY `variable or field 'zT_<N>' declared void` (or `'z_<' declared void`) — no other errors.

---

## Gap C: Optional on non-struct

**Root cause:** Cascade from void typing. When a type is inferred as void and then wrapped in optional (`?void`), the optional's `.has_value`/`.value` access is emitted on a non-struct type. Auto-fixed after Gap B is resolved, but isolated repro confirms the cascade.

**Fix area:** Auto-resolved by Gap B fix. If needed independently: `sf/src/c89_emit.zig:3185` check for void payload in optional unwrap.

### Repro: `repro/optional_non_struct/main.zig`

```zig
fn noop() void {
    return;
}

pub fn main() void {
    var val = noop();
    var opt: ?@TypeOf(val) = null;
    if (opt) |v| {
        _ = v;
    }
}
```

**Alternative simpler repro** (may work on its own):

```zig
pub fn main() void {
    var opt: ?void = null;
    if (opt) |v| {
        _ = v;
    }
}
```

**Expected gcc errors:** `request for member 'has_value' in something not a structure or union` OR `request for member 'value' in something not a structure or union`. If Gap B fix has already landed, this may produce 0 errors; in that case, skip or mark as "fixed-by-B".

---

## Gap D: TYPE_VOID typedef missing (zT_1)

**Root cause:** TYPE_VOID (type id 1) is referenced in C output (e.g., as a struct field type in `?void` or `*void` composed types) but its C typedef (`typedef void zT_1;`) is never emitted because pass 2 skips void_type primitives (c89_emit.zig:805, 854). When the mangled name `zT_1` appears as a type reference in C but has no typedef, gcc errors.

**Fix area:** `sf/src/c89_emit.zig` — ensure TYPE_VOID gets a typedef emitted when referenced as a C name. Add emission in `emitSpecialTypes` pass 2 (or pass 1 forward declarations) when TYPE_VOID is found in the sorted type array or when any emitted type references it by its C name.

### Repro: `repro/zT_1_undeclared/main.zig`

```zig
pub fn main() void {
    var p: ?void = null;
    _ = p;
}
```

**Expected gcc errors:** `'zT_1' undeclared` (or `'zT_1' does not name a type`).

---

## Gap E: Tagged union prong capture field path

**Root cause:** When a switch prong captures a tagged union variant whose payload is a struct (e.g., `JsonValue.Object` → `[]JsonItem`), the lowerer emits `load_field` with `field_id=1` (payload union) on the tagged union base, and sets `temp_variant_sub_field=0`. The emitter at `c89_emit.zig:2390-2419` resolves this to `.payload.<variant_name>._<subfield_idx>`. But subsequent field accesses on the capture variable (e.g., `.key` on a `JsonItem` struct member) may resolve against the outer tagged union struct instead of the captured inner struct, because the temp's hoisted type is tracked as the tagged union type rather than the capture's inner field type.

In the json_parser, `main.zig:59` iterates `for (obj) |item, i|` where `obj: []JsonItem` and `item: JsonItem`. Accessing `item.key` should hit the `JsonItem` struct. The error `'zT_E9CE9840_JsonValue' has no member named 'key'` suggests the emitter is resolving field access against the outer `JsonValue` tagged union struct instead of the `JsonItem` struct captured from the Object variant payload.

**Fix area:** `sf/src/c89_emit.zig:2380-2419` (load_field on tagged_union and struct types) — ensure field access on a captured prong variable resolves against the inner payload struct, not the outer tagged union. Also check `sf/src/lower.zig:2309-2315` — the `payload_temp` type is `fe.type_id` which should be correct, but the hoisted temp tracking may need verification.

### Repro: `repro/tagged_field_path/main.zig`

```zig
const Item = struct {
    key: []const u8,
    value: i32,
};

const MyUnion = union(enum) {
    Empty,
    WithData: Item,
    Other: i32,
};

pub fn main() void {
    var val: MyUnion = MyUnion{ .WithData = Item{ .key = "hello", .value = 42 } };
    var k: []const u8 = undefined;
    switch (val) {
        .Empty => {},
        .WithData => |data| {
            k = data.key;
        },
        .Other => |n| {
            _ = n;
        },
    }
    _ = k;
}
```

**Expected gcc errors:** `'zT_<hash>_MyUnion' has no member named 'key'` — field access resolved against outer tagged union struct instead of inner `Item` struct.

---

## Task Breakdown

- [ ] Task 0: Write plan doc (this file)
- [ ] Task 1: Create `repro/` directory structure
- [ ] Task 2: Repro Gap A — `repro/eu_void_payload/main.zig`
- [ ] Task 3: Repro Gap B — `repro/var_declared_void/main.zig`
- [ ] Task 4: Repro Gap C — `repro/optional_non_struct/main.zig`
- [ ] Task 5: Repro Gap D — `repro/zT_1_undeclared/main.zig`
- [ ] Task 6: Repro Gap E — `repro/tagged_field_path/main.zig`
- [ ] Task 7: Build zig1 from current HEAD, verify each repro produces only targeted errors
- [ ] Task 8: Document results in repro directories (gcc error output, targeted count)

---

## Self-Review

1. **Spec coverage:** All 8 errors across 5 gap categories covered. Each repro is minimal — single function, minimal types, no imports.
2. **Placeholder scan:** No TBD or TODO. Each repro has exact source code. Verification commands are specified.
3. **Type consistency:** All repros use `pub fn main() void` entry point, compatible with zig1's `--dump-c89` mode. No external imports needed.
4. **Risk management:** Gap C repro may produce 0 errors after Gap B fix (by-design cascade). Documented as such. Gap D repro may or may not trigger `zT_1` depending on whether `?void` struct typedef path hits the void_type check in `getCTypeName`. If not triggered, will adjust repro.
5. **Gap D verification strategy:** `?void` creates an `optional_type` with `payload=TYPE_VOID`. The `emitOptionalType` function (c89_emit.zig:1226-1253) calls `getCTypeName` on the payload. If `getCTypeName(TYPE_VOID)` returns "void" correctly, the optional typedef will be `struct { void payload; int has_value; }` which is valid C and won't reference `zT_1`. The `zT_1` trigger may require a different composed type (e.g., a struct with a void field, an array of void). If the `?void` repro doesn't trigger, replace with `struct { x: void }` or `[1]void` pattern.
