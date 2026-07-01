## Task 1 Report: Category 1 void-payload diagnostic markers

### Locations instrumented

| Location | Line | Marker | Purpose |
|----------|------|--------|---------|
| `emitOptionalType` | 1227 | `INSTA:optt<tid>` | Records optional payload type_id |
| `unwrap_error_payload` | 3099 | `INSTA:eup` | unwrap_error_payload LIR path |
| `unwrap_error_code` | 3109 | `INSTA:euc` | unwrap_error_code LIR path |
| `unwrap_optional` | 3192 | `INSTA:optu` | unwrap_optional LIR path |
| `wrap_optional` | 2943 | `INSTA:optw` | wrap_optional LIR path |
| `load_field` tagged_union | 2401 | `INSTA:tulf<tid>` | Records result type in TU load_field |

### Build result

```
gcc error count: 0 (expected 0)
```

### Marker output per repro

**eu_void_payload:**
```
INSTA:euc
INSTA:eup
```
Both error union unwrap paths fire. Void-payload error union confirmed.

**optional_void:**
```
(no INSTA markers)
```
`?void` does NOT go through `emitOptionalType` or any optional instruction code path. The compiler treats void-payload optional as a special case (emitted as `void` directly, not as `{void value; int has_value;}`). This IS the gap — confirms that void-payload optional bypasses normal optional handling.

**tu_void_prong:**
```
INSTA:tulf1
INSTA:tulf6
```
`tulf1` = TYPE_VOID result (tagged union load with void prong). `tulf6` = non-void prong result. Confirms void-prong path is taken.

### Commit

See git log for commit hash.
