# Z98 Win9x Calling-Convention Prelude — Design (Track 1)

**Date:** 2026-09-13
**Branch:** `zig1_improvements`
**HEAD:** `f755dbed` (parent `14129e68`)

**Parent spec:** [`2026-09-13-async-prelude-and-feasibility-design.md`](./2026-09-13-async-prelude-and-feasibility-design.md) — this subspec derives from its §6 (non-negotiable concerns), §8 (Prelude A calling convention), §9 (Prelude B ban), §10 (`extern struct`), §11 (inline asm), and §14.2 Track 1.

**Sibling subspecs:**
- [`2026-09-13-async-compiler-core-design.md`](./2026-09-13-async-compiler-core-design.md)
- [`2026-09-13-std-async-design.md`](./2026-09-13-std-async-design.md)
- [`2026-09-13-coroutine-integration-design.md`](./2026-09-13-coroutine-integration-design.md)

**Previous subspec:** none (first subspec in the sequence).
**Next subspec:** async-compiler-core.

**Plan:** [`../plans/2026-09-13-win9x-calling-convention-plan.md`](../plans/2026-09-13-win9x-calling-convention-plan.md)

**Status:** draft, amendable in place.

---

## 1. Scope

Track 1 implements the Win9x calling-convention prelude (Prelude A, §8 of the parent spec; operator ruling m1155-A). It is independent of the async track and can land first.

1. Parse and **capture** the currently-discarded `extern` string (`sf/src/parser.zig:1554-1556`).
2. Accept the strings `"c"`/`"cdecl"` (both = `cdecl`, the default) and `"stdcall"` on:
   - extern function declarations: `extern "stdcall" fn MessageBoxA(...) i32;`
   - function-pointer types: `const Cb = extern "stdcall" fn(i32) void;`
3. Unknown string -> new diagnostic `ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045` (explicit `= 3045`, parent spec §12.7).
4. **Represent** the convention on the function type (`FnPayload.flags_packed` free bit1) so a `fn(...)T` value and its pointer typedef agree, and thread it into `LirFunction` so the emitter can act on it.
5. **Emit** the convention on the extern prototype/definition and on the fn-pointer typedef, portably (gcc `__attribute__((stdcall))`, MSVC/Watcom `__stdcall`) and only for `stdcall` (default `cdecl` emits nothing, preserving linux byte-identity).
6. **Force a prototype** for an extern function when a convention is present (today the predicate `f.is_extern==0 or f.is_variadic!=0` at `sf/src/c89_emit.zig:2418,2566` suppresses the prototype for non-variadic externs).
7. Reject variadic `stdcall` (i386 stdcall cannot be variadic).
8. **Migrate** `sf/src/std_net.zig` and the related Win32 extern std calls to `extern "stdcall"` so they do not conflict with the real `winsock.h` declarations once (6) forces prototypes (m1155-A; exact list in §3.7).
9. Add the `ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017` diagnostic **code/plumbing only**; the enforcement itself lands in Track 2 (Prelude B), because it depends on `is_suspending`.

`extern struct` is out of scope (parent spec §10: Z98 normal layout matches the Win32 i686 ABI). Inline assembly stays documented unsupported (§11).

## 2. Non-goals

- No async/suspending work; no `is_suspending`. `ERR_3017` is only reserved here.
- No `extern struct`, no `#pragma pack`, no ABI oracle re-run (done: §15.6).
- No inline asm support.
- No new convention strings beyond `c`/`cdecl`/`stdcall`; no `fastcall`/`thiscall`/`vectorcall`.
- No change to the emitted C for any program that does not use `stdcall` (linux gates byte-identical).
- No MSVC/Watcom runtime harness; portability is proven by emission inspection plus mingw `-c` (and `wine` only if a runnable check is cheap).

## 3. Detailed design

### 3.1 Capture (parser)

**Current state.** `parserParseExternDecl` (`sf/src/parser.zig:1552-1564`) advances past an optional `string_literal` and drops it (`:1554-1556`). Only the `0x04` `is_extern` bit survives (`parser.zig:1580`, `ast.zig:118`, `type_registry.zig:599`). No convention token exists anywhere; the only literal in the compiler is `__cdecl` on the `mainCRTStartup` bootstrap shim (`c89_emit.zig:1021`).

