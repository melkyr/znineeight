# for_in_array -- RED: array for-in load_field .ptr/.len gap

## Form
Array for-in summing elements: `for (arr) |v| { sum += v; }`.

## Expected
`60`.

## Actual (RED)
gcc compile error. zig1 emits C that does `load_field(.ptr)` and `load_field(.len)` on an array
type, which has no such fields. gcc error mentions `.ptr`/`.len` members on array type.

Typical error:
```
error: 'struct <anonymous>' has no member named 'ptr'
error: 'struct <anonymous>' has no member named 'len'
```

## Root cause
`sf/src/lower.zig` for-in lowering does not differentiate array from slice when accessing
.ptr/.len fields. For slices, the struct has these fields; for arrays, the type is a
flat aggregate with no such members. The lower.zig for-in path needs to either coerce the
array to a slice first or access array elements by index.

## Cross-links
- `sf/src/lower.zig`: for-in lowering (array vs. slice .ptr/.len access)
