# F-EXPORT Implementation Plan — `export fn` / `export var` source-name symbols

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make zig1 accept `export fn NAME(...) {...}` and `export var NAME: T = init;` and emit their C definitions under the SOURCE name (no `zF_`/`zG_` mangling), so the two committed R4 RED fixtures (`export_fn_xmod`, `export_var_xmod`) go GREEN: runtime stdout `81` / `3` AND the emitted C contains non-static `square` / `counter` symbols by source name.

**Architecture:** zig1 already emits EVERY top-level fn + module storage var as non-static external C; the only thing `export` changes is the C NAME (source name instead of `z<kind>_<fnv1a>_<name>`). So the feature = (1) parser: accept `export` (bit3 0x08 `is_export` on the fn/var decl flags — the reserved ast.zig bit), (2) a per-declaration export registry keyed `(module_id, kind, name_id)` populated during `phase_LIRLowering` where AST flags are visible, (3) a source-name exemption inside the two name-mangler helpers (`nameManglerMangle` / via it `nameManglerMangleGlobal`) that consults that registry — this covers every definition, forward-decl, call, ref, read and write site in one place. zig0 parses `export` but KEEPS mangled names, so the source-name GREEN is Zig semantics, NOT an oracle expectation. No LIR/emitter/emission restructuring; comptime_eval untouched.

**Tech Stack:** Z98 dialect in `sf/src/*.zig` (self-hosted compiler source); verified against the rebuilt zig0-bootstrap reference; R4 fixtures run-gate + C symbol gate.

## Global Constraints

