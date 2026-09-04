# F-CLEANDIAG Implementation Plan — clean unsupported-builtin & unknown-type diagnostics

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace two silent/misleading zig1 failure modes with clean `error[3000]` diagnostics: (a) an UNKNOWN/unsupported builtin name (e.g. `@totallyBogus(i32, 5)`) today dumps rc=0 emitting invalid C (GCCFAIL) or silently wrong C (prints `0`); (b) an unknown TYPE name in a var annotation (e.g. `var a: bogusfoo = 1;` — the R7 `uN`/void-fallback class) today reports the misleading `cannot declare variable of type void`. After this plan both report precise errors. BYTE-NEUTRAL for valid programs (4-MD5 gates, golden, matrix, and all valid corpus programs unchanged).

**Architecture:** two additive front-end gates in `sf/src/semantic_analyzer.zig` ONLY. (a) A new membership helper `semanticAnalyzerIsBuiltinSupported(self, name_id)` enumerates every builtin semantic_analyzer interns (all `self.*_name_id` fields) plus the five lower-only builtins that legitimately arrive as `AstKind.builtin_call` but are not sema-interned (`@enumToInt`, `@cVaStart`, `@cVaArg`, `@cVaEnd`, `@panic` — matched by interned text). A new dispatch arm immediately BEFORE the real `builtin_call` arm fires when the name is NOT in that union → `error[3000] "unsupported builtin function"` + `result = TYPE_VOID`; valid builtins never enter the arm (byte-neutral). (b) At the var-decl annotation site, when a bare-ident annotation resolved to `TYPE_VOID`, a second `resolveTypeExprFull` determines whether the ident is a REAL type (`void`/alias → resolves non-UNDEFINED) or truly unknown (→ `TYPE_UNDEFINED`); only the unknown case emits `error[3000] "unknown type in variable declaration"` and sets `decl_type = TYPE_UNDEFINED` (which suppresses the `var_declared_void` + type-mismatch cascade via the existing `decl_type = it` recovery at the init site). No parser/LIR/emitter/type-registry change; `comptime_eval.zig` untouched.

**Tech Stack:** Z98 dialect in `sf/src/*.zig` (self-hosted compiler source); verified against the rebuilt zig0-bootstrap reference; two new committed clean-diagnostic fixtures.

## Global Constraints

