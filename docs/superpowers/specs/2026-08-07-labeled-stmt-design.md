# Labeled Statement Support — Design Spec

**Date:** 2026-08-07
**Status:** Draft
**Predecessor:** `2026-08-06-compiler-gaps-design.md` (complete at HEAD 5ee62732)

## Goal

Add zig1 support for labeled statements (`label: stmt`) in the semantic analyzer and lowerer, fixing the `labeled_stmt_unhandled` FAIL discovered while attempting rogue_mud compilation. Scope: labeled statements of ANY inner kind (while, for, block, if, etc.) — not just loops. This is the first step toward rogue_mud compilation.

## Background

rogue_mud compilation blocks at type resolution with `error[3020]: internal error: unhandled node kind in type resolution`. Root cause: `labeled_stmt` (AstKind 82) has NO case in `semanticAnalyzerResolveStmtIter` (semantic_analyzer.zig:1599-1778), so it falls to `resolveExpr`'s unhandled else (:1424-1429) and crashes. Sites: `main.zig:92 game_loop: while(true)`, `scenario.zig:59 bsp_loop:`. The zig0 oracle accepts labeled statements (rc=0) — this is a genuine compiler gap.

A defensive repro `repro/mi_matrix/labeled_stmt_unhandled/` was created in commit e7332667 (`game_loop: while(true){break :game_loop;}`) and classified FAIL (raw FAIL 7→8, corpus 210).

## Fix (Approach B — full, including parser label-name)

Four edits across three files. The labeled_stmt AST node is a transparent wrapper: `child_0` = inner statement, `payload` = label name string_id.

### Edit 1: Parser — store label name in payload

**File:** `sf/src/parser.zig:1285` (`parserParseLabeledStmt`)

Current: `astStoreAddNode(..., inner, 0, 0, 0)` — payload hardcoded to 0. The label name `label_tok.value.string_id` is interned but never stored.

Fix: store `label_tok.value.string_id` in the payload field. This matches the documented AST semantics (ast.zig:261: "labeled_stmt, break_stmt, continue_stmt → label name ID (0=unlabeled)") and enables `break :label` / `continue :label` matching. Same change applies to `parserParseLabeledBlockExpr` (parser.zig:1290-1301) if it also hardcodes payload 0.

### Edit 2: Sema stmt dispatcher — transparent unwrap

**File:** `sf/src/semantic_analyzer.zig` (stmt dispatcher, ~:1767, before the defer_stmt case)

Add:
```zig
} else if (node.kind == AstKind.labeled_stmt) {
    if (node.child_0 != @intCast(u32, 0)) {
        semanticAnalyzerStmtWorkPush(self, node.child_0);
    }
```
This mirrors the existing `defer_stmt`/`errdefer_stmt` transparent unwrapper (semantic_analyzer.zig:1767-1770). The work-queue model means ONE case handles labeled while/for/block/if/switch — no per-kind handling needed. The label itself needs no semantic state (labels are resolved at lowering via break/continue payload matching).

### Edit 3: Sema expr redirect — prevent crash

**File:** `sf/src/semantic_analyzer.zig:1341` (resolveExpr stmt-redirect branch)

Add `labeled_stmt` to the branch alongside `var_decl`/`defer_stmt`/`errdefer_stmt`:
```zig
} else if (node.kind == AstKind.var_decl or node.kind == AstKind.defer_stmt or node.kind == AstKind.errdefer_stmt or node.kind == AstKind.labeled_stmt) {
    semanticAnalyzerResolveStmtIter(self, node_idx);
    result = type_mod.TYPE_VOID;
}
```
Defensive — if labeled_stmt ever reaches resolveExpr, it delegates back to the stmt resolver instead of crashing in the unhandled else.

### Edit 4: Lowerer — transparent unwrap

**File:** `sf/src/lower.zig` (`lowerStmt`, ~:3497, alongside the defer_stmt handler)

Add a `labeled_stmt` unwrap — recurse into `child_0`. Simple transparent unwrap; the inner statement (while/for/block) lowers normally. Break/continue inside the labeled statement resolve via their own handlers (existing break_stmt/continue_stmt at lower.zig:4002-4052 already look up `node.payload` for label matching — now that the parser stores the label name, labeled break/continue can match).

Note: `lowerIsNoValueStmtKind` (lower.zig:3432-3443) does NOT include `labeled_stmt` — acceptable (labeled_stmt is a statement-position wrapper; the inner statement determines value semantics).

## Gates

- Build: zig0 → zig1 bootstrap in /tmp, 0 gcc errors (QUICK_REF recipe)
- Repro `labeled_stmt_unhandled`: post-fix dump rc=0, gcc-clean, link, run. FAIL→OK
- 4 MD5 gates byte-identical: mud `50beb1bf...`, gol `0d8f0092...`, lisp `605b597e...`, json `b5f56ebd...` (no gate baseline uses labeled statements)
- Corpus: 210 repros, OK=202→203/FAIL=4→3/gg=4 (raw 8→7). No FAIL increase
- test_analyzer_bin PASS

## Follow-ups (NOT this plan)

- **I-task: rogue_mud syntax survey** — scan rogue_mud's 14 modules against the corpus + examples to find any syntax pattern NOT covered by existing repros/examples, so the next build attempt doesn't hit an unpredicted gap. (User requested; separate plan.)
- 0-FAIL goal is blocked by the 2 std-lib-deferred FAILs (`field_store_drop`, `test_stub_0` — need real std lib) and the C89-fundamental FAIL (`self_embed_optional_cycle` — infinite-size type). labeled_stmt fix reduces active defects to 1 (the 2 std-lib + 1 C89, all documented deferred/known).