- This plan is **F-EXPORT** = item 5 of the operator-approved follow-on execution order (I4 verdict IMPLEMENT-NOW: parser kw_export + mangler source-name exemption). ONLY `export` support; **no other F work, no other compiler changes.**
- Z98 dialect discipline: `@intCast` on every narrowing/widening; no `anytype`/`@Type`; `switch` must have `else`; no method syntax; no pointer captures. Follow the surrounding file style exactly.
- Source edits via `fastedit` ONLY per `docs/sf/AGENTS.md` X.7 (re-read the region immediately before every edit; absolute line numbers; edit bottom-to-top; an INSERT = replace the anchor line keeping the original at the end of `new_code` since `end_line = start_line - 1` errors). No python/sed/bulk transforms. No `git checkout` to erase.
- **Files that MAY change:** `sf/src/parser.zig`, `sf/src/main.zig`, `sf/src/c89_emit.zig`. NO other `sf/src` file; `comptime_eval.zig` MUST stay byte-identical; never touch `sf/build/out_release/`. The R4 fixtures are committed verbatim and are NOT amended.
- **Operator-authorized D1 dialect (carried from F-BITCAST AMENDMENT 1):** cross-module comptime-const local-init decls (`var x: u32 = type_mod.TYPE_*;`) dropped by zig0 during self-compile may be wrapped `@intCast(u32, type_mod.TYPE_*)` WITHOUT a fresh ruling. Any other drop/undeclared class → STOP-present.
- Reference rebuild: `timeout 900 bash sf/scripts/build_release.sh` → output `/tmp/fx_subfolder/zig1`. **CRITICAL:** this rebuild wipes `/tmp/fx_subfolder/lib` — after any rebuild re-install the canonical std lib (cp `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into `/tmp/fx_subfolder/lib/`).
- GREEN contracts (byte-exact stdout, run-gate `RUNRC=0`): `export_fn_xmod` → `81`; `export_var_xmod` → `3`. ADDITIONALLY the emitted C symbol gate: the definition line for the exported entity is `square` / `counter` (source name, non-static) and NO `zF_…_square` / `zG_…_counter` appears anywhere in the emitted `.c`/`.h` of the fixture.
- The 4-MD5 gate programs use no `export` ⇒ their dump md5 MUST stay byte-identical: gol `302df36b…`, lisp `3591bad9…`, json `76056b97…`, mud `53405b3b…`. Any move is a bug → STOP-present. The compiler's OWN source (`sf/src`) contains no `export`; the mangler change must be byte-neutral when the export registry is empty (which all non-export programs exercise).
- Documented limitations (out of scope, no clean error required): `export fn main` collides with the emitted C `main()` wrapper; an export name that is a C keyword or begins `__` falls back to normal mangling (the mangler's existing keyword/temp guards return before the exemption); cross-module duplicate source names are C-linker semantics.
- **Battery/docs deferral (operator scheme, F-BITCAST AMENDMENT 2):** this plan contains ONLY the implementation task. The full battery (golden/matrix/corpus) + fixed-point re-baseline STOP-present + EXPECTED_FAIL/QUICK_REF docs GATE for items 3-6 run COMBINED once F-SWITCHRANGE (item 6) lands. Per-commit gates that STILL hold here: fixture RED→GREEN byte-exact + symbol gate, 4-MD5 byte-identical, self-compile fixed point closes (record new md5), exact commit scope.
- Authoritative per-fixture classifier = Step-4 recipe in `.superpowers/sdd/task-LANGWINS-report.md` (`fixture_run.sh` run-gate; fresh output dir `rm -rf`+`mkdir -p` REQUIRED, else dump ICEs rc=3 spill-open). Pre-existing dirty/untracked repo files are NEVER staged or committed.
- Commit messages follow repo style (lowercase `feat:`/`test:`/`fix:`/`docs:` prefix + concise body).
- Operator standing rules: only plan-authorized actions; STOP-and-present on any issue or any plan-vs-evidence divergence; store memories as we go (mnemoria agent `fexport-session`); NO context compression during this build session.

---

## Background (verified anchors — read before editing; line numbers at HEAD `3ad5c12e`)

1. Parser: `kw_export` tokenized but no handler. `parserParseStatement` (parser.zig:1351-1382) dispatches const/var/pub/extern/fn …; fn decls `parserParseFnDecl(self,is_pub,is_extern,is_test)` :1507 (flags 0x02 pub, 0x04 extern, 0x20 test, 0x01 variadic; node returned :1583 `astStoreAddNode(fn_decl, flags, …, proto_idx)` with the name inside the FnProto: `store.fn_protos.items[payload].name_id`); var decls `parserParseVarDecl(self,is_mutable,is_pub,is_extern)` :1445 (flags 0x01 mutable, 0x02 pub, 0x04 extern; name = `name_id`, node :1479). `parserParsePubDecl` :1482-1493; `parserParseExternDecl` :1494-1506 (template for a new export handler — minus the string-literal arm, `export` takes no "c"). Fn-decl call sites :1358 (false,false,false), :1485 (true,false,false), :1500 (is_pub,true,false); var-decl call sites :1354/:1355 (statement), :1486/:1487 (pub), :1501/:1502 (extern).
2. Symbol/emit: `Symbol.flags: u16` is a VERBATIM copy of the AST decl flags (symbol_registrator.zig:300 var, :332 fn) so bit3 flows for free and needs no visibility handling (only pub bit0x02 gates cross-module visibility). Function/global C names are produced ONLY through c89_emit's mangler helpers: `NameMangler` struct c89_emit.zig:91-98 (`hash_seed/cache/keyword_set/collision_mod/collision_name/interner`), `nameManglerInit` :437-448 (alloc = emission Sand), `nameManglerMangle(name_id,kind,module_id)` :450-526 (kind 0='F'/1='G'/2='T'; cache key :454 = `(module_id<<35)|(kind<<32)|name_id`), `nameManglerMangleGlobal` :528-539 (user-global → `nameManglerMangle(kind 1)`). Every function def :1976 / fwd-decl :2039 / main-wrapper :2529 / call :6163 / tail-call :6329 / func_ref :6923 and every storage-global extern-header :2444 / def :2623 / load :5180 / store :5191 funnels through these two helpers — a single exemption at the top of `nameManglerMangle` covers ALL sites. The `name_mangler.zig` stub (NameMangler{counter}) is DEAD code (never read).
3. Phase wiring: `CompilerContext` main.zig:92-117 (add the export registry field after `global_decls` :116). `runCompiler` ctx setup: `var comptime_values = hash_mod.u32ToU64MapInit(&compiler_alloc.emission);` :239 then `var ctx = CompilerContext{ … }` :240+ (`.global_decls = lir_mod.globalDeclArrayListInit(&compiler_alloc.emission),` :263). `phase_LIRLowering` :597+ iterates module root decls (module loop :643+, decl loop :670+); fn branch `if (decl.kind == AstKind.fn_decl)` :679-687 (fn name via `store.fn_protos.items[astStoreNodePayload(store, decls[di])].name_id`); var branch :689+ with the is-storage filter :690/:696-702 and `ModuleGlobalDecl` append :714-729 (`gv_name` = `astStoreNodePayload(store, decls[di])`). `phase_C89Emission` :785+: `mangler = c89_mod.nameManglerInit(ctx.interner, &ctx.alloc.emission, mangler_hint);` :788-790, `emitter = c89_mod.c89EmitterInit(…)` :792+. AST (`ctx.store`) + module roots remain open through the emission phase.
4. R4 fixtures (committed): `export_fn_xmod/main.zig` — `export fn square(n: i32) i32 { return n * n; }` then `pub fn main` calls `square(9)` → prints `81`; contract stdout `81\n` AND emitted C must contain a non-static definition named `square`. `export_var_xmod/main.zig` — `export var counter: i32 = 0;`, local `fn bump` does `counter += 1;`, `main` bumps 3× and prints → `3\n`; contract stdout `3\n` AND non-static `counter`. Both currently RED: clean parse `error[2000] expected expression` at the `export` keyword (col 0), 0 `.c`.

---

### Task 1: Implement `export` (parser bit + registry + mangler exemption)

**Files:**
- Modify: `sf/src/parser.zig` (new `parserParseExportDecl` + statement/pub arms + `is_export` param on the two decl parsers + updated call sites)
- Modify: `sf/src/main.zig` (ctx registry field + init var + literal; fn/var export marking in `phase_LIRLowering`; attach registry to mangler in `phase_C89Emission`)
- Modify: `sf/src/c89_emit.zig` (NameMangler optional-export-map field + null default; exemption in `nameManglerMangle`)

**Interfaces:**
- Consumes: existing fn/var decl parsers, the decl-loop in `phase_LIRLowering`, the mangler helpers, R4 fixtures.
- Produces: `export fn`/`export var` parsed (flags bit3 0x08); export registry populated; mangler source-name exemption; R4 fixtures GREEN (`81`/`3` + source-name symbol gate); 4-MD5 byte-identical; fixed-point closes on a NEW md5.

- [ ] **Step 1: Confirm the pre-edit RED + snapshot gates**

Against the current reference (repo-root CWD; `/tmp/fx_subfolder/zig1` md5 `0d97c207…`, std lib already installed):
```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/export_fn_xmod/main.zig /tmp/fexp_red_fn
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/export_var_xmod/main.zig /tmp/fexp_red_var
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: both fixtures clean parse FAIL (`error[2000]` at the `export` keyword, 0 `.c`) → RED confirmed; the four md5s equal gol `302df36b…`/lisp `3591bad9…`/json `76056b97…`/mud `53405b3b…`. If either fixture is already GREEN or any gate hash moved, STOP-present.

- [ ] **Step 2: Edit `sf/src/parser.zig` (do these bottom-to-top)**

(2a) `parserParseFnDecl` signature + flags — change line ~:1507 and its flag block (~:1510-1513):
```zig
fn parserParseFnDecl(self: *Parser, is_pub: bool, is_extern: bool, is_test: bool, is_export: bool) ParserError!u32 {
```
and inside, after the `is_test` line add:
```zig
    if (is_export) flags = flags | @intCast(u8, 0x08);
```

(2b) `parserParseVarDecl` signature + flags — change line ~:1445 and its flag block (~:1455-1458):
```zig
fn parserParseVarDecl(self: *Parser, is_mutable: bool, is_pub: bool, is_extern: bool, is_export: bool) ParserError!u32 {
```
and inside, after the `is_extern` line add:
```zig
    if (is_export) flags = flags | @intCast(u8, 0x08);
```

(2c) New handler — insert AFTER `parserParseExternDecl`'s closing `}` (:1506) and BEFORE `parserParseFnDecl` (:1507) (INSERT = replace the anchor line `fn parserParseFnDecl(self: *Parser, is_pub: bool, is_extern: bool, is_test: bool) ParserError!u32 {`, but that line is edited in (2a); instead anchor on the line `    return error.UnexpectedToken;` of `parserParseExternDecl` — verify uniqueness and use (2a)'s already-updated signature line as the kept tail only if unambiguous; the SAFEST anchor is the extern error line `    var e_msg: []const u8 = "expected fn/const/var after extern";` + its two lines — replace those three lines with the same three lines followed by the new handler):
```zig
    var e_msg: []const u8 = "expected fn/const/var after extern";
    parserAddError(self, tok, e_msg);
    return error.UnexpectedToken;
}
fn parserParseExportDecl(self: *Parser, is_pub: bool) ParserError!u32 {
    _ = parserAdvance(self);
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.kw_fn) return parserParseFnDecl(self, is_pub, false, false, true);
    if (tok.kind == TokenKind.kw_const) return parserParseVarDecl(self, false, is_pub, false, true);
    if (tok.kind == TokenKind.kw_var) return parserParseVarDecl(self, true, is_pub, false, true);
    var x_msg: []const u8 = "expected fn/const/var after export";
    parserAddError(self, tok, x_msg);
    return error.UnexpectedToken;
}
```