- This plan is **F-CLEANDIAG** (operator-approved G1 ruling (d)) — clean unsupported-builtin/unknown-type diagnostics; byte-neutral so the 4 MD5 gates hold. ONLY these two diagnostic gates; **no other F work, no other compiler changes.**
- Z98 dialect discipline: `@intCast` on every narrowing/widening; no `anytype`/`@Type`; `switch` must have `else`; no method syntax; no pointer captures. Follow the surrounding file style exactly.
- Source edits via `fastedit` ONLY per `docs/sf/AGENTS.md` X.7 (re-read the region immediately before every edit; absolute line numbers; edit bottom-to-top; an INSERT = replace the anchor line keeping the original at the end of `new_code` since `end_line = start_line - 1` errors). No python/sed/bulk transforms. No `git checkout` to erase.
- **Files that MAY change:** `sf/src/semantic_analyzer.zig` ONLY for the feat commit; the two new fixtures under `repro/mi_matrix/<name>_xmod/main.zig`; `repro/mi_matrix/EXPECTED_FAIL.md`; later `docs/sf/QUICK_REF.md`. NO other `sf/src` file; `comptime_eval.zig` MUST stay byte-identical; never touch `sf/build/out_release/`.
- **Operator-authorized D1 dialect (carried from F-BITCAST AMENDMENT 1):** cross-module comptime-const local-init decls (`var x: u32 = type_mod.TYPE_*;`) dropped by zig0 during self-compile may be wrapped `@intCast(u32, type_mod.TYPE_*)` WITHOUT a fresh ruling. Any other drop/undeclared class → STOP-present.
- Reference rebuild: `timeout 900 bash sf/scripts/build_release.sh` → output `/tmp/fx_subfolder/zig1`. **CRITICAL:** this rebuild wipes `/tmp/fx_subfolder/lib` — after any rebuild re-install the canonical std lib (cp `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into `/tmp/fx_subfolder/lib/`).
- Fixture contracts: `cleandiag_unknown_builtin_xmod` → RED today compiles rc=0 and prints `0` (silent drop); after fix: clean `error[3000] "unsupported builtin function"`, rc=2, 0 `.c`. `cleandiag_unknown_type_xmod` → RED today reports `error[3000] "cannot declare variable of type void"`; after fix: `error[3000] "unknown type in variable declaration"` (no `cannot declare…void`), rc=2, 0 `.c`. Both end-state fixtures classify GREEN (`error[3000]` + 0 `.c`, the classifier's green-guard rule) — the flip is the MESSAGE + (for the builtin) OK→clean-FAIL; verify stderr text in the steps.
- **Membership helper MUST include every builtin the compiler legitimately accepts** — the union of (i) all `self.*_name_id` builtins interned in semantic_analyzer (~38: ptrcast/ptrtoint/inttoptr/int_from_ptr/ptr_from_int/field_parent_ptr/intcast/floatcast/inttofloat/inttoenum/as/size_of/align_of/offset_of/bit_size_of/bit_offset_of/bitcast/putchar/stdout_write/stderr_write/getchar/exit/sleep_ms/is_windows/console_clear/console_gotoxy/console_set_color/socket_create/socket_bind_listen/socket_accept/socket_connect/socket_send/socket_recv/socket_select/socket_fd_zero/socket_fd_set/socket_fd_isset/socket_close) and (ii) the lower-only five matched by TEXT: `@enumToInt`, `@cVaStart`, `@cVaArg`, `@cVaEnd`, `@panic`. MISSING A NAME = the compiler's own source or the corpus stops compiling (self-compile Step will catch it) → STOP-present, do not ship a short list.
- The 4-MD5 gate programs use only supported builtins and no unknown-type annotations ⇒ their dump md5 MUST stay byte-identical: gol `302df36b…`, lisp `3591bad9…`, json `76056b97…`, mud `53405b3b…`. Any move is a bug → STOP-present.
- Self-compile round-trip fixed point WILL move (compiler source grows) ⇒ NEW fixed-point md5 recorded; re-baseline is operator-ruled in Task 2's STOP-present, never silent.
- Full battery on the feat commit: golden 9/9, matrix 21/21, corpus sweep, self-compile round-trip. The corpus list GROWS to 426 dirs (two new fixtures). Expected classify deltas on the new 426 list: only `cleandiag_unknown_builtin_xmod` flips OK→GREEN (clean-FAIL); `cleandiag_unknown_type_xmod` stays GREEN (message-only change); `int_arbitrary_width_xmod` stderr text changes (now the unknown-type message) but stays GREEN; ALL other 424 dirs byte-identical to the established baseline (OK=405/FAIL=13/GCCFAIL=0/GREEN=6/ICE=0/CRASH=0) → final expectation OK=405/FAIL=13/GCCFAIL=0/GREEN=8/ICE=0/CRASH=0 over 426.
- Authoritative per-fixture classifier = Step-4 recipe in `.superpowers/sdd/task-LANGWINS-report.md` (`classify1.sh` compile-gate + `fixture_run.sh` run-gate; fresh output dir `rm -rf`+`mkdir -p` REQUIRED, else dump ICEs rc=3 spill-open). Pre-existing dirty/untracked repo files are NEVER staged or committed.
- Commit messages follow repo style (lowercase `feat:`/`test:`/`fix:`/`docs:` prefix + concise body).
- Operator standing rules: only plan-authorized actions; STOP-and-present on any issue or any plan-vs-evidence divergence; store memories as we go (mnemoria agent `fcleandiag-session`); NO context compression during this build session.

---

## Background (verified anchors — read before editing; line numbers at HEAD `6ac16199`)

1. Builtin dispatch: `semanticAnalyzerResolveExpr` builtin arm `} else if (node.kind == AstKind.builtin_call) {` at **semantic_analyzer.zig:1527** (preceded by the `fn_call` arm :1525-1526). Name guards chain through the sema ids (:1529 onward: sizeof-group, ptrtoint/int_from_ptr, ptr_from_int, field_parent_ptr, bitcast, getchar, … sockets). Unknown names silently fall to the tail :1666-1678 (`ec.len≥2` → isTypeValueCast false → resolve ec[0]; `ec.len≥1` → resolve ec[0]; else `TYPE_VOID`) — the silent mis-emission/drop class. Parser `parserParseBuiltinCall` (parser.zig:691-739) accepts ANY `@ident(` as `builtin_call` (only `@import` diverts); lexer interns the name WITH the leading `@`.
2. Sema builtin name-id fields: struct :54-91 (`ptrcast_name_id`…`socket_close_name_id`) + `bitcast_name_id`. Diagnostic pattern (name-bearing example exists via `diagnosticBuilderMakeMsg`, but a static message is simplest): `diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3000), self.source_file_id, span_start, span_end, msg)`; errors become fatal rc=2 with 0 `.c`. **Use the literal `@intCast(u16, 3000)`** — `@enumToInt(ERR_3000)` renders `error[19]`.
3. Lower-only builtins that arrive as `builtin_call` and MUST NOT be flagged: `@enumToInt`, `@cVaStart`, `@cVaArg`, `@cVaEnd` (used by live corpus fixtures) and `@panic` (used in `sf/src/parser.zig:276`, compiled by the self-compile battery). `@import`/`@cInclude` never produce `builtin_call`.
4. Var-decl annotation (this is the general var_decl resolver, covering fn-local and module-level decls): semantic_analyzer.zig:2022-2037 — `decl_type = TYPE_UNDEFINED`; if `node.child_0` (the annotation) is an `ident_expr`, `decl_type = semanticAnalyzerResolveExpr(self, node.child_0)` (:2025); that ident path's :356 fallback silently returns `TYPE_VOID` for a never-registered name → `var_declared_void` at :2102-2108 ("cannot declare variable of type void"). Genuine types resolve through nameCache/registry (type_registry.zig:628 for `void`); `resolveTypeExprFull` returns TYPE_UNDEFINED ONLY when the ident truly cannot resolve (type_resolver.zig:735 fall-through). Recovery: at :2101 `if (decl_type == TYPE_UNDEFINED) decl_type = it;` picks up the init type — so setting `decl_type = TYPE_UNDEFINED` after the unknown-type error suppresses the void/mismatch cascade.
5. Current corpus impact (verified read-only): NO existing corpus program uses an out-of-union builtin; only `int_arbitrary_width_xmod` stderr text changes (stays GREEN). EXPECTED_FAIL.md is at header **v66** (post items-3-6 docs gate).

---

### Task 1: Add the two clean-diagnostic gates + commit fixtures + feat

**Files:**
- Create: `repro/mi_matrix/cleandiag_unknown_builtin_xmod/main.zig`, `repro/mi_matrix/cleandiag_unknown_type_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v66→v67, two new Langwins clean-diag rows + RED status)
- Modify: `sf/src/semantic_analyzer.zig` (two helpers after `semanticAnalyzerIsTypeValueCast` ~:252; the builtin unsupported arm before :1527; the unknown-type check at :2025)