**Classification.** Add one pure helper in `parser.zig`:

```zig
const CALL_CONV_CDECL: u8 = 0;
const CALL_CONV_STDCALL: u8 = 1;
const CALL_CONV_INVALID: u8 = 2;

fn parserClassifyCallConv(self: *Parser, text: []const u8) u8 {
    if (text.len == 1 and text[0] == 'c') return CALL_CONV_CDECL;
    if (text.len == 5 and text[0] == 'c' and text[1] == 'd' and text[2] == 'e'
        and text[3] == 'c' and text[4] == 'l') return CALL_CONV_CDECL;
    if (text.len == 7 and text[0] == 's' and text[1] == 't' and text[2] == 'd'
        and text[3] == 'c' and text[4] == 'a' and text[5] == 'l'
        and text[6] == 'l') return CALL_CONV_STDCALL;
    return CALL_CONV_INVALID;
}
```

`parserParseExternDecl` captures the string and threads it to `parserParseFnDecl`:

```zig
fn parserParseExternDecl(self: *Parser, is_pub: bool) ParserError!u32 {
    _ = parserAdvance(self);
    var call_conv: u8 = CALL_CONV_CDECL;
    if (parserPeek(self).kind == TokenKind.string_literal) {
        var str_tok = parserAdvance(self);
        var text = string_interner_mod.stringInternerGet(self.interner, str_tok.value.string_id);
        call_conv = parserClassifyCallConv(self, text);
        if (call_conv == CALL_CONV_INVALID) {
            var ucv: []const u8 = "unknown calling convention in `extern`";
            parserAddErrorCode(self, str_tok, 3045, ucv);
            call_conv = CALL_CONV_CDECL;
        }
    }
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.kw_fn) return parserParseFnDecl(self, is_pub, true, false, false, call_conv);
    if (tok.kind == TokenKind.kw_const) return parserParseVarDecl(self, false, is_pub, true, false);
    if (tok.kind == TokenKind.kw_var) return parserParseVarDecl(self, true, is_pub, true, false);
    var e_msg: []const u8 = "expected fn/const/var after extern";
    parserAddError(self, tok, e_msg);
    return error.UnexpectedToken;
}
```

`parserParseFnDecl` (`parser.zig:1575`) gains a trailing `call_conv: u8` parameter; `parserParsePubDecl`/module-root non-extern call sites pass `CALL_CONV_CDECL` (`parser.zig:1412,1542,1543,1544,1546,1547,1568,1569,1570`). Non-extern declarations never carry a convention.

**Error helper.** `parserAddError` hardcodes code `2000` (`parser.zig:253-256`). Add a sibling that takes the code:

```zig
pub fn parserAddErrorCode(self: *Parser, tok: Token, code: u16, msg: []const u8) void {
    diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), code,
        self.file_id, tok.span_start, tok.span_start + @intCast(u32, tok.span_len), msg);
}
```

**Declaration storage.** Add `call_conv: u8` to `FnProto` **between `params_count` and `return_type_node`** so `@sizeOf(FnProto)` stays `16` (asserted at `sf/src/tests/ast_tests.zig:54`): `name_id`(0-4), `params_start`(4-8), `params_count`(8-10), `call_conv`(10-11), pad(11-12), `return_type_node`(12-16). `parserParseFnDecl` sets it at `parser.zig:1648`. All `FnProto{...}` initializers gain the field: `parser.zig:1648`, `sf/src/tests/test_analyzer_bin.zig:35,53,79,1298`.

### 3.2 Capture (function-pointer types)

The type form `extern "stdcall" fn(i32) void` is not parsed today: `parserParseType` (`parser.zig:1072-1112`) has no `kw_extern` branch and the expression primary dispatch treats `fn` as a type expression (`parser.zig:437`).

Add `parserParseExternFnType`:

```zig
fn parserParseExternFnType(self: *Parser) ParserError!u32 {
    _ = parserAdvance(self); // extern
    var call_conv: u8 = CALL_CONV_CDECL;
    if (parserPeek(self).kind == TokenKind.string_literal) {
        var str_tok = parserAdvance(self);
        var text = string_interner_mod.stringInternerGet(self.interner, str_tok.value.string_id);
        call_conv = parserClassifyCallConv(self, text);
        if (call_conv == CALL_CONV_INVALID) {
            var ucv: []const u8 = "unknown calling convention in `extern`";
            parserAddErrorCode(self, str_tok, 3045, ucv);
            call_conv = CALL_CONV_CDECL;
        }
    }
    var nt = parserPeek(self);
    if (nt.kind != TokenKind.kw_fn) {
        var efm: []const u8 = "expected 'fn' after extern calling convention";
        parserAddError(self, nt, efm);
        return error.UnexpectedToken;
    }
    return parserParseFnType(self, call_conv);
}
```

Wire it in both positions:
- `parserParseType` (`parser.zig:1072`): add `if (tok.kind == TokenKind.kw_extern) return parserParseExternFnType(self);` before the `kw_fn` branch.
- expression primary (near `parser.zig:437`): add the same branch before `if (tok.kind == TokenKind.kw_fn) return parserParseFnType(self, CALL_CONV_CDECL);`.

`parserParseFnType` (`parser.zig:1188`) gains a `call_conv: u8` parameter and passes it as the node `flags` bit0 to `astStoreAddNode(..., AstKind.fn_type, flags, ...)` at `parser.zig:1226`:

```zig
var fn_flags: u8 = 0;
if (call_conv == CALL_CONV_STDCALL) fn_flags = fn_flags | @intCast(u8, 0x01);
return ast_mod.astStoreAddNode(self.store, AstKind.fn_type, fn_flags, ...);
```

Bit0 of `AstNode.flags` for `fn_type` nodes is unused today (`ast.zig:116-127`; the `fn_type` resolver at `type_resolver.zig:933-991` ignores node flags), so this is collision-free.

### 3.3 Represent (type registry + LIR)

**Fn type.** `FnPayload` (`type_registry.zig:84`) keeps `flags_packed` bit0 = variadic; bit1 becomes `CALL_CONV_STDCALL`:

```zig
pub const FN_FLAG_VARIADIC: u8 = 1;
pub const FN_FLAG_STDCALL: u8 = 2;
```

`typeRegistryGetOrCreateFn` (`type_registry.zig:588`) gains a trailing `call_conv: u8` parameter and packs `flags_packed = is_variadic | (if (call_conv == 1) 2 else 0)`. The dedup condition (`:594`) gains a convention comparison so two fn types differing only by convention do not silently alias a shared payload:

```zig
if (it.kind == TypeKind.fn_type and it.name_id == name_id
    and self.fn_items[self.types_items[i].payload_idx].module_id == module_id
    and (self.fn_items[self.types_items[i].payload_idx].flags_packed & 2)
        == @intCast(u8, if (call_conv == 1) 2 else 0)) {
    return @intCast(u32, i);
}
```

Callers:
- `type_resolver.zig:1324` (fn_decl): pass `proto.call_conv`.
- `type_resolver.zig:988` (anonymous `fn(...)` type): pass `if ((node.flags & 1) != 0) 1 else 0`.
- `sf/src/semantic_analyzer.zig:481,491,497,637,645,650` (function-symbol type materialization): pass `proto.call_conv` where a proto is in hand; otherwise `0`.
- `sf/src/tests/test_semantic_bin.zig:871,915,1042`: pass `0`.

`Type.flags` free bits are `2, 3, 5, 6, 7`; bit0 = fn-ptr-used (`type_registry.zig:612-614`), bit1 = `VOLATILE_FLAG` (`:76`), bit4 = packed (`type_registry.zig:1057`, read `type_resolver.zig:133`). No `Type.flags` change is needed.

**LIR.** Add `call_conv: u8` to `LirFunction` (`lir.zig:494-513`), set from `proto.call_conv` where lowering reads the proto (`lower.zig:6603`; `is_extern` is set at `:6618`, `is_variadic` at `:6625`). Serialize it in the function header: add `wU8(s, src_fn.call_conv)` after `wU8(s, src_fn.is_variadic)` in `lir_stream.zig:117`, mirror it in the read path (`lir_stream.zig:187-308`) and in `emptyLirFunction` (`:162-175`). The function header grows by one byte; `expected_len` is derived from `write_offset` (`lir_stream.zig:158`) so no length constant changes. This is the only reason Track 1 moves the fixed point beyond the emitter text.

### 3.4 Emit

Three sites in `c89_emit.zig`:

- `emitFunctionSignature` (`:2134-2197`) — extern definition path. After writing `ret_c` (`:2151-2152`), if `stdcall` write the `Z98_STDCALL` macro + space before the function name.
- `emitFunctionForwardDecl` (`:2199-2241`) — prototype writer. Same placement: after `ret_c` (`:2200-2203`).
- `emitFnPtrType` (`:1882-1911`) — typedef writer. Read `fp.flags_packed & FN_FLAG_STDCALL` and, if set, write `Z98_STDCALL` between `" ("` (`:1889`) and `"*"`: `typedef void (Z98_STDCALL *Cb)(int);`.

A tiny helper keeps all three sites DRY:

```zig
fn emitCallConv(emitter: *C89Emitter, call_conv: u8) void {
    if (call_conv == @intCast(u8, 1)) {
        var cc: []const u8 = "Z98_STDCALL ";
        bufferedWriterWrite(&emitter.writer, cc);
    }
}
```

**Forced prototype.** Change the predicate at `c89_emit.zig:2418` and `:2566` from

```zig
if (f.is_extern == @intCast(u8, 0) or f.is_variadic != @intCast(u8, 0)) {
```

to

```zig
if (f.is_extern == @intCast(u8, 0) or f.is_variadic != @intCast(u8, 0) or f.call_conv != @intCast(u8, 0)) {
```

This is rule A.4 in the parent spec §8: a convention only takes effect if the extern declaration is visible at the call site.

**Portability (`Z98_STDCALL`).** Add to the `zig_compat.h` compatibility layer, in **both** the canonical header `sf/src/include/zig_compat.h` and its embedded copy in `sf/src/emit_support.zig` (`emitZigCompatHSupport`, `:17-56`; the hand-written bytes verified by `scripts/check_emit_support.sh`):

```c
#if !defined(_WIN32)
#define Z98_STDCALL
#elif defined(_MSC_VER) || defined(__WATCOMC__)
#define Z98_STDCALL __stdcall
#else
#define Z98_STDCALL __attribute__((stdcall))
#endif
```