(2d) Statement dispatch — add the `export` arm right after the `kw_extern` arm (:1357):
```zig
    if (tok.kind == TokenKind.kw_export) return parserParseExportDecl(self, false);
```

(2e) `parserParsePubDecl` — add the `pub export` arm right after the `kw_extern` arm (:1489) and before its error line:
```zig
    if (tok.kind == TokenKind.kw_export) return parserParseExportDecl(self, true);
```

(2f) Update the existing call sites for the new trailing parameter (append `, false` to each):
- fn sites: `parserParseFnDecl(self, false, false, false)` (:1358) → `…, false)`; `parserParseFnDecl(self, true, false, false)` (:1485) → `…, false)`; `parserParseFnDecl(self, is_pub, true, false)` (:1500) → `…, false)`.
- var sites: `parserParseVarDecl(self, false, false, false)` (:1354) → `…, false)`; `(self, true, false, false)` (:1355) → `…, false)`; `(self, false, true, false)` (:1486) → `…, false)`; `(self, true, true, false)` (:1487) → `…, false)`; `(self, false, is_pub, true)` (:1501) → `…, false)`; `(self, true, is_pub, true)` (:1502) → `…, false)`.
Notes: `export fn`/`export var` pass `is_export=true`; `export` without `pub` passes `is_pub=false` (matching fixtures); `pub export` passes `is_pub=true`. Verify there are no other `parserParseFnDecl`/`parserParseVarDecl` call sites by grep before editing.