**Interfaces:**
- Consumes: the builtin dispatch arm, the var-decl annotation resolution, `resolveTypeExprFull`/`TypeResolveEnv`, the diag-add pattern.
- Produces: `error[3000]` for out-of-union builtin names and for unknown bare-ident type annotations; two GREEN clean-diagnostic fixtures; 4-MD5 byte-identical; fixed-point closes on a NEW md5.

- [ ] **Step 1: Confirm the pre-edit RED classes + snapshot gates**

Create the two fixture files (Step 2 first commit), then against the current reference (repo-root CWD; `/tmp/fx_subfolder/zig1` md5 `821d77ff…`, std lib installed):
```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/cleandiag_unknown_builtin_xmod/main.zig /tmp/fcd_red_b
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/cleandiag_unknown_type_xmod/main.zig /tmp/fcd_red_t
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 repro/mi_matrix/cleandiag_unknown_builtin_xmod/main.zig > /tmp/fcd_red_b.out 2> /tmp/fcd_red_b.dump.err
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 repro/mi_matrix/cleandiag_unknown_type_xmod/main.zig > /tmp/fcd_red_t.out 2> /tmp/fcd_red_t.dump.err
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected RED: unknown_builtin compiles rc=0 (prints `0`) with empty stderr; unknown_type dump rc=2 with `error[3000]: cannot declare variable of type void`; the four md5s equal gol `302df36b…`/lisp `3591bad9…`/json `76056b97…`/mud `53405b3b…`. Record both RED evidences.

- [ ] **Step 2: Commit the two fixtures + EXPECTED_FAIL rows (`test:` commit)**

Fixture `cleandiag_unknown_builtin_xmod/main.zig` (verbatim):
```zig
// cleandiag_unknown_builtin_xmod — CLEAN-DIAG fixture (unsupported builtin).
// Feature: unknown @builtin names get a clean error, not silent mis-emission.
// RED today: @totallyBogus parses as builtin_call, no sema/lower handler ->
//   silent dump rc=0, valid C, result dropped -> prints 0 (or invalid C).
// GREEN (contract): dump rc=2, 0 .c, error[3000]: unsupported builtin function.
const std = @import("std");