Properties:
- On a non-Windows target the macro expands to nothing, so a `stdcall` declaration compiles as its cdecl form (safe; `std_net`'s Winsock calls are guarded by `@isWindows()` at runtime).
- On Win32 mingw/gcc it is `__attribute__((stdcall))`; on MSVC/Watcom it is `__stdcall`.
- It is referenced only when the source wrote `stdcall`, so no program that uses only default `cdecl` changes a single emitted byte.

`check_emit_support.sh` compares the emitted `zig_compat.h` byte-for-byte with `sf/src/include/zig_compat.h`; keeping both edits identical keeps that gate green with no re-baseline.

### 3.5 Typing rules

- A `fn(...)T` of one convention must not coerce to or assign to one of another. Extend the fn-pointer assignability arm (`type_registry.zig:1147-1166`) so the comparison also requires the convention bits to match:

```zig
and (src_f.flags_packed & @intCast(u8, 2)) == (tgt_f.flags_packed & @intCast(u8, 2))
```

- `sf/src/coercion.zig:112` currently rejects all `fn_type` targets; the mismatch must remain a clean frontend error (`error[3000]` type mismatch) with 0 `.c` emitted, not an ICE.
- Variadic `stdcall` is invalid. If `is_variadic` and convention is `stdcall` on the same declaration, emit `ERR_3012_VARARGS_INVALID` (`diagnostics.zig:42`) during semantic analysis (the fn type is built at `type_resolver.zig:1304-1324`; the check can live in `semantic_analyzer.zig` beside the fn-symbol resolution). Variadic `cdecl` stays legal (`extern "c" fn printf(fmt: [*]const u8, ...) i32;`).

### 3.6 Portability matrix

| Source | gcc (mingw, `_WIN32`, `__GNUC__`) | MSVC (`_MSC_VER`) | Watcom (`__WATCOMC__`) | gcc linux (`! _WIN32`) |
|---|---|---|---|---|
| `extern "c" fn f()` / `extern "cdecl" fn f()` / `extern fn f()` | nothing | nothing | nothing | nothing |
| `extern "stdcall" fn f()` | `__attribute__((stdcall))` | `__stdcall` | `__stdcall` | nothing |
| `extern "stdcall" fn(i32) void` (typedef) | `__attribute__((stdcall))` | `__stdcall` | `__stdcall` | nothing |

### 3.7 `std_net` migration list (operator ruling m1155-A)

Once A.4 forces prototypes, every `std_net` Win32 extern must be declared `extern "stdcall"` or the emitted prototype conflicts with `winsock.h`. Exact edit list in `sf/src/std_net.zig`:

| Lines | Symbols |
|---|---|
| `:18-19` | `htons`, `htonl` |
| `:35-38` | `socket`, `bind`, `listen`, `setsockopt` |
| `:39-44` | `accept_os`, `connect_os`, `send_os`, `recv_os`, `select_os`, `close_os` |
| `:45-47` | `closesocket`, `WSAStartup`, `WSACleanup` |

The `_os` aliases are `#define`d to the real Winsock identifiers by `sf/src/include/net_prelude.h` (`:26-31`); the convention must be on the Z98 declaration. On linux `Z98_STDCALL` is empty, so the `net_prelude.h` libc declarations stay cdecl-compatible. `net_prelude.h` itself does not change.

The compiler's own Win32 calls in `sf/src/include/zig_pal.c` are real C that includes `<windows.h>` (`:7`) and are **not** migrated (parent spec §15.5).

## 4. Interfaces

Exact names and signatures this track produces (Track 2 consumes only the implemented surface, not internals):

```zig
// sf/src/parser.zig
const CALL_CONV_CDECL: u8 = 0;
const CALL_CONV_STDCALL: u8 = 1;
const CALL_CONV_INVALID: u8 = 2;
fn parserClassifyCallConv(self: *Parser, text: []const u8) u8;
fn parserParseExternFnType(self: *Parser) ParserError!u32;
fn parserParseFnType(self: *Parser, call_conv: u8) ParserError!u32;
fn parserParseFnDecl(self: *Parser, is_pub: bool, is_extern: bool, is_test: bool, is_export: bool, call_conv: u8) ParserError!u32;
pub fn parserAddErrorCode(self: *Parser, tok: Token, code: u16, msg: []const u8) void;

// sf/src/ast.zig
pub const FnProto = struct {
    name_id: u32,
    params_start: u32,
    params_count: u16,
    call_conv: u8,        // NEW; between params_count and return_type_node (keeps @sizeOf == 16)
    return_type_node: u32,
};

// sf/src/type_registry.zig
pub const FN_FLAG_VARIADIC: u8 = 1;
pub const FN_FLAG_STDCALL: u8 = 2;
pub fn typeRegistryGetOrCreateFn(self: *TypeRegistry, name_id: u32, module_id: u32,
    is_extern: u8, is_variadic: u8, params_start: u32, params_count: u16,
    return_type: TypeId, call_conv: u8) u32;   // NEW trailing param

// sf/src/lir.zig
pub const LirFunction = struct { ..., call_conv: u8 };

// sf/src/c89_emit.zig
fn emitCallConv(emitter: *C89Emitter, call_conv: u8) void;

// sf/src/diagnostics.zig (explicit values; never bare members)
ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045,
ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017,   // code/plumbing only; enforced in Track 2
```

## 5. Diagnostics

| Code | Name | Trigger | Site |
|---|---|---|---|
| `3045` | `ERR_3045_UNKNOWN_CALLING_CONVENTION` | `extern "<not c/cdecl/stdcall>"` on a declaration or fn-pointer type | `parserParseExternDecl`, `parserParseExternFnType` |
| `3012` | `ERR_3012_VARARGS_INVALID` | variadic `stdcall` declaration | `semantic_analyzer.zig` fn-symbol resolution |
| `3000` | `ERR_3000_TYPE_MISMATCH` | fn-pointer assignment across conventions | `type_registry.zig:1153-1157` / `coercion.zig:112` |
| `3017` | `ERR_3017_SUSPENDING_FUNCTION_POINTER` | reserved; not triggered in Track 1 | Track 2 (Prelude B) |

All members are appended to `ErrorCode` (`diagnostics.zig:10-73`) with explicit `= NNNN` values, and the parallel `pub const ERR_...: u16 = NNNN;` block (`diagnostics.zig:75+`) gains matching constants. `ERR_3048_CANNOT_READ_FILE = 3048` (`:72`) and every auto-incremented tail code are preserved.

## 6. Testing

Fixtures live under `repro/mi_matrix/` so `scripts/corpus/list_corpus_dirs.sh` picks them up. Classification follows `docs/sf/QUICK_REF.md:134-154` (gcc exit code, never empty-stderr).

| Fixture | Convention | Gate |
|---|---|---|
| `callconv_default_cdecl_xmod` | `extern fn` (no string) | dump rc=0, gcc rc=0, runtime rc=0, no `Z98_STDCALL` |
| `callconv_explicit_cdecl_xmod` | `extern "c"` / `extern "cdecl"` | dump rc=0, emission byte-equal to the no-string form |
| `callconv_stdcall_decl_xmod` | `extern "stdcall" fn` | `-osw` dump contains the forced prototype and `Z98_STDCALL`; mingw `-c` rc=0 |
| `callconv_stdcall_fnptr_xmod` | `const Cb = extern "stdcall" fn(i32) void` | `-osw` dump typedef is `... (Z98_STDCALL *Cb)(...)`; mingw `-c` rc=0 |
| `callconv_unknown_green_xmod` | `extern "fastcall"` | clean reject `error[3045]`, 0 `.c` emitted (green-guard) |
| `callconv_fnptr_mismatch_green_xmod` | assign stdcall fn ptr to cdecl fn ptr | clean reject `error[3000]`, 0 `.c` (green-guard) |
| `callconv_stdcall_variadic_green_xmod` | `extern "stdcall" fn f(...)` | clean reject `error[3012]`, 0 `.c` (green-guard) |

Gate commands use the binding flag set: `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; compiler builds only via `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`; emission support via `scripts/check_emit_support.sh <zig1>`; the corpus via `bash scripts/corpus/list_corpus_dirs.sh`. Default `cdecl` byte-identity is gated by the corpus zero-class-change sweep plus the self-emission N-hop closure (`hop2 == hop3`).

`newgreen` expectations are recorded in `repro/mi_matrix/EXPECTED_FAIL.md` (bump at closeout only).

## 7. Risks

- **i386 `__stdcall` name decoration** (`_name@N`): libraries link against the decorated symbol. This is the intended Win32 ABI; no Z98 linker logic changes (the emitted C is compiled by the platform toolchain). Windows links were already relying on `winsock.h`; the migration aligns Z98 prototypes with it.
- **gcc attribute acceptance:** `__attribute__((stdcall))` is x86-gcc only; the gates are `-m32`. On `! _WIN32` the macro expands empty, so 64-bit linux is unaffected.
- **`FnPayload` dedup aliasing:** two same-name fn types in one module still cannot differ, but anonymous `fn(...)T` types can; the dedup key now includes the convention bit (§3.3), preventing a silent shared-payload mutation.
- **Stream header growth:** the extra `call_conv` byte in `lir_stream` must be mirrored in both the read path and `emptyLirFunction`; a mismatch is caught immediately by the N-hop fixed-point closure (a wrong byte count changes every hop hash).
- **`check_emit_support.sh`:** `zig_compat.h` edits must land identically in `sf/src/include/zig_compat.h` and `sf/src/emit_support.zig` or that gate fails.
- **`std_net` linux compatibility:** the migration is safe only because `Z98_STDCALL` is empty off-Windows; do not emit a raw `__attribute__((stdcall))` token that survives on linux.
- **Bootstrap staging:** new `sf/src` code must be compilable by the current seed. The new syntax (`extern "stdcall"`) appears only in `std_net.zig`/fixtures, which are not in the compiler's import graph and are not compiled during `build_from_seed.sh`; `sf/src` itself uses only default cdecl.

## 8. Dependencies

- **Consumes:** nothing from other tracks. Track 1 can start at the current fixed point `1467d932a876402f40a56316dfcad0e5` (seed v10 `ca18fc9f…`).
- **Produces:** an implemented calling-convention surface — `extern "stdcall"`/`"cdecl"` on extern declarations and fn-pointer types, the `FnPayload.flags_packed` convention bit, the `LirFunction.call_conv`/stream byte, forced extern prototypes, the `Z98_STDCALL` portability macro, and `ERR_3045`. Track 2 relies on this surface (and on the reserved `ERR_3017` code) for the Prelude B ban; the ban's `is_suspending` enforcement lands in Track 2.