- [ ] **Step 3: Edit `sf/src/main.zig` (do bottom-to-top)**

(3a) `CompilerContext` struct — add a field after the `.global_decls` decl `global_decls: lir_mod.GlobalDeclArrayList,` (:116):
```
    exported: hash_mod.U64ToU32Map,
```

(3b) ctx init — add the local registry right after the `comptime_values` init line (:239):
```
     var exported = hash_mod.u64ToU32MapInit(&compiler_alloc.emission);
```
and add the struct-literal assignment `.exported = exported,` right after the `.comptime_values = comptime_values,` line in the `CompilerContext{…}` literal (~:240-265; locate the literal's `.comptime_values = …` line and insert after it — do NOT rely on field order, struct init is by name).

(3c) fn-export marking in `phase_LIRLowering` — inside the `if (decl.kind == AstKind.fn_decl)` branch (:679), immediately BEFORE the `var lowerer = lower_mod.lowererInit(…);` line, insert:
```zig
                        if ((@intCast(u16, decl.flags) & @intCast(u16, 0x08)) != @intCast(u16, 0)) {
                            var fexp_proto = ctx.store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(ctx.store, decls[di]))];
                            var fexp_key: u64 = (@intCast(u64, mods[mi].id) << @intCast(u64, 35)) | (@intCast(u64, 0) << @intCast(u64, 32)) | @intCast(u64, fexp_proto.name_id);
                            _ = hash_mod.u64ToU32MapPut(&ctx.exported, fexp_key, @intCast(u32, 1));
                        }
```

(3d) var-export marking — inside the `if (gv_is_storage == @intCast(u8, 1)) {` block (:714), immediately BEFORE the `var gv_has_ri: u8 = @intCast(u8, 0);` line (:715), insert:
```zig
                                    if ((@intCast(u16, decl.flags) & @intCast(u16, 0x08)) != @intCast(u16, 0)) {
                                        var gexp_key: u64 = (@intCast(u64, mods[mi].id) << @intCast(u64, 35)) | (@intCast(u64, 1) << @intCast(u64, 32)) | @intCast(u64, gv_name);
                                        _ = hash_mod.u64ToU32MapPut(&ctx.exported, gexp_key, @intCast(u32, 1));
                                    }
```

(3e) attach to the mangler in `phase_C89Emission` — right after the `mangler = c89_mod.nameManglerInit(ctx.interner, &ctx.alloc.emission, mangler_hint);` line (:790), insert:
```zig
    mangler.exported = &ctx.exported;
```

- [ ] **Step 4: Edit `sf/src/c89_emit.zig` (do bottom-to-top)**

(4a) NameMangler struct (:91-98) — add a field after `.interner: *StringInterner,` (:97):
```
    exported: ?*U64ToU32Map,
```

(4b) `nameManglerInit` struct literal (:437-445) — add `.exported = null,` (anywhere in the literal).

(4c) `nameManglerMangle` — add the exemption right AFTER the cache-key computation line `var key: u64 = (@intCast(u64, module_id) << @intCast(u64, 35)) | (@intCast(u64, kind) << @intCast(u64, 32)) | @intCast(u64, name_id);` (:454) and BEFORE the cache lookup (:455):
```zig
    if (self.exported) |exp_map| {
        if (hash_mod.u64ToU32MapGet(exp_map, key)) |_| return name_id;
    }
```
Notes: the cache-key layout `(module<<35)|(kind<<32)|name_id` matches the registry keys from Step 3 exactly (kind 0 = fn, 1 = global, same as the 'F'/'G' kind chars). The guards above (temp/builtin names → return unchanged; C keywords → mangled fallback) already return before this point, so exported C-keyword/`__`-prefixed names degrade safely to mangling. `nameManglerMangleGlobal` needs NO change: its user-global branch calls `nameManglerMangle(kind 1)` which the exemption covers; its type-storage branches use kind-1 keys for TYPE symbols that are never in the export registry. `name_id` returned here is the interned source-name string, emitted verbatim as the C identifier.

- [ ] **Step 5: Rebuild the reference compiler**

```bash
timeout 900 bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```
Expected: release-Done, NEW `/tmp/fx_subfolder/zig1` md5 (≠ `0d97c207…`), std lib re-installed. Record the md5. If the build of the compiler fails (parser/ctx/mangler edits), fix per fastedit discipline and re-run.

- [ ] **Step 6: Verify both fixtures flip RED→GREEN incl. the symbol gate**

```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/export_fn_xmod/main.zig /tmp/fexp_g_fn
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/export_var_xmod/main.zig /tmp/fexp_g_var
```
Expected: each `RUNRC=0`; stdout byte-exact `81` / `3`; gcc clean. THEN the C symbol gate — dump both fixtures into fresh dirs and grep the emitted `.c`/`.h`:
```bash
rm -rf /tmp/fexp_sym_fn && mkdir -p /tmp/fexp_sym_fn && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fexp_sym_fn repro/mi_matrix/export_fn_xmod/main.zig
rm -rf /tmp/fexp_sym_var && mkdir -p /tmp/fexp_sym_var && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fexp_sym_var repro/mi_matrix/export_var_xmod/main.zig
grep -rln "square" /tmp/fexp_sym_fn; grep -rn "square\|zF_.*square" /tmp/fexp_sym_fn/*.c /tmp/fexp_sym_fn/*.h
grep -rln "counter" /tmp/fexp_sym_var; grep -rn "counter\|zG_.*counter" /tmp/fexp_sym_var/*.c /tmp/fexp_sym_var/*.h
```
Expected: the emitted `main_*.c` (or module `.c`) contains a non-static definition `… square(…` / `… counter …` (source name, no `static`), and NO `zF_…_square` / `zG_…_counter` symbol anywhere. If not GREEN with the exact stdout, or the definition is still z-mangled, or the fixture fails to compile/link, STOP-present.

- [ ] **Step 7: 4-MD5 gates byte-identical (repo-root CWD)**

```bash
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` — all four byte-identical. ANY move = a bug → STOP-present (do not re-baseline).

- [ ] **Step 8: comptime_eval.zig byte-identical check**

```bash
git diff --stat sf/src/comptime_eval.zig
```
Expected: NO output. If it changed, STOP-present.

- [ ] **Step 9: Self-compile round-trip (fixed point check)**

```bash
bash scripts/self_compile/build_next_gen.sh /tmp/fx_subfolder/zig1 /tmp/fexp_self
```
Expected: dump rc=0, 42 `.c`, 0 `error[`, 0 PANIC, hop binaries md5-identical to each other AND to the new reference (fixed point closed). Record the NEW fixed-point md5. If the fixed point does NOT close, STOP-present. (Fixed-point re-baseline is part of the COMBINED items-3-6 STOP-present — not here.)

- [ ] **Step 10: Commit + report**

```bash
git add sf/src/parser.zig sf/src/main.zig sf/src/c89_emit.zig
git commit -m "feat: export fn/var — source-name C symbols via mangler exemption (F-EXPORT)"
```
Stage ONLY those three files. Pre-existing dirty/untracked files stay unstaged. Append the full report to `.superpowers/sdd/task-F-EXPORT-report.md` (`## F-EXPORT-1`): RED proof, per-file hunk list, fixture GREEN evidence (stdout bytes + symbol-gate grep output), 4-MD5 table, new reference md5, new fixed-point md5, commit sha, git-status-at-end. Ledger line in `.superpowers/sdd/progress.md`. Store a success memory via `mnemoria --path .opencode/memory add --agent fexport-session ...`.

Report back: `DONE` + commit sha + one-line test summary + any concern.

---

## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** I4 verdict (parser kw_export mirroring kw_extern + reserved bit3 is_export + mangler source-name exemption) → Task 1 implements all three plus the registry plumbing. The mangler-exemption choke point covers every fn def/fwd-decl/call/func_ref and every global header/def/load/store site with ONE edit, so references inside the fixture resolve to the exported source name too. R4 GREEN contracts (`81`/`3`) + the source-name symbol gate are explicit steps. zig0 semantics (keeps mangled names) correctly documented as non-oracle. comptime_eval untouched.
2. **Placeholder scan:** no TBD/TODO; every step carries exact file paths, complete edit content/anchors, and commands.
3. **Type/name consistency:** registry key layout `(module<<35)|(kind<<32)|name_id` matches the mangler cache-key layout verbatim; kind 0=fn/1=global matches the mangler 'F'/'G' kind chars; field `exported` named identically in CompilerContext (value map) and NameMangler (optional pointer); `astStoreNodePayload`/`fn_protos`/`u64ToU32MapPut`/`u64ToU32MapGet` all verified in use in the touched files.

## Execution Handoff

Plan complete. **Subagent-Driven (recommended per operator):** fresh implementer subagent per task + task reviewer (spec compliance + quality). No Task 2/Task 3 in this plan — battery + fixed-point re-baseline + docs GATE run COMBINED after F-SWITCHRANGE (item 6) per the operator deferral scheme (F-BITCAST AMENDMENT 2).