pub fn main() void {
    var r = @totallyBogus(i32, 5);
    std.io.printInt(r);
    std.io.writeByte('\n');
}
```
Fixture `cleandiag_unknown_type_xmod/main.zig` (verbatim):
```zig
// cleandiag_unknown_type_xmod — CLEAN-DIAG fixture (unknown type in var decl).
// Feature: unknown type annotations get a clean "unknown type" error, not the
//   misleading void-fallback ("cannot declare variable of type void", R7 class).
// RED today: error[3000]: cannot declare variable of type void.
// GREEN (contract): dump rc=2, 0 .c, error[3000]: unknown type in variable
//   declaration (and NO "cannot declare variable of type void").
const std = @import("std");

pub fn main() void {
    var a: bogusfoo = 1;
    std.io.printInt(@intCast(i32, a));
    std.io.writeByte('\n');
}
```
EXPECTED_FAIL.md: header v66→v67 (file convention), add a `## Langwins clean-diag fixtures (v67) — F-CLEANDIAG` section (at the top of the Langwins group per newest-first convention) with the two rows, RED-status bullets recording the actual RED classes above, and a Rule line with the GREEN contract (`error[3000] unsupported builtin function` / `error[3000] unknown type in variable declaration`, rc=2, 0 `.c`). Touch no other section.
```bash
git add repro/mi_matrix/cleandiag_unknown_builtin_xmod/main.zig repro/mi_matrix/cleandiag_unknown_type_xmod/main.zig repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "test: clean-diagnostic fixtures — unsupported builtin + unknown type (F-CLEANDIAG)"
```

- [ ] **Step 3: Add the two helpers in `sf/src/semantic_analyzer.zig`**

