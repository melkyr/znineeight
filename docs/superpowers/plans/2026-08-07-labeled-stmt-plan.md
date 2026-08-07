# Labeled Statement Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add zig1 support for labeled statements (`label: stmt`) in parser, sema, and lowerer so `labeled_stmt_unhandled` flips FAIL→OK — the first step toward rogue_mud compilation.

**Architecture:** The `labeled_stmt` AST node is a transparent wrapper: `child_0` = inner statement, `payload` = label name string_id. Four edits: parser stores the label name; sema stmt dispatcher transparently unwraps `child_0` onto the work queue; sema expr redirect delegates labeled_stmt back to the stmt resolver (defensive); lowerer unwraps `child_0` in `lowerStmt`. No new LIR, no AST shape change.

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89)

## Global Constraints

- Build in /tmp via the QUICK_REF bootstrap recipe (NOT `sf/build/out_release/` — timeouts):
  ```bash
  OUT=/tmp/zlbl
  rm -rf "$OUT" && mkdir -p "$OUT"
  ./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
  ```
  Gate: 0 gcc errors (`error:` count == 0).
- 4 MD5 baselines byte-identical: mud `50beb1bf...`, gol `0d8f0092...`, lisp `605b597e...`, json `b5f56ebd...` (no gate baseline uses labeled statements).
- Corpus: 210 repros, OK=202/FAIL=4/gg=4 (raw 8). After fix: OK=203/FAIL=3/gg=4 (raw 7). FAIL count must not increase.
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- QUICK_REF.md reference mandatory for all gates.
- The plan is the ONLY authority. Plan says A → do A; if you think X/Y is better, STOP and present.

---

### Task F1: Implement labeled_stmt support (4 edits, 3 files)

**Files:**
- Modify: `sf/src/parser.zig:1285` (parserParseLabeledStmt) + `:1299` (parserParseLabeledBlockExpr)
- Modify: `sf/src/semantic_analyzer.zig:1341` (expr redirect) + `:1767` (stmt dispatcher)
- Modify: `sf/src/lower.zig:3497` (lowerStmt)
- Update: `repro/mi_matrix/EXPECTED_FAIL.md`

**Interfaces:**
- Consumes: nothing (self-contained fix).
- Produces: `labeled_stmt` handled in all three pipeline stages; `label: while`/`label: for`/`label: block`/`label: if` compile. `break :label` / `continue :label` match via `node.payload` (now populated).

- [ ] **Step 1: Read the 4 edit regions**

Read `sf/src/parser.zig:1280-1301`, `sf/src/semantic_analyzer.zig:1336-1347` and `:1760-1778`, `sf/src/lower.zig:3497-3520`. Confirm the exact current text before editing.

- [ ] **Step 2: Edit 1 — parser stores label name (parser.zig:1285)**

`parserParseLabeledStmt` currently passes `0` as the payload (7th arg to astStoreAddNode). Change the payload argument from `0` to the label's string_id:
```zig
fn parserParseLabeledStmt(self: *Parser) ParserError!u32 {
    var label_tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.colon);
    var inner = try parserParseStatement(self);
    var end = inner; _ = end;
    return ast_mod.astStoreAddNode(self.store, AstKind.labeled_stmt, 0,
        label_tok.span_start, label_tok.span_start + @intCast(u32, label_tok.span_len),
        inner, 0, 0, label_tok.value.string_id);
}
```
Same change in `parserParseLabeledBlockExpr` (`:1299`): replace the trailing `0` payload with `label_tok.value.string_id`.

- [ ] **Step 3: Edit 2 — sema stmt dispatcher transparent unwrap (semantic_analyzer.zig:1767)**

In `semanticAnalyzerResolveStmtIter`, add a `labeled_stmt` case BEFORE the `defer_stmt`/`errdefer_stmt` case (insert at the `else if` chain, i.e. new case just before line 1767):
```zig
        } else if (node.kind == AstKind.labeled_stmt) {
            if (node.child_0 != @intCast(u32, 0)) {
                semanticAnalyzerStmtWorkPush(self, node.child_0);
            }
        } else if (node.kind == AstKind.defer_stmt or node.kind == AstKind.errdefer_stmt) {
```
This mirrors the defer_stmt transparent unwrapper exactly. ONE case handles all inner kinds (while/for/block/if/switch) via the work-queue model.

- [ ] **Step 4: Edit 3 — sema expr redirect (semantic_analyzer.zig:1341)**

Add `labeled_stmt` to the existing stmt-redirect branch:
```zig
     } else if (node.kind == AstKind.var_decl or node.kind == AstKind.defer_stmt or node.kind == AstKind.errdefer_stmt or node.kind == AstKind.labeled_stmt) {
         semanticAnalyzerResolveStmtIter(self, node_idx);
         result = type_mod.TYPE_VOID;
```
Defensive: if labeled_stmt ever reaches resolveExpr, it delegates back to the stmt resolver instead of the unhandled-else 3020 crash.

