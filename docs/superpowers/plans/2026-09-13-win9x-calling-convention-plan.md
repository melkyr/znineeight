# Z98 Win9x Calling-Convention Prelude Implementation Plan (Track 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `extern "stdcall"`/`extern "cdecl"` on extern function declarations and `fn(...)T` function-pointer types, represent the convention on the function type and LIR, emit it portably on the prototype/definition and fn-pointer typedef, force an extern prototype when a convention is present, reject unknown conventions with `error[3045]`, and migrate the `std_net` Win32 externs.

**Architecture:** One linear track over the existing pipeline. The parser captures the previously-dropped `extern` string and classifies it into a 2-value convention carried on the declaration side table (`FnProto.call_conv`) and on `fn_type` nodes (flags bit0). Type resolution stores the convention on `FnPayload.flags_packed` bit1, keyed into the fn-type dedup so anonymous fn types do not alias. Lowering copies it to `LirFunction.call_conv`, which is serialized in the LIR stream so the emitter can act on it. The emitter writes a `Z98_STDCALL` macro token only for `stdcall`; the macro is `__attribute__((stdcall))` on Win32 gcc, `__stdcall` on MSVC/Watcom, and empty on non-Windows, so linux emission for default-cdecl programs is byte-identical. The forced-prototype predicate at `c89_emit.zig:2418,2566` widens to include non-default conventions.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, `i686-w64-mingw32-gcc`, `wine` (optional), git.

## Global Constraints

- **Baseline (re-verify at Task 1):** HEAD `f755dbed`; compiler fixed point `1467d932a876402f40a56316dfcad0e5`; seed v10 archive md5 `ca18fc9f9af55d58147fcb7ff7a662b6`; corpus 570 = 541 OK / 29 GREEN / 0 FAIL; `repro/mi_matrix/EXPECTED_FAIL.md` header v77 (2026-09-13).
- **`timeout 120` on every binary execution.**
- **Compiler builds only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`; **never invoke `zig0`**. The dump runs from the repo root with the relative `sf/src/main.zig` path (module basename-hash tokens are path-derived). `<out_dir>` must be fresh.
- **gcc flag-set rule (binding):** every `gcc -c` MUST be `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files; `/tmp` scratch is unrestricted). Re-read the target region immediately before every `fastedit`.
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Explicit error codes:** every new `ErrorCode` member is appended with `= NNNN`; never a bare auto-increment member. Preserve `ERR_3048_CANNOT_READ_FILE = 3048` and every existing value.
- **Bootstrap staging:** new `sf/src` code must compile under the current seed. The new `extern "stdcall"` syntax appears only in `sf/src/std_net.zig` and `repro/` fixtures, which are not in the compiler's import graph and are not compiled during `build_from_seed.sh`; `sf/src` itself uses only default cdecl.
- **Runtime gates mandatory** for every affected program (compile-only gates are forbidden), except the declared compile-only `stdcall` fixtures, which cannot run on linux because the symbol does not exist.
- **Spec of record:** `docs/superpowers/specs/2026-09-13-win9x-calling-convention-design.md` (Track 1 subspec); parent `docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md` §8–§11.
- **Seed rotation:** reference compiler rebuilt per the seed model; rotate the seed at closeout via `scripts/seed/archive_seed.sh`.

---

**Sequence:** PREVIOUS plan: none — this is the first implementation plan (spike: `../plans/2026-09-13-async-prelude-and-feasibility-plan.md`). NEXT plan: `../plans/2026-09-13-async-compiler-core-plan.md`. Subspec: [`../specs/2026-09-13-win9x-calling-convention-design.md`](../specs/2026-09-13-win9x-calling-convention-design.md).

## File Structure

**Create (fixtures under `repro/mi_matrix/`, one directory each with `main.zig`):**
- `callconv_default_cdecl_xmod/main.zig` — default/`"c"`/`"cdecl"` declarations emit no convention.
- `callconv_explicit_cdecl_xmod/main.zig` — `"c"` and `"cdecl"` are byte-identical to no-string.
- `callconv_stdcall_decl_xmod/main.zig` — `extern "stdcall" fn` forces a decorated prototype.
- `callconv_stdcall_fnptr_xmod/main.zig` — `extern "stdcall" fn(...)` typedef.
- `callconv_unknown_green_xmod/main.zig` — `extern "fastcall"` clean-rejects `error[3045]`.
- `callconv_fnptr_mismatch_green_xmod/main.zig` — cross-convention fn-ptr assignment clean-rejects `error[3000]`.
- `callconv_stdcall_variadic_green_xmod/main.zig` — variadic `stdcall` clean-rejects `error[3012]`.

**Modify:**
- `sf/src/diagnostics.zig` — add `ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045` and reserve `ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017`.
- `sf/src/parser.zig` — classify/capture the `extern` string; `parserAddErrorCode`; `extern "conv" fn(...)` type form.
- `sf/src/ast.zig` — `FnProto.call_conv`.
- `sf/src/type_registry.zig` — `FN_FLAG_*`, `typeRegistryGetOrCreateFn(..., call_conv)`, dedup key, fn-ptr assignability convention check.
- `sf/src/type_resolver.zig` — pass declaration/node conventions into fn-type creation.
- `sf/src/semantic_analyzer.zig` — pass conventions at the six fn-symbol fn-type call sites; variadic-`stdcall` reject.
- `sf/src/lower.zig` — set `LirFunction.call_conv`.
- `sf/src/lir.zig` — `LirFunction.call_conv`.
- `sf/src/lir_stream.zig` — serialize/deserialize `call_conv`.
- `sf/src/c89_emit.zig` — `emitCallConv`, convention on signature/forward-decl/fn-ptr typedef, forced-prototype predicate.
- `sf/src/include/zig_compat.h` + `sf/src/emit_support.zig` — `Z98_STDCALL` macro (kept byte-identical).
- `sf/src/std_net.zig` — migrate Win32 externs to `extern "stdcall"`.
- `sf/src/tests/ast_tests.zig`, `sf/src/tests/test_analyzer_bin.zig`, `sf/src/tests/test_semantic_bin.zig` — `FnProto.call_conv` initializers / `typeRegistryGetOrCreateFn` call sites.
- `repro/mi_matrix/EXPECTED_FAIL.md` — green-guard entries (closeout bump).
- `docs/sf/QUICK_REF.md` — calling-convention note + new fixed point/seed (closeout).

---

### Task 1: Capture and validate calling conventions in extern declarations

**Files:**
- Create: `repro/mi_matrix/callconv_unknown_green_xmod/main.zig`, `repro/mi_matrix/callconv_default_cdecl_xmod/main.zig`
- Modify: `sf/src/diagnostics.zig:10-73` (+ const block `:75+`), `sf/src/parser.zig:1552-1564,1575-1652`, `sf/src/ast.zig:129-134`, `sf/src/tests/test_analyzer_bin.zig:35,53,79,1298`