Immediately AFTER the end of `semanticAnalyzerIsTypeValueCast` (its closing `}` :252) insert (INSERT = replace the anchor `fn semanticAnalyzerGrowLocalDecls(self: *SemanticAnalyzer) void {` :254 keeping it at the END of `new_code`):
```zig
fn semanticAnalyzerBuiltinNameEq(self: *SemanticAnalyzer, name_id: u32, lit: []const u8) bool {
    var nm = interner_mod.stringInternerGet(self.interner, name_id);
    if (nm.len != lit.len) return false;
    var ci: usize = 0;
    while (ci < nm.len) : (ci += @intCast(usize, 1)) {
        if (nm[ci] != lit[ci]) return false;
    }
    return true;
}

fn semanticAnalyzerIsBuiltinSupported(self: *SemanticAnalyzer, name_id: u32) bool {
    if (name_id == self.ptrcast_name_id) return true;
    if (name_id == self.ptrtoint_name_id) return true;
    if (name_id == self.inttoptr_name_id) return true;
    if (name_id == self.int_from_ptr_name_id) return true;
    if (name_id == self.ptr_from_int_name_id) return true;
    if (name_id == self.field_parent_ptr_name_id) return true;
    if (name_id == self.bitcast_name_id) return true;
    if (name_id == self.intcast_name_id) return true;
    if (name_id == self.floatcast_name_id) return true;
    if (name_id == self.inttofloat_name_id) return true;
    if (name_id == self.inttoenum_name_id) return true;
    if (name_id == self.as_name_id) return true;
    if (name_id == self.size_of_name_id) return true;
    if (name_id == self.align_of_name_id) return true;
    if (name_id == self.offset_of_name_id) return true;
    if (name_id == self.bit_size_of_name_id) return true;
    if (name_id == self.bit_offset_of_name_id) return true;
    if (name_id == self.putchar_name_id) return true;
    if (name_id == self.stdout_write_name_id) return true;
    if (name_id == self.stderr_write_name_id) return true;
    if (name_id == self.getchar_name_id) return true;
    if (name_id == self.exit_name_id) return true;
    if (name_id == self.sleep_ms_name_id) return true;
    if (name_id == self.is_windows_name_id) return true;
    if (name_id == self.console_clear_name_id) return true;
    if (name_id == self.console_gotoxy_name_id) return true;
    if (name_id == self.console_set_color_name_id) return true;
    if (name_id == self.socket_create_name_id) return true;
    if (name_id == self.socket_bind_listen_name_id) return true;
    if (name_id == self.socket_accept_name_id) return true;
    if (name_id == self.socket_connect_name_id) return true;
    if (name_id == self.socket_send_name_id) return true;
    if (name_id == self.socket_recv_name_id) return true;
    if (name_id == self.socket_select_name_id) return true;
    if (name_id == self.socket_fd_zero_name_id) return true;
    if (name_id == self.socket_fd_set_name_id) return true;
    if (name_id == self.socket_fd_isset_name_id) return true;
    if (name_id == self.socket_close_name_id) return true;
    var eti_s: []const u8 = "@enumToInt";
    if (semanticAnalyzerBuiltinNameEq(self, name_id, eti_s)) return true;
    var cvs_s: []const u8 = "@cVaStart";
    if (semanticAnalyzerBuiltinNameEq(self, name_id, cvs_s)) return true;
    var cva_s: []const u8 = "@cVaArg";
    if (semanticAnalyzerBuiltinNameEq(self, name_id, cva_s)) return true;
    var cve_s: []const u8 = "@cVaEnd";
    if (semanticAnalyzerBuiltinNameEq(self, name_id, cve_s)) return true;
    var pan_s: []const u8 = "@panic";
    if (semanticAnalyzerBuiltinNameEq(self, name_id, pan_s)) return true;
    return false;
}

fn semanticAnalyzerGrowLocalDecls(self: *SemanticAnalyzer) void {
```
Notes: `interner_mod.stringInternerGet(self.interner, …)` matches the file's interner access pattern (self.interner field :53); verify every name-id field name above exists in the struct (:54-91 + `bitcast_name_id`) by reading before finalizing — the field list in this plan is the ground truth and MUST cover all of them, plus the five text-matched lower-only names. If the struct contains any ADDITIONAL `*_name_id` builtin field not listed here, add its guard too (do NOT ship a short list).

- [ ] **Step 4: Add the unsupported-builtin arm in `sf/src/semantic_analyzer.zig`**