- [ ] **Step 5: Edit 4 — lowerer transparent unwrap (lower.zig:3497)**

In `lowerStmt`, add a `labeled_stmt` case that recurses into `child_0`. Insert after the `block` case (`:3507-3515`) or alongside the defer/errdefer cases — the KEY is it unwraps and recurses:
```zig
    } else if (node.kind == AstKind.labeled_stmt) {
        if (node.child_0 != @intCast(u32, 0)) {
            lowerStmt(self, node.child_0);
        }
    } else if (node.kind == AstKind.defer_stmt) {
```
The inner statement lowers normally (existing while/for/block handlers). `break :label`/`continue :label` inside resolve via their existing handlers (lower.zig:4002-4052) which read `node.payload` — now populated by Edit 1.

- [ ] **Step 6: Build + verify repro**

Build `/tmp/zlbl/zig1` (0 gcc errors). Run the repro:
```bash
/tmp/zlbl/zig1 --dump-c89 --output-dir /tmp/zlblr repro/mi_matrix/labeled_stmt_unhandled/main.zig ; echo "dump rc=$?"
ls /tmp/zlblr/*.c 2>/dev/null
cd /tmp/zlblr && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c ; echo "gcc rc=$?"
cd /tmp/zlblr && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog ; echo "link rc=$?"
/tmp/zlblr/prog ; echo "run rc=$?"
```
Expected: dump rc=0, gcc rc=0, link rc=0, run rc=0. FAIL→OK.

- [ ] **Step 7: Gate sweep**

Build 0 gcc errors. Verify:
- 4 MD5 gates byte-identical: run the QUICK_REF single-stream `--dump-c89` on mud/gol/lisp/json entries and compare against `50beb1bf.../0d8f0092.../605b597e.../b5f56ebd...`.
- test_analyzer_bin PASS.
- Corpus: run the classifier sweep (QUICK_REF corpus gate). Expected 210 repros, OK=203/FAIL=3/gg=4 (raw 7). The only flip: `labeled_stmt_unhandled` FAIL→OK. No other flips.

- [ ] **Step 8: Update EXPECTED_FAIL.md**

Update `repro/mi_matrix/EXPECTED_FAIL.md`: clear the `labeled_stmt_unhandled` FAIL row → OK, update totals to OK=203/FAIL=3/gg=4 (raw 7) over 210, add a fix-reference note (F1, 2026-08-07). Follow the file's existing section conventions (newest-on-top, `[updated]` annotations).

- [ ] **Step 9: Commit**

```bash
git add sf/src/parser.zig sf/src/semantic_analyzer.zig sf/src/lower.zig repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "feat: labeled statement support in parser, sema, lowerer (labeled_stmt_unhandled)"
```

---

### Task F2: Docs + gate confirmation (QUICK_REF + tech docs)

**Files:**
- Modify: `docs/sf/QUICK_REF.md`
- Modify: `sf/docs/tech_docs/00_lexer_parser.md`, `05_semantic_analysis.md`, `07_lir_lowering.md` (per AGENTS §1.1.1)

**Interfaces:**
- Consumes: F1's completed fix + measured gate results.
- Produces: docs reflect labeled_stmt support; QUICK_REF corpus baseline updated.

- [ ] **Step 1: Confirm gates at HEAD**

Re-verify: build 0 err; repro FAIL→OK; 4 MD5s byte-identical; corpus OK=203/FAIL=3/gg=4 (raw 7). Record the actual measured numbers.

- [ ] **Step 2: Update QUICK_REF.md**

Update the corpus baseline section: 210 repros, OK=203/FAIL=3/gg=4 (raw 7). Add a note that labeled statements are now supported (2026-08-07, labeled_stmt fix). Leave the 4 FAILs enumerated: `field_store_drop`, `test_stub_0` (std-lib-deferred), `self_embed_optional_cycle` (C89 fundamental).

- [ ] **Step 3: Update tech docs**

Per AGENTS §1.1.1, add `[updated: 2026-08-07]` annotations + describe labeled_stmt handling in:
- `00_lexer_parser.md` — parser stores label name in payload (parser.zig:1285/1299).
- `05_semantic_analysis.md` — labeled_stmt transparent unwrap in stmt dispatcher (:1767) + expr redirect (:1341).
- `07_lir_lowering.md` — labeled_stmt unwrap in lowerStmt (:3497); break/continue label matching now active.

- [ ] **Step 4: Commit**

```bash
git add docs/sf/QUICK_REF.md sf/docs/tech_docs/00_lexer_parser.md sf/docs/tech_docs/05_semantic_analysis.md sf/docs/tech_docs/07_lir_lowering.md
git commit -m "docs: labeled statement support (QUICK_REF baseline + tech docs)"
```