**Interfaces:**
- Consumes: nothing.
- Produces: `CALL_CONV_CDECL=0`, `CALL_CONV_STDCALL=1`, `CALL_CONV_INVALID=2`; `parserClassifyCallConv`; `parserAddErrorCode(self, tok, code, msg)`; `FnProto.call_conv: u8`; `ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045`.

- [ ] **Step 1: Write the failing fixtures**

`repro/mi_matrix/callconv_unknown_green_xmod/main.zig`:
```zig
extern "fastcall" fn z98_bad_conv_probe(x: i32) i32;

pub fn main() void {
    _ = z98_bad_conv_probe;
}
```

`repro/mi_matrix/callconv_default_cdecl_xmod/main.zig`:
```zig
extern fn pal_trap() void;
extern "c" fn pal_abort() void;
extern "cdecl" fn pal_print_stderr(s: [*]const u8, n: u32) void;

pub fn main() void {
    var msg: []const u8 = "callconv default\n";
    pal_print_stderr(msg.ptr, @intCast(u32, msg.len));
}
```

- [ ] **Step 2: Build the baseline compiler and observe the RED**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/cc0
mkdir -p /tmp/t1_unknown_base
timeout 120 /tmp/cc0/zig1_5_clean --dump-c89 --output-dir /tmp/t1_unknown_base repro/mi_matrix/callconv_unknown_green_xmod/main.zig; echo "dump rc=$?"
ls /tmp/t1_unknown_base/*.c 2>/dev/null | wc -l
```
Expected RED: `dump rc=0` and ≥1 `.c` — the baseline silently accepts the unknown convention (the string is dropped at `parser.zig:1554-1556`). Record the rc and file count in the commit message body.

- [ ] **Step 3: Implement the diagnostic and parser capture**

`sf/src/diagnostics.zig` — append to `ErrorCode` (before the closing `}` at `:73`, alongside the existing explicit `ERR_3048` at `:72`):
```zig
    ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045,
    ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017,
```
Add the matching constants in the `pub const ...: u16` block:
```zig
pub const ERR_3045_UNKNOWN_CALLING_CONVENTION: u16 = 3045;
pub const ERR_3017_SUSPENDING_FUNCTION_POINTER: u16 = 3017;
```

`sf/src/ast.zig` — change `FnProto` (`:129-134`) to place `call_conv` between `params_count` and `return_type_node` so `@sizeOf(FnProto)` stays `16`:
```zig
pub const FnProto = struct {
    name_id: u32,
    params_start: u32,
    params_count: u16,
    call_conv: u8,
    return_type_node: u32,
};
```

`sf/src/parser.zig` — add above `parserParseExternDecl`:
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

pub fn parserAddErrorCode(self: *Parser, tok: Token, code: u16, msg: []const u8) void {
    diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), code,
        self.file_id, tok.span_start, tok.span_start + @intCast(u32, tok.span_len), msg);
}
```
Replace `parserParseExternDecl` (`:1552-1564`) with:
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
Change the `parserParseFnDecl` signature (`:1575`) to add the trailing `call_conv: u8` parameter, and its `FnProto` initializer (`:1648`) to include it:
```zig
fn parserParseFnDecl(self: *Parser, is_pub: bool, is_extern: bool, is_test: bool, is_export: bool, call_conv: u8) ParserError!u32 {
```
```zig
    var proto: FnProto = FnProto{ .name_id = name_id, .params_start = param_start, .params_count = param_count, .call_conv = call_conv, .return_type_node = ret_type_node };
```
Update every other `parserParseFnDecl` call to pass `CALL_CONV_CDECL` (`parser.zig:1412,1542,1543,1544,1568`; the pub-extern call at `:1546` goes through the new `parserParseExternDecl`).

Update the `FnProto` initializers in the tests to include `.call_conv = @intCast(u8, 0)`: `sf/src/tests/test_analyzer_bin.zig:35,53,79,1298`.

- [ ] **Step 4: Rebuild and verify GREEN (unknown rejected, known accepted)**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/cc1
rm -rf /tmp/t1_unknown_new && mkdir -p /tmp/t1_unknown_new
timeout 120 /tmp/cc1/zig1_5_clean --dump-c89 --output-dir /tmp/t1_unknown_new repro/mi_matrix/callconv_unknown_green_xmod/main.zig 2>/tmp/t1_unknown_new/err.txt; echo "dump rc=$?"
grep -c 'error\[3045\]' /tmp/t1_unknown_new/err.txt
ls /tmp/t1_unknown_new/*.c 2>/dev/null | wc -l
rm -rf /tmp/t1_default && mkdir -p /tmp/t1_default
timeout 120 /tmp/cc1/zig1_5_clean --dump-c89 --output-dir /tmp/t1_default repro/mi_matrix/callconv_default_cdecl_xmod/main.zig 2>/tmp/t1_default/err.txt; echo "dump rc=$?"
```
Expected: unknown fixture `dump rc` nonzero, `error\[3045\]` count `1`, `.c` count `0`; default fixture `dump rc=0`.

- [ ] **Step 5: Commit**

```bash
git add sf/src/diagnostics.zig sf/src/parser.zig sf/src/ast.zig sf/src/tests/ast_tests.zig sf/src/tests/test_analyzer_bin.zig repro/mi_matrix/callconv_unknown_green_xmod repro/mi_matrix/callconv_default_cdecl_xmod
git commit -m "feat(callconv): capture extern calling convention + ERR_3045 (Track1)"
```

---

### Task 2: Represent and emit the convention on the extern prototype

**Files:**
- Create: `repro/mi_matrix/callconv_explicit_cdecl_xmod/main.zig`, `repro/mi_matrix/callconv_stdcall_decl_xmod/main.zig`
- Modify: `sf/src/type_registry.zig:84,588-610,1147-1166`, `sf/src/type_resolver.zig:1324`, `sf/src/semantic_analyzer.zig:481,491,497,637,645,650`, `sf/src/lir.zig:494-513`, `sf/src/lir_stream.zig:110-160,162-175,187-308`, `sf/src/lower.zig:6603-6640`, `sf/src/c89_emit.zig:2134-2241,2418,2566`, `sf/src/include/zig_compat.h`, `sf/src/emit_support.zig`, `sf/src/tests/test_semantic_bin.zig:871,915,1042`

**Interfaces:**
- Consumes: `FnProto.call_conv`, `ERR_3045`.
- Produces: `FN_FLAG_VARIADIC=1`, `FN_FLAG_STDCALL=2`; `typeRegistryGetOrCreateFn(..., call_conv: u8)`; `LirFunction.call_conv: u8`; `emitCallConv(emitter, call_conv)`; the `Z98_STDCALL` macro.

- [ ] **Step 1: Write the fixtures**

`repro/mi_matrix/callconv_explicit_cdecl_xmod/main.zig`:
```zig
extern "c" fn pal_abort() void;
extern "cdecl" fn pal_print_stderr(s: [*]const u8, n: u32) void;

pub fn main() void {
    var msg: []const u8 = "callconv explicit cdecl\n";
    pal_print_stderr(msg.ptr, @intCast(u32, msg.len));
}
```

`repro/mi_matrix/callconv_stdcall_decl_xmod/main.zig`:
```zig
extern "stdcall" fn MessageBoxA(hwnd: *void, text: [*]const u8, cap: [*]const u8, typ: u32) i32;

pub fn main() void {
    if (@isWindows()) {
        _ = MessageBoxA(@ptrCast(*void, @intToPtr(*void, 0)), @ptrCast([*]const u8, @intToPtr([*]const u8, 0)), @ptrCast([*]const u8, @intToPtr([*]const u8, 0)), @intCast(u32, 0));
    }
}
```

- [ ] **Step 2: Run the failing test against the Task-1 compiler**

Run:
```bash
rm -rf /tmp/t2_stdcall_red && mkdir -p /tmp/t2_stdcall_red
timeout 120 /tmp/cc1/zig1_5_clean -osw -o /tmp/t2_stdcall_red repro/mi_matrix/callconv_stdcall_decl_xmod/main.zig; echo "emit rc=$?"
grep -rc 'Z98_STDCALL' /tmp/t2_stdcall_red/ | head
ls /tmp/t2_stdcall_red/*.c | wc -l
```
Expected RED: `emit rc=0` but `Z98_STDCALL` count `0` and no `MessageBoxA` prototype (`int MessageBoxA(...)` absent from the `.h`/`.c`), because the convention is still not represented and non-variadic externs get no prototype (`c89_emit.zig:2418`).

- [ ] **Step 3: Implement representation (type registry, LIR, lowering)**

`sf/src/type_registry.zig` — add next to `VOLATILE_FLAG` (`:76`):
```zig
pub const FN_FLAG_VARIADIC: u8 = 1;
pub const FN_FLAG_STDCALL: u8 = 2;
```
Change `typeRegistryGetOrCreateFn` (`:588`) to take a trailing `call_conv: u8`, pack the bit, and key the dedup:
```zig
pub fn typeRegistryGetOrCreateFn(self: *TypeRegistry, name_id: u32, module_id: u32, is_extern: u8, is_variadic: u8, params_start: u32, params_count: u16, return_type: TypeId, call_conv: u8) u32 {
    var conv_bit: u8 = @intCast(u8, 0);
    if (call_conv == @intCast(u8, 1)) conv_bit = FN_FLAG_STDCALL;
    var i: usize = 0;
    while (i < self.types_len) : (i += 1) {
        var it = self.types_items[i];
        if (it.kind == TypeKind.fn_type and it.name_id == name_id
            and self.fn_items[self.types_items[i].payload_idx].module_id == module_id
            and (self.fn_items[self.types_items[i].payload_idx].flags_packed & FN_FLAG_STDCALL) == conv_bit) {
            return @intCast(u32, i);
        }
    }
    fnAppend(self, FnPayload{ .name_id = name_id, .module_id = module_id, .is_extern = is_extern, .params_start = params_start, .params_count = params_count, .return_type = return_type, .flags_packed = is_variadic | conv_bit });
    // ...unchanged typeRegistryAppend...
}
```
In the fn-pointer assignability arm (`:1153-1156`), add the convention comparison:
```zig
            if (src_f.return_type == tgt_f.return_type
                and src_f.params_count == tgt_f.params_count
                and src_f.is_extern == tgt_f.is_extern
                and (src_f.flags_packed & @intCast(u8, 1)) == (tgt_f.flags_packed & @intCast(u8, 1))
                and (src_f.flags_packed & @intCast(u8, 2)) == (tgt_f.flags_packed & @intCast(u8, 2)))
```

`sf/src/type_resolver.zig` — pass the declaration convention at `:1324`:
```zig
                var tid = type_mod.typeRegistryGetOrCreateFn(env.typereg, proto.name_id, mods[mi].id, is_ext, is_variadic, fn_start, proto.params_count, rt_box[0], proto.call_conv);
```

`sf/src/semantic_analyzer.zig` — append `@intCast(u8, 0)` (or `proto.call_conv` where a proto is in scope) to the six calls at `:481,491,497,637,645,650`; at `:637,645,650` use `proto.call_conv`.

`sf/src/lir.zig` — add to `LirFunction` (`:494-513`), after `is_variadic`:
```zig
    call_conv: u8,
```

`sf/src/lower.zig` — the function that reads `proto` at `:6603`: set `func_ptr.call_conv = proto.call_conv;` next to `func_ptr.is_extern` (`:6618`).

`sf/src/lir_stream.zig` — add `wU8(s, src_fn.call_conv);` after `wU8(s, src_fn.is_variadic);` (`:117`); add `.call_conv = @intCast(u8, 0)` to `emptyLirFunction` (`:162-175`) and to the read-constructed `LirFunction` (`:187-308`, reading one `rU8` in the same position). Update `sf/src/tests/test_semantic_bin.zig:871,915,1042` with the trailing `@intCast(u8, 0)`.

- [ ] **Step 4: Implement the portability macro**

`sf/src/include/zig_compat.h` and the embedded bytes in `sf/src/emit_support.zig` (the `emitSupportWriteCompatHeader` data) — add, before the final `#endif`:
```c
#if !defined(_WIN32)
#define Z98_STDCALL
#elif defined(_MSC_VER) || defined(__WATCOMC__)
#define Z98_STDCALL __stdcall
#else
#define Z98_STDCALL __attribute__((stdcall))
#endif
```

- [ ] **Step 5: Implement emission and the forced prototype**

`sf/src/c89_emit.zig` — add:
```zig
fn emitCallConv(emitter: *C89Emitter, call_conv: u8) void {
    if (call_conv == @intCast(u8, 1)) {
        var cc: []const u8 = "Z98_STDCALL ";
        bufferedWriterWrite(&emitter.writer, cc);
    }
}
```
In `emitFunctionForwardDecl` (`:2199`), call `emitCallConv(emitter, lir_fn.call_conv);` immediately after writing `ret_c` and the space (`:2200-2203`). In `emitFunctionSignature` (`:2134`), do the same after `:2151-2154`. Widen both forced-prototype predicates (`:2418`, `:2566`) to:
```zig
        if (f.is_extern == @intCast(u8, 0) or f.is_variadic != @intCast(u8, 0) or f.call_conv != @intCast(u8, 0)) {
```

- [ ] **Step 6: Rebuild and verify GREEN**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/cc2
rm -rf /tmp/t2_stdcall_new && mkdir -p /tmp/t2_stdcall_new
timeout 120 /tmp/cc2/zig1_5_clean -osw -o /tmp/t2_stdcall_new repro/mi_matrix/callconv_stdcall_decl_xmod/main.zig; echo "emit rc=$?"
grep -rn 'Z98_STDCALL' /tmp/t2_stdcall_new/ | head
grep -rn 'MessageBoxA' /tmp/t2_stdcall_new/*.h /tmp/t2_stdcall_new/*.c | head
for f in /tmp/t2_stdcall_new/*.c; do i686-w64-mingw32-gcc -m32 -std=c89 -c "$f" -o /dev/null || exit 1; done; echo "mingw -c rc=$?"
```
Expected: `emit rc=0`; `Z98_STDCALL` present on the `MessageBoxA` prototype; mingw `-c` rc=0.

- [ ] **Step 7: Verify default-cdecl byte-identity**

Run:
```bash
rm -rf /tmp/base_emit /tmp/new_emit
mkdir -p /tmp/base_emit /tmp/new_emit
timeout 120 /tmp/cc0/zig1_5_clean -o /tmp/base_emit repro/mi_matrix/extern_fn_eu_return/main.zig
timeout 120 /tmp/cc2/zig1_5_clean -o /tmp/new_emit repro/mi_matrix/extern_fn_eu_return/main.zig
diff -r --exclude='*.sh' --exclude='*.bat' /tmp/base_emit /tmp/new_emit; echo "diff rc=$?"
scripts/check_emit_support.sh /tmp/cc2/zig1_5_clean
```
Expected: `diff rc=0` (no convention used -> no emitted change), `check_emit_support.sh` all checks pass.

- [ ] **Step 8: Commit**

```bash
git add sf/src/type_registry.zig sf/src/type_resolver.zig sf/src/semantic_analyzer.zig sf/src/lir.zig sf/src/lir_stream.zig sf/src/lower.zig sf/src/c89_emit.zig sf/src/include/zig_compat.h sf/src/emit_support.zig sf/src/tests/test_semantic_bin.zig repro/mi_matrix/callconv_explicit_cdecl_xmod repro/mi_matrix/callconv_stdcall_decl_xmod
git commit -m "feat(callconv): represent + emit stdcall prototype and force extern prototype (Track1)"
```

---

### Task 3: Function-pointer type form, typedef emission, and typing rules

**Files:**
- Create: `repro/mi_matrix/callconv_stdcall_fnptr_xmod/main.zig`, `repro/mi_matrix/callconv_fnptr_mismatch_green_xmod/main.zig`, `repro/mi_matrix/callconv_stdcall_variadic_green_xmod/main.zig`
- Modify: `sf/src/parser.zig:437,1072-1112,1188-1229`, `sf/src/type_resolver.zig:933-991`, `sf/src/c89_emit.zig:1882-1911`, `sf/src/semantic_analyzer.zig` (variadic check)

**Interfaces:**
- Consumes: `parserClassifyCallConv`, `FN_FLAG_STDCALL`, `emitCallConv`.
- Produces: `parserParseExternFnType`; `parserParseFnType(self, call_conv)`; convention-aware fn-ptr typedef; `error[3000]` cross-convention mismatch; `error[3012]` variadic stdcall.

- [ ] **Step 1: Write the fixtures**

`repro/mi_matrix/callconv_stdcall_fnptr_xmod/main.zig`:
```zig
const Cb = extern "stdcall" fn(i32) void;
extern "stdcall" fn z98_stdcall_probe(x: i32) void;

pub fn main() void {
    var cb: Cb = z98_stdcall_probe;
    _ = cb;
}
```

`repro/mi_matrix/callconv_fnptr_mismatch_green_xmod/main.zig`:
```zig
const CbC = fn(i32) void;
const CbS = extern "stdcall" fn(i32) void;
extern fn z98_cdecl_probe(x: i32) void;

pub fn main() void {
    var c: CbC = z98_cdecl_probe;
    var s: CbS = c;
    _ = s;
}
```

`repro/mi_matrix/callconv_stdcall_variadic_green_xmod/main.zig`:
```zig
extern "stdcall" fn z98_stdcall_variadic(x: i32, ...) i32;

pub fn main() void {
    _ = z98_stdcall_variadic;
}
```

- [ ] **Step 2: Run the failing tests**

Run:
```bash
for d in callconv_stdcall_fnptr_xmod callconv_fnptr_mismatch_green_xmod callconv_stdcall_variadic_green_xmod; do
  rm -rf /tmp/t3_$d && mkdir -p /tmp/t3_$d
  timeout 120 /tmp/cc2/zig1_5_clean -osw -o /tmp/t3_$d repro/mi_matrix/$d/main.zig 2>/tmp/t3_$d/err.txt; echo "$d rc=$?"
done
grep -rc 'Z98_STDCALL' /tmp/t3_callconv_stdcall_fnptr_xmod/ | head
```
Expected RED: `callconv_stdcall_fnptr_xmod` fails to parse `extern "stdcall" fn(...)` (nonzero rc / `error[2000]`); the mismatch fixture compiles (no convention in the type), and the variadic fixture compiles (variadic check absent). `.c` count for the fnptr fixture is `0`.

- [ ] **Step 3: Implement the parser type form**

`sf/src/parser.zig` — add `parserParseExternFnType` (code identical to subspec §3.2), change `parserParseFnType` signature to `fn parserParseFnType(self: *Parser, call_conv: u8) ParserError!u32`, and set the node flags at `:1226`:
```zig
    var fn_flags: u8 = 0;
    if (call_conv == CALL_CONV_STDCALL) { fn_flags = fn_flags | @intCast(u8, 0x01); }
    return ast_mod.astStoreAddNode(self.store, AstKind.fn_type, fn_flags,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        ret_type, 0, 0, payload);
```
Update the `kw_fn` call site in the expression primary (near `:437`) to `parserParseFnType(self, CALL_CONV_CDECL)`, and add `if (tok.kind == TokenKind.kw_extern) return parserParseExternFnType(self);` before it in both the primary dispatch and `parserParseType` (`:1072-1078`).

- [ ] **Step 4: Implement type resolution and typedef emission**

`sf/src/type_resolver.zig` — in the `fn_type` arm, pass the node flag at `:988`:
```zig
        var fnt_conv: u8 = @intCast(u8, 0);
        if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) fnt_conv = @intCast(u8, 1);
        var fnt_tid = type_mod.typeRegistryGetOrCreateFn(env.typereg, fnt_name_id, @intCast(u32, 0), @intCast(u8, 0), @intCast(u8, 0), @intCast(u32, fnt_pstart), @intCast(u16, fnt_pc), fnt_ret_box[0], fnt_conv);
```

`sf/src/c89_emit.zig` — in `emitFnPtrType` (`:1882-1911`), read `fp.flags_packed` and emit inside the declarator:
```zig
    if ((fp.flags_packed & type_mod.FN_FLAG_STDCALL) != @intCast(u8, 0)) {
        var cc: []const u8 = "Z98_STDCALL ";
        bufferedWriterWrite(&emitter.writer, cc);
    }
```
immediately after writing `" ("` at `:1889` and before the `*`/name.

- [ ] **Step 5: Implement the variadic-stdcall rejection**

`sf/src/semantic_analyzer.zig` — in the fn-symbol resolution that reads `proto` (the `:474`/`:632`/`:1393` paths), if the resolved fn type has `is_variadic != 0` and `flags_packed & FN_FLAG_STDCALL != 0`, add:
```zig
            var vs_msg: []const u8 = "variadic functions cannot use the stdcall calling convention";
            _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3012_VARARGS_INVALID)), self.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), vs_msg);
```

- [ ] **Step 6: Rebuild and verify GREEN**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/cc3
rm -rf /tmp/t3_fnptr && mkdir -p /tmp/t3_fnptr
timeout 120 /tmp/cc3/zig1_5_clean -osw -o /tmp/t3_fnptr repro/mi_matrix/callconv_stdcall_fnptr_xmod/main.zig; echo "fnptr emit rc=$?"
grep -rn 'Z98_STDCALL' /tmp/t3_fnptr/ | head
for d in callconv_fnptr_mismatch_green_xmod callconv_stdcall_variadic_green_xmod; do
  rm -rf /tmp/t3_$d && mkdir -p /tmp/t3_$d
  timeout 120 /tmp/cc3/zig1_5_clean --dump-c89 --output-dir /tmp/t3_$d repro/mi_matrix/$d/main.zig 2>/tmp/t3_$d/err.txt; echo "$d rc=$?"
  grep -oE 'error\[(3000|3012)\]' /tmp/t3_$d/err.txt | sort -u
  ls /tmp/t3_$d/*.c 2>/dev/null | wc -l
done
```
Expected: fnptr `emit rc=0` and `Z98_STDCALL` on the `Cb` typedef; mismatch fixture rejects with `error[3000]`, `.c` count `0`; variadic fixture rejects with `error[3012]`, `.c` count `0`.

- [ ] **Step 7: Commit**

```bash
git add sf/src/parser.zig sf/src/type_resolver.zig sf/src/c89_emit.zig sf/src/semantic_analyzer.zig repro/mi_matrix/callconv_stdcall_fnptr_xmod repro/mi_matrix/callconv_fnptr_mismatch_green_xmod repro/mi_matrix/callconv_stdcall_variadic_green_xmod
git commit -m "feat(callconv): extern fn-pointer types, typedef emission, cross-conv + variadic rejection (Track1)"
```

---

### Task 4: Migrate `std_net` Win32 externs to `extern "stdcall"`

**Files:**
- Modify: `sf/src/std_net.zig:18-47`
- Reuse (runtime gate): `examples/z98/mud_server` (imports `std_net`), `repro/mi_matrix/net_bind_startup_xmod`

**Interfaces:**
- Consumes: the implemented `extern "stdcall"` surface.
- Produces: a `std_net` whose emitted prototypes agree with `winsock.h` under `-osw`.

- [ ] **Step 1: Write the failing Windows cross check**

Run the pre-migration cross build to capture the RED (prototype conflict):
```bash
rm -rf /tmp/t4_net_red
timeout 120 /tmp/cc3/zig1_5_clean -osw -o /tmp/t4_net_red repro/mi_matrix/net_bind_startup_xmod/main.zig; echo "emit rc=$?"
for f in /tmp/t4_net_red/*.c; do i686-w64-mingw32-gcc -m32 -std=c89 -c "$f" -o /dev/null 2>/tmp/t4_net_red/mingw.err || { echo "mingw rc=$?"; cat /tmp/t4_net_red/mingw.err; }; done
```
Expected RED: since Task 2 already forces prototypes for `stdcall` but `std_net` still declares `extern "c"`, either no prototype is forced (no conflict yet) or, once a conflict is provoked, mingw reports a conflicting declaration. Record the observed behavior.

- [ ] **Step 2: Migrate the declarations**

`sf/src/std_net.zig` — replace `"c"` with `"stdcall"` for exactly these lines: `:18` `htons`, `:19` `htonl`, `:35` `socket`, `:36` `bind`, `:37` `listen`, `:38` `setsockopt`, `:39` `accept_os`, `:40` `connect_os`, `:41` `send_os`, `:42` `recv_os`, `:43` `select_os`, `:44` `close_os`, `:45` `closesocket`, `:46` `WSAStartup`, `:47` `WSACleanup`. Leave `pub extern "c" fn htons` etc. Otherwise unchanged:
```zig
pub extern "stdcall" fn htons(x: u16) u16;
pub extern "stdcall" fn htonl(x: u32) u32;
...
extern "stdcall" fn socket(af: i32, typ: i32, proto: i32) i32;
extern "stdcall" fn bind(s: i32, name: *const void, namelen: i32) i32;
extern "stdcall" fn listen(s: i32, backlog: i32) i32;
extern "stdcall" fn setsockopt(s: i32, level: i32, optname: i32, optval: *const void, optlen: i32) i32;
extern "stdcall" fn accept_os(s: i32, addr: *void, addrlen: *void) i32;
extern "stdcall" fn connect_os(s: i32, name: *const void, namelen: i32) i32;
extern "stdcall" fn send_os(s: i32, buf: [*]const u8, len: i32, flags: i32) i32;
extern "stdcall" fn recv_os(s: i32, buf: [*]u8, len: i32, flags: i32) i32;
extern "stdcall" fn select_os(nfds: i32, readfds: *void, writefds: *void, exceptfds: *void, timeout: *const void) i32;
extern "stdcall" fn close_os(fd: i32) i32;
extern "stdcall" fn closesocket(s: i32) i32;
extern "stdcall" fn WSAStartup(wVersion: u16, lpWSAData: *void) i32;
extern "stdcall" fn WSACleanup() i32;
```

- [ ] **Step 3: Rebuild and verify GREEN**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/cc4
rm -rf /tmp/t4_net_new && mkdir -p /tmp/t4_net_new
timeout 120 /tmp/cc4/zig1_5_clean -osw -o /tmp/t4_net_new repro/mi_matrix/net_bind_startup_xmod/main.zig; echo "emit rc=$?"
for f in /tmp/t4_net_new/*.c; do i686-w64-mingw32-gcc -m32 -std=c89 -c "$f" -o /dev/null || exit 1; done; echo "mingw -c rc=$?"
grep -rn 'Z98_STDCALL' /tmp/t4_net_new/ | head
```
Expected: `emit rc=0`; mingw `-c` rc=0 (no conflict with `winsock.h`); `Z98_STDCALL` present on the migrated prototypes.

- [ ] **Step 4: Verify linux runtime is unchanged**

Run:
```bash
mkdir -p /tmp/t4_lib && cp sf/src/std*.zig /tmp/t4_lib/
rm -rf /tmp/t4_mud && mkdir -p /tmp/t4_mud
timeout 120 /tmp/cc4/zig1_5_clean -o /tmp/t4_mud examples/z98/mud_server/main.zig
cd /tmp/t4_mud && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include /tmp/t4_mud/*.c /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/t4_mud/mud 2>/tmp/t4_mud/link.err; echo "link rc=$?"
cd /workspace/znineeight && timeout 120 /tmp/t4_mud/mud </dev/null >/tmp/t4_mud/out.txt; echo "run rc=$?"
md5sum /tmp/t4_mud/out.txt
```
Expected: link rc=0; the server runs under `timeout 120` (rc=124 with the message-buffering caveat or rc=0) and its stdout is unchanged vs the pre-migration `std_net` (compare against a capture taken with `/tmp/cc3`). If the program is a long-running server, use `timeout -k 2 5` and compare the first N lines rather than a full run.

- [ ] **Step 5: Commit**

```bash
git add sf/src/std_net.zig
git commit -m "feat(callconv): migrate std_net Win32 externs to extern stdcall (Track1, m1155-A)"
```

---

### Task 5: Fixed-point closeout, seed rotation, corpus sweep, docs

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: the new self-emission fixed point, the rotated seed, and the updated corpus/green-guard baseline.

- [ ] **Step 1: N-hop fixed-point movement**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/ccfp
```
Expected: the script detects the moving point and prints `[seed] three-hop closure OK (moving point): hop2 == hop3 == <NEW_MD5>`. Record `<NEW_MD5>` (hop2/hop3). This replaces `1467d932a876402f40a56316dfcad0e5`; `sf/src` changes (emitter text + LIR header byte) move it.

- [ ] **Step 2: Rotate the seed**

Run:
```bash
bash scripts/seed/archive_seed.sh /tmp/ccfp/hop2/zig1_hop2 /tmp/ccfp/hop2 release/seed/zig1-seed.tgz --update-changelog
md5sum release/seed/zig1-seed.tgz
```
Expected: `[seed] Done`; the script prints the new binary md5 (== `<NEW_MD5>`), C count, fixed-point md5, and archive md5; `release/seed/CHANGELOG.md` gains a newest-first entry. Record the new archive md5.

- [ ] **Step 3: Corpus sweep**

Run:
```bash
new_ok=0; new_green=0; new_fail=0
for d in $(bash scripts/corpus/list_corpus_dirs.sh); do
  mkdir -p /tmp/ccsw; rm -rf /tmp/ccsw; mkdir -p /tmp/ccsw
  timeout 120 /tmp/ccfp/hop2/zig1_hop2 --dump-c89 --output-dir /tmp/ccsw "$d/main.zig" >/dev/null 2>/tmp/ccsw/err.txt
  rc=$?
  if [ "$rc" -ne 0 ]; then grep -qE 'error\[(3000|3012|3043|9001|3042)\]' /tmp/ccsw/err.txt && new_green=$((new_green+1)) || new_fail=$((new_fail+1)); continue; fi
  [ -z "$(ls /tmp/ccsw/*.c 2>/dev/null)" ] && { new_fail=$((new_fail+1)); continue; }
  ok=1; for f in /tmp/ccsw/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null || { ok=0; break; }; done
  [ "$ok" -eq 1 ] && new_ok=$((new_ok+1)) || new_fail=$((new_fail+1))
done
echo "OK=$new_ok GREEN=$new_green FAIL=$new_fail"
```
Expected: the 7 new `callconv_*` fixtures classify as intended (4 OK, 3 GREEN) and all pre-existing dirs keep their class (zero asymmetric movement). Baseline is 570 = 541 OK / 29 GREEN / 0 FAIL; after the 7 new dirs the expected total is 577 = 545 OK / 32 GREEN / 0 FAIL. Update `repro/mi_matrix/EXPECTED_FAIL.md` to v78 with the 3 new green-guard entries and record the recomputed exact counts (do not copy the expected numbers blindly; verify them).

- [ ] **Step 4: Emission-support + Windows cross gates**

Run:
```bash
scripts/check_emit_support.sh /tmp/ccfp/hop2/zig1_hop2
rm -rf /tmp/t5_cross && mkdir -p /tmp/t5_cross
timeout 120 /tmp/ccfp/hop2/zig1_hop2 -osw -o /tmp/t5_cross repro/mi_matrix/net_bind_startup_xmod/main.zig
for f in /tmp/t5_cross/*.c; do i686-w64-mingw32-gcc -m32 -std=c89 -c "$f" -o /dev/null || exit 1; done; echo "cross rc=$?"
```
Expected: `check_emit_support.sh` all pass; mingw `-c` rc=0.

- [ ] **Step 5: Update docs and commit**

Add a calling-convention note to `docs/sf/QUICK_REF.md` (the `extern "stdcall"` surface, the `Z98_STDCALL` macro, and the forced-prototype rule) and update the seed-v10 references to the new seed version/md5. Commit:
```bash
git add repro/mi_matrix/callconv_default_cdecl_xmod repro/mi_matrix/callconv_explicit_cdecl_xmod repro/mi_matrix/callconv_stdcall_decl_xmod repro/mi_matrix/callconv_stdcall_fnptr_xmod repro/mi_matrix/callconv_unknown_green_xmod repro/mi_matrix/callconv_fnptr_mismatch_green_xmod repro/mi_matrix/callconv_stdcall_variadic_green_xmod repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
git commit -m "chore(callconv): Track1 closeout — new fixed point, seed rotation, corpus baseline"
```

---

## Self-Review

**Spec coverage:**
- Subspec §3.1 (capture declarations) → Task 1.
- Subspec §3.2 (fn-pointer type capture) → Task 3 Step 3.
- Subspec §3.3 (type registry + LIR representation) → Task 2 Step 3.
- Subspec §3.4 (emission + forced prototype + portability macro) → Task 2 Steps 4–5.
- Subspec §3.5 (typing rules, variadic stdcall) → Task 2 Step 3 (assignability) + Task 3 Step 5.
- Subspec §3.6/§3.7 (portability matrix, `std_net` migration) → Task 2 Step 4 + Task 4.
- Subspec §4 (interfaces) → named identically in each task's **Interfaces** block.
- Subspec §5 (diagnostics: 3045, 3012, 3000, 3017) → Task 1 Step 3 and Task 3 Step 5.
- Subspec §6 (fixtures/tests) → Tasks 1–5 steps and the File Structure fixture list.
- Subspec §7 (risks) → Global Constraints (byte-identity, staging, check_emit_support lockstep).
- Subspec §8 (dependencies) → the Sequence line + Track 2 reserved `ERR_3017`.

**Placeholder scan:** no `TBD`/`TODO`/"add error handling"/"similar to Task N"; every code step shows the code and every command shows the expected evidence. The only enumerated-by-reference item is the exact new corpus counts, which the closeout recomputes and records.

**Type consistency:** `call_conv: u8` is used identically in `FnProto` (Task 1), `typeRegistryGetOrCreateFn` (Task 2), `LirFunction`/`lir_stream` (Task 2), and the emitter helper `emitCallConv(emitter, call_conv)` (Task 2). `FN_FLAG_VARIADIC`/`FN_FLAG_STDCALL` are defined once in Task 2 and consumed with the same names in Tasks 2–3. `CALL_CONV_CDECL`/`CALL_CONV_STDCALL`/`CALL_CONV_INVALID` are defined once in Task 1 and reused in Task 3. `parserParseFnType(self, call_conv)` and `parserParseFnDecl(..., call_conv)` signatures match across Tasks 1 and 3.

## Amendments

This plan is amendable in place. Any deviation discovered during execution is recorded here as an explicit amendment (date, task, reason, decision) and, where it changes a task's deliverable, the affected task body is edited rather than appended. No `TBD`/`TODO` markers are permitted in amendments; each must state the concrete change and its verification.

### Amendment 1 — 2026-09-13 (Task 2, Step 7 byte-identity gate)

**Reason:** Step 7's literal command `diff -r --exclude='*.sh' --exclude='*.bat' /tmp/base_emit /tmp/new_emit; echo "diff rc=$?"` cannot produce `diff rc=0` by construction. Step 4 unconditionally appends the `Z98_STDCALL` macro to `sf/src/include/zig_compat.h` and to the embedded bytes in `sf/src/emit_support.zig`, so every emission's `zig_compat.h` necessarily differs from the pre-Task-2 baseline (and `scripts/check_emit_support.sh` requires exactly that file to now carry the macro). Separately, the transient `.zig1_lir.tmp` differs because Step 3 adds one serialized `call_conv` byte to every LIR function record (write/read kept symmetric).

**Decision:** The Step 7 gate is re-interpreted as *program-emission* byte-identity: `diff -r -x '*.sh' -x '*.bat' -x 'zig_compat.h' -x '.zig1_*.tmp' /tmp/base_emit /tmp/new_emit` must be `rc=0`, and `scripts/check_emit_support.sh /tmp/cc2/zig1_5_clean` must pass. Verification (2026-09-13): the excluded diff is `rc=0`; the only files differing from baseline are the two intentional ones (`zig_compat.h`, `.zig1_lir.tmp`); `check_emit_support.sh` reports `OK: 5/5 support files byte-identical to canonical`. No source behavior is changed by this amendment.

### Amendment 2 — 2026-09-13 (Task 3, Step 5 variadic-check site + cross-convention mismatch severity)

**Reason 1 (Step 5 site does not fire for the fixture):** Step 5 places the variadic-`stdcall` `error[3012]` check "in the fn-symbol resolution that reads `proto` (the `:474`/`:632`/`:1393` paths)". The Step 1 fixture `callconv_stdcall_variadic_green_xmod` references the extern function as a *bare value* (`_ = z98_stdcall_variadic;`). That resolves in `semanticAnalyzerResolveIdent`, which returns the symbol's `type_id` (already populated by `type_resolver.resolveFnSignatures` for extern declarations); it never enters the field-access `:474`/`:632` or direct-call `:1393` paths. Red test (2026-09-13, `/tmp/cc2`): the fixture compiled `rc=0` (no `error[3012]`). Placing the check only at the Step 5 paths therefore cannot satisfy the brief.

**Reason 2 (cross-convention mismatch is a warning, not the required error):** Step 4's interface promises `error[3000]` for a cross-convention fn-pointer assignment, but `semanticAnalyzerResolveStmtIter`'s var-decl-init mismatch and `semanticAnalyzerResolveAssign`'s assignment mismatch emit level 1 (`warning[3000]`). With only Task 2's assignability change, `callconv_fnptr_mismatch_green_xmod` compiled `rc=0` with `warning[3000]` and 4 `.c` — not the required `error[3000]` / 0 `.c`.

**Decision:** (a) Implement the variadic-`stdcall` rejection in `semanticAnalyzerResolveFnBody`, immediately after the `fn_proto` read and before the body-less early return: it reads the resolved fn type for the `fn_decl` from the resolved-type table and emits `ERR_3012_VARARGS_INVALID` (level 0, the `decl` span) when `is_variadic` and `FN_FLAG_STDCALL` are both set. `phase_SemanticAnalysis` (main.zig:562) invokes `semanticAnalyzerResolveFnBody` for every `fn_decl` including extern (body-less) declarations, so this fires reliably for the fixture regardless of use, while leaving variadic `cdecl` legal. (b) Add `semanticAnalyzerFnPtrConvMismatch(src, tgt)`, which unwraps one pointer level from each side and returns true iff both bases are `fn_type` with differing `FN_FLAG_STDCALL`; use it to set the var-decl-init and assignment mismatch diagnostic to level 0 (error). All other mismatches keep the existing level-1 behavior.

**Verification (2026-09-13, `/tmp/cc3` fixed point `77421c7225f4ee5f8e1ab7b9aa7ee364`, hop1==hop2):** `callconv_stdcall_fnptr_xmod` emits `rc=0` with `typedef void (Z98_STDCALL *zT_430A6DAC_FP_void_int)(int);`; `callconv_fnptr_mismatch_green_xmod` rejects `rc=2`, `error[3000]`, 0 `.c`; `callconv_stdcall_variadic_green_xmod` rejects `rc=2`, `error[3012]`, 0 `.c`; variadic-`cdecl` control still compiles `rc=0`; `check_emit_support.sh` 5/5. The `error[3012]` snippet in Step 5 is otherwise used verbatim (message, code, level-0 collector call, `decl` span).

### Amendment 3 — 2026-09-13 (Task 3 review-fix: convention-aware fn-pointer typedef identity)

**Reason:** Post-Task-3 review found that `fnt_name_id` (`sf/src/type_resolver.zig`, the `fn_type` arm) and the emitted C typedef name (`getCTypeName`, `sf/src/c89_emit.zig` `fn_type` arm) both omitted the calling convention. `typeRegistryGetOrCreateFn` (Task 2) already keeps cdecl and stdcall entries distinct (its dedup includes the `FN_FLAG_STDCALL` bit), but the two entries shared one `name_id`, and `getCTypeName` rebuilt the same `zT_..._F?_void_int` string for both. The special-type emitter dedups typedefs by C name (`sf/src/c89_emit.zig` sub-pass 2a), so a program declaring BOTH `fn(i32) void` and `extern "stdcall" fn(i32) void` emitted only ONE typedef and used it for both variables, with whichever convention was emitted first winning. Verified order-dependent on the Task-3 compiler `/tmp/cc3`: cdecl-first emitted a cdecl typedef used by both vars; stdcall-first emitted the stdcall typedef used by both. Task 3's three fixtures did not catch this because each used a single convention.

**Decision:** Make the function-type identity and emitted name convention-aware while leaving default-cdecl emission byte-identical. (a) `sf/src/type_resolver.zig`: compute `fnt_conv` before building the name key, and use the prefix `"fnts_"` (instead of `"fnt_"`) when the `fn_type` node carries stdcall, so the two entries no longer share a `name_id`. (b) `sf/src/c89_emit.zig` `getCTypeName` `fn_type` arm: when `flags_packed & FN_FLAG_STDCALL` is set, use the distinct marker byte `'S'` at position 1 (`FS_...`); non-stdcall names keep exactly the existing `'P'`/`'N'` (`FP_...`/`FN_...`), so cdecl bytes are unchanged. No other Task-3 step or message changes.

**Verification (2026-09-13, fixed point `818288fbfce514c128526fc85f7aa14f`, hop1==hop2):** new regression fixture `repro/mi_matrix/callconv_mixed_fnptr_typedef_xmod` declares both conventions. RED on `/tmp/cc3` (`77421c72…`) emitted one cdecl typedef `zT_430A6DAC_FP_void_int` reused by both variables; GREEN on `/tmp/cc4` emits `typedef void (*zT_430A6DAC_FP_void_int)(int);` AND `typedef void (Z98_STDCALL *zT_71E1D857_FS_void_int)(int);`, each variable using its own; stdcall-first declaration order also emits both. The three Task-3 fixtures still behave (fnptr emits `Z98_STDCALL`; mismatch `error[3000]`/0 `.c`; variadic `error[3012]`/0 `.c`); `check_emit_support.sh` 5/5; default-cdecl program emission is byte-identical to `/tmp/cc3` for both `extern_fn_eu_return` and `callconv_explicit_cdecl_xmod` (`diff -r -x '*.sh' -x '*.bat' -x 'zig_compat.h' -x '.zig1_*.tmp'` rc=0). The fixture compiles and runs natively (`RUNRC=0`, empty stdout).

### Amendment 4 — 2026-09-13 (Task 3R: apply the convention at use sites; supersede the forced-prototype rule)

**Reason (operator ruling, Option B):** Task 2 Step 5 / subspec §3.4 forced a `Z98_STDCALL` prototype for every convention-bearing extern by widening the `emitModuleHeader`/`emitModuleHeaderFile` predicate (`sf/src/c89_emit.zig`). That emits a second declaration for externs whose real prototype comes from an OS header (`sf/src/include/net_prelude.h` → `<winsock.h>`), which conflicts once Task 4 migrates `std_net` (red observed in the Task 4 Step 1 cross build). A convention extern must be self-describing without a header-conflicting prototype: the C header stays the sole declaration source, Z98 carries the convention on its fn type/LIR, and the convention is applied at the USE SITE via a cast to the convention-qualified fn-pointer typedef (the `FS_…` name from Task 3). Call sites therefore carry the callee convention in LIR.

**Decision:**
- (a) **Revert the forced-prototype clause.** Both predicates become exactly `f.is_extern == 0 or f.is_variadic != 0` again (`sf/src/c89_emit.zig` `emitModuleHeader` and `emitModuleHeaderFile`). The `Z98_STDCALL` macro and the convention on the fn type/prototype-writer/typedef are retained.
- (b) **Carry the callee convention to call sites.** Add `call_conv: u8` to `CallDirectData`/`TailCallData` (`sf/src/lir.zig`). Populate at every `lirSideAppendCallDirect` site (`sf/src/lower.zig`) from the callee's resolved fn type (`fp.flags_packed & FN_FLAG_STDCALL`) or, for the cross-module symbol paths, from the decl `FnProto.call_conv` via `lowerDeclCallConvFlag`; default `0`. `CallInfo` gains `call_conv` so tail calls propagate it (indirect calls stay `0`, already convention-typed by their variable).
- (c) **Emit the use-site cast.** Add `emitCalleeExpr(emitter, fn_type_id, name)` writing `((<cname>)name)` when the fn type carries `FN_FLAG_STDCALL` (where `<cname> = getCTypeName(fn_type_id)`, the `FS_…` typedef) and plain `name` otherwise. Use it in ALL `call_direct` branches (normal, `(void)` dead, optional/EU wraps), the direct `tail_call` branch, and `.func_ref` (which now also uses the extern's original name and resolves its fn-type id from the result temp). `findCalleeFnTypeId` recovers the callee fn-type id by decl name/module since the emitter has no symbol table.
- (d) **Emit the `FS_…` typedef whenever a cast uses it.** `typeRegistryGetOrCreateFn` marks a stdcall fn type used (`types_items[i].flags |= 1`) on both the dedup hit and the create path, so `emitFnPtrType` sees it and emits the typedef (no lowering-side marking needed).
- (e) **LIR stream:** the side table is serialized raw with `@sizeOf(LirSideEntry)` on both the write (`wBytes`) and fault-in (`rBytes`) paths and `expected_len` is computed from `@sizeOf`, so the added fields flow through symmetrically with no per-field write/read and no length-constant change. The function header (`call_conv`, Task 2) is unchanged.

**Verification (2026-09-13, fixed point `c155014e6394ba95e53c25ffa11d9296`, hop1==hop2; seed NOT rotated — Task 5):**
- `callconv_stdcall_decl_xmod` `-osw`: no `Z98_STDCALL` prototype remains; the call is `zT_14 = ((zT_AE874408_FS_int_void__unsign)MessageBoxA)(...)`; `typedef int (Z98_STDCALL *zT_AE874408_FS_int_void__unsign)(...)` is in `zig_special_types.h`.
- Header-covered compile (`i686-w64-mingw32-gcc -m32 -std=c89 ... -include windows.h` over the emitted `callconv_stdcall_decl_xmod` `.c`): rc=0, warning-only ("function called through a non-compatible type") because the fixture's generic signature differs from `MessageBoxA`'s real one while ABI-compatible. Standalone (non-header-covered) stdcall fixtures are emission-inspection only: the cast references the extern symbol, whose declaration is the C header's responsibility per the ruling.
- `callconv_stdcall_fnptr_xmod` `-osw`: emits `typedef void (Z98_STDCALL *zT_71E1D857_FS_void_int)(int);` and the value use `zT_1 = ((zT_71E1D857_FS_void_int)z98_stdcall_probe);`, no forced prototype.
- Default-cdecl byte-identity vs `/tmp/cc4` (`818288fb…`): `extern_fn_eu_return`, `callconv_explicit_cdecl_xmod`, and `callconv_default_cdecl_xmod` all `diff -r -x '*.sh' -x '*.bat' -x 'zig_compat.h' -x '.zig1_*.tmp'` rc=0.
- `callconv_fnptr_mismatch_green_xmod` rejects `rc=2`, `error[3000]`, 0 `.c`; `callconv_stdcall_variadic_green_xmod` rejects `rc=2`, `error[3012]`, 0 `.c`; `callconv_mixed_fnptr_typedef_xmod` still emits both `FP_` (cdecl) and `FS_` (stdcall) typedefs.
- `scripts/check_emit_support.sh /tmp/t3r_cc/zig1_5_clean` 5/5.