Change the builtin-arm opening line at :1527 — replace the single line `    } else if (node.kind == AstKind.builtin_call) {` with (keeping that same line at the END):
```zig
    } else if (node.kind == AstKind.builtin_call and !semanticAnalyzerIsBuiltinSupported(self, node.child_0)) {
        var ub_msg: []const u8 = "unsupported builtin function";
        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3000), self.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), ub_msg);
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.builtin_call) {
```
Notes: `node`/`result`/`self.diag`/`self.source_file_id` are in scope (this is inside `semanticAnalyzerResolveExpr`). Use literal `@intCast(u16, 3000)` NOT `@enumToInt(ERR_3000)` (which renders `error[19]`). The new arm never fires for supported builtins (byte-neutral).

- [ ] **Step 5: Add the unknown-type check in `sf/src/semantic_analyzer.zig`**

Change the bare-ident annotation branch at :2025 — replace the single line
```zig
                if (ann.kind == AstKind.ident_expr) { decl_type = semanticAnalyzerResolveExpr(self, node.child_0); }
```
with:
```zig
                if (ann.kind == AstKind.ident_expr) {
                    decl_type = semanticAnalyzerResolveExpr(self, node.child_0);
                    if (decl_type == type_mod.TYPE_VOID) {
                        var cd_env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner, .module_id = self.module_id };
                        var cd_full = type_resolver.resolveTypeExprFull(&cd_env, node.child_0, @intCast(u32, 0));
                        if (cd_full == type_mod.TYPE_UNDEFINED) {
                            var ut_msg: []const u8 = "unknown type in variable declaration";
                            _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3000), self.source_file_id, ann.span_start, ann.span_start + @intCast(u32, ann.span_len), ut_msg);
                            decl_type = type_mod.TYPE_UNDEFINED;
                        }
                    }
                }
```
Notes: `ann` is in scope (:2024). The secondary `resolveTypeExprFull` returns TYPE_UNDEFINED ONLY for a truly unresolvable name (`bogusfoo`, `u3`); a genuine `void` or a `void`-aliasing type resolves non-UNDEFINED and keeps the existing `var_declared_void` behavior. Setting `decl_type = TYPE_UNDEFINED` routes the init site's existing `decl_type = it` recovery (:2101) so the cascade (type-mismatch + `cannot declare variable of type void`) is suppressed.

- [ ] **Step 6: Rebuild the reference compiler**

```bash
timeout 900 bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```
Expected: release-Done, NEW `/tmp/fx_subfolder/zig1` md5 (≠ `821d77ff…`), std lib re-installed. Record the md5.

- [ ] **Step 7: Verify both fixtures flip to the clean-diagnostic contracts**

```bash
rm -rf /tmp/fcd_g_b && mkdir -p /tmp/fcd_g_b && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fcd_g_b repro/mi_matrix/cleandiag_unknown_builtin_xmod/main.zig > /tmp/fcd_g_b/out.txt 2> /tmp/fcd_g_b/dump.err
rm -rf /tmp/fcd_g_t && mkdir -p /tmp/fcd_g_t && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fcd_g_t repro/mi_matrix/cleandiag_unknown_type_xmod/main.zig > /tmp/fcd_g_t/out.txt 2> /tmp/fcd_g_t/dump.err
cat /tmp/fcd_g_b/dump.err; echo "rc=$?"; ls /tmp/fcd_g_b/*.c 2>/dev/null
cat /tmp/fcd_g_t/dump.err; echo "rc=$?"; ls /tmp/fcd_g_t/*.c 2>/dev/null
```
Expected: both rc=2, 0 `.c`; builtin stderr contains `error[3000]: unsupported builtin function`; type stderr contains `error[3000]: unknown type in variable declaration` and does NOT contain `cannot declare variable of type void`. If the message/rc/.c count diverges (or a cascade error appears), STOP-present.

- [ ] **Step 8: 4-MD5 gates byte-identical (repo-root CWD)**

```bash
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` — all four byte-identical. ANY move = a bug → STOP-present (do not re-baseline).

- [ ] **Step 9: comptime_eval.zig byte-identical check**

```bash
git diff --stat sf/src/comptime_eval.zig
```
Expected: NO output. If it changed, STOP-present.

- [ ] **Step 10: Self-compile round-trip (fixed point check)**

```bash
bash scripts/self_compile/build_next_gen.sh /tmp/fx_subfolder/zig1 /tmp/fcd_self
```
Expected: dump rc=0, 42 `.c`, 0 `error[`, 0 PANIC, hop binaries md5-identical to each other AND to the new reference (fixed point closed). Record the NEW fixed-point md5. If the fixed point does NOT close (e.g. the membership helper missed a builtin the compiler's own source uses), STOP-present with the exact missing name.

- [ ] **Step 11: Commit + report**

```bash
git add sf/src/semantic_analyzer.zig
git commit -m "feat: clean diagnostics — unsupported builtin + unknown type in var decl (F-CLEANDIAG)"
```
Stage ONLY `sf/src/semantic_analyzer.zig` (the fixture `test:` commit landed in Step 2). Pre-existing dirty/untracked files stay unstaged. Append the full report to `.superpowers/sdd/task-F-CLEANDIAG-report.md` (`## F-CLEANDIAG-1`): RED proof (both classes), per-file hunk list, GREEN evidence (both stderr messages verbatim + rc/`.c`), 4-MD5 table, new reference md5, new fixed-point md5, both commit shas, git-status-at-end. Ledger line in `.superpowers/sdd/progress.md`. Store a success memory via `mnemoria --path .opencode/memory add --agent fcleandiag-session ...`.

Report back: `DONE` + commit shas + one-line test summary + any concern.

---

### Task 2: Full battery + corpus reconciliation + STOP-present re-baseline proposal

**Files:**
- Create report: `.superpowers/sdd/task-F-CLEANDIAG-report.md` (`## F-CLEANDIAG-2` appended; gitignored scratch)

**Interfaces:**
- Consumes: the Task-1 compiler `/tmp/fx_subfolder/zig1` (new md5), the two GREEN fixtures, the 426-dir corpus list.
- Produces: full-battery evidence, corpus reconciliation table, STOP-present with a re-baseline proposal for the NEW self-compile fixed-point md5 (operator-ruled). NO commits in this task.

- [ ] **Step 1: Golden 9/9** — run the 9 golden fixtures emit→gcc→link→run with the new compiler; stdout byte-identical to the pre-change golden refs (harness under /tmp/fx_fix; F-PTRBUILTIN-2 methodology). Record rc + stdout state.
- [ ] **Step 2: Matrix 21/21** — all rc=0; mud_server + rogue_mud timeout-gated rc=124 with correct output = PASS; runtime stdout byte-equal vs pre-change reference.
- [ ] **Step 3: Corpus sweep (426 dirs, `-s0`) + asymmetric reconciliation** — build the 426-dir list = the R-phase 424 enumeration + the two new `cleandiag_*_xmod` dirs. Sweep the new compiler. Pre-edit reference no longer exists; expected deltas on the 426 list vs the documented 424 baseline (OK=405/FAIL=13/GCCFAIL=0/GREEN=6/ICE=0/CRASH=0): ONLY `cleandiag_unknown_builtin_xmod` flips OK→GREEN; `cleandiag_unknown_type_xmod` is GREEN on both sides (message-only flip); `int_arbitrary_width_xmod` stays GREEN (stderr text now the unknown-type message) → final = OK=405/FAIL=13/GCCFAIL=0/GREEN=8/ICE=0/CRASH=0 over 426; per-dir asymmetric on the common 424 set = ZERO other delta. Verify stderr message contracts on the two new dirs in the sweep. Any unexpected delta → STOP-present.
- [ ] **Step 4: Self-compile confirmation + fixed-point record** — re-summarize the Task-1 round-trip; record the NEW fixed-point md5; state plainly it MOVED from `bf1e37ca…` because compiler source grew.
- [ ] **Step 5: STOP-present re-baseline proposal** — append `## F-CLEANDIAG-2` with full evidence. STOP-present: re-baseline self-compile fixed point `bf1e37ca…` → `(new)` (operator-ruled); 4-MD5 gates unchanged → NO gate re-baseline; the two new fixture rows GREEN + `int_arbitrary_width_xmod` message-change need an EXPECTED_FAIL docs update in Task 3 AFTER operator approval. Report back: `DONE` + summary + concerns. NO commit.

---

### Task 3: Docs GATE — EXPECTED_FAIL resolution + QUICK_REF baseline (operator-approved)

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`
- Modify: `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: operator approval of the Task-2 re-baseline proposal; the Task-2 evidence.
- Produces: committed docs reconciliation. THIS TASK RUNS ONLY AFTER THE OPERATOR APPROVES.

- [ ] **Step 1: EXPECTED_FAIL.md** — header v67→v68; mark the two `cleandiag_*_xmod` rows RESOLVED with the F-CLEANDIAG fix commit sha + the clean-diagnostic contracts (`unsupported builtin function` / `unknown type in variable declaration`, rc=2, 0 `.c`); update the `int_arbitrary_width_xmod` row note to record its message now reports `unknown type in variable declaration` (class unchanged GREEN). Preserve historical RED text. Touch no other section.
- [ ] **Step 2: QUICK_REF.md** — insert one newest-first baseline bullet ABOVE the current newest (`Post-… items 3-6 baseline`): F-CLEANDIAG commit shas, clean `error[3000]` diagnostics for unsupported builtins + unknown type annotations (byte-neutral), two new fixtures GREEN, corpus 426 `-s0` = OK=405/FAIL=13/GCCFAIL=0/GREEN=8/ICE=0/CRASH=0 (1-dir compile flip + message-only change), 4-MD5 gates byte-identical, golden 9/9, matrix 21/21, NEW reference md5 + NEW fixed-point md5 (operator-ruled re-baseline).
- [ ] **Step 3: Commit**
```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — clean diagnostics GREEN + fixed-point re-baseline (F-CLEANDIAG)"
```
Only the two doc files staged. Report back: `DONE` + commit sha.

---

## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** G1 ruling (d) F-CLEANDIAG → Task 1 implements the two error[3000]-class gates at the sema builtin dispatch and the var-decl annotation resolution (the two documented silent/wrong classes: silent mis-emission/drop for unknown builtins; uN/void-fallback false message for unknown type names); both byte-neutral (valid programs never enter the new paths — proven by the 4-MD5/self-compile gates); Task 2 = regression battery incl. the 426-dir list and message contracts; Task 3 = EXPECTED_FAIL/QUICK_REF reconciliation.
2. **Placeholder scan:** no TBD/TODO; every step carries exact file paths, complete edit content, and commands; fixture sources are complete.
3. **Type/name consistency:** `semanticAnalyzerIsBuiltinSupported`/`semanticAnalyzerBuiltinNameEq` named consistently; the field guards mirror the struct's real `*_name_id` names; literal code `3000` (not `@enumToInt`) so the diagnostic prints `error[3000]`; secondary `resolveTypeExprFull` reuses the exact `TypeResolveEnv` shape used throughout sema.

**AMENDMENT 1 (operator, 2026-09-03):** the five text-match strings MUST be bound to `var x: []const u8` locals before the `semanticAnalyzerBuiltinNameEq` calls (as written above). Passing bare literals inline breaks the compiler's own multi-module build: zig0 emits raw `char*` across module boundaries with no slice coercion → gcc `incompatible type … expected 'Slice_u8'` (AGENTS.md X.5). Operator-ratified; probe-verified clean rebuild.

## Execution Handoff

Plan complete. **Subagent-Driven (recommended per operator):** fresh implementer subagent per task + task reviewer (spec compliance + quality) after each; Task 2 and Task 3 proceed only after the prior review approves and, for Task 3, after the operator approves the Task-2 re-baseline proposal.
