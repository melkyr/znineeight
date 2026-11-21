# parsergap_strict_comma_xmod — GREEN-GUARD: fn-call missing-comma `f(1 2)` correctly rejected (F-STRICTCOMMA)

## What it tests
A fn-call argument list missing the separating comma must be a **clean parse error**,
matching real Zig (which rejects `f(1 2)` — expected comma):

```zig
var r1 = f(1 2);        // malformed — no comma between args
```

Reclassified **GREEN-GUARD** (correct rejection, oracle-governed): real Zig's grammar
requires a `,` between call arguments, so rejecting `f(1 2)` is correct compiler
behavior — not a gap. 0 `.c` emitted, `error[2000]` diagnostic only, no ICE, no crash.

## Fix (F-STRICTCOMMA, commit `7bb775ad` — restore strict comma/close diagnostics)
The fn-call argument loop at `sf/src/parser.zig:417-423` (fn `parserParseFnCall`) now
REQUIRES the comma between arguments instead of advancing it optionally:

```zig
while (true) {
    var arg = try parserParseExprPrec(self, Prec.none);
    u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, arg);
    if (parserPeek(self).kind == TokenKind.rparen) break;
    _ = try parserExpect(self, TokenKind.comma);   // REQUIRE the comma between args
    if (parserPeek(self).kind == TokenKind.rparen) break;
}
var rparen = try parserExpect(self, TokenKind.rparen);
```

After each argument: if the next token is `)` the list ends (no comma required); otherwise
the comma is demanded via `parserExpect` (missing comma → `error[2000] expected ',' but
found <tok>`). The post-comma `)` break preserves the trailing-comma form (`f(1, 2,)`,
`f(1, )`) — trailing commas are legal in real Zig and remain accepted.

## Verified behavior (2026-08-24, `/tmp/fx_subfolder/zig1`, rebuilt at HEAD `a9ea91f0`, canonical std reinstalled)

```
cd repro/mi_matrix/parsergap_strict_comma_xmod && timeout 60 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fx main.zig
```

- **rc=2** (frontend error; no crash, no ICE)
- **`/tmp/fx/*.c` = 0 files** (0 `.c` emitted)
- stderr:

```
main.zig:4:17: error[2000]: expected ',' but found integer literal
pub fn main() void {
                 ^
main.zig:4:17: error[2000]: unexpected token
pub fn main() void {
                 ^
main.zig:6:0: error[2000]: expected expression
    std.io.printInt(r1);
^
main.zig:6:0: error[2000]: unexpected token
    std.io.printInt(r1);
^
```

## Controls (must stay GREEN — the fix must not break them)
- **Empty call `f()`**: dump rc=0, `.c` emitted, gcc -c rc=0.
- **Single arg `f(1)`**: dump rc=0, `.c` emitted, gcc -c rc=0.
- **Valid call `f(1, 2)`**: dump rc=0, `.c` emitted, gcc -c rc=0, link+run rc=0 prints `3`.
- **Trailing comma `f(1, 2,)`**: dump rc=0, `.c` emitted, gcc -c rc=0 (trailing comma legal).
- **Unterminated `f(1`**: rc=2, `error[2000]` cascade, 0 `.c` (unchanged).

## Historical RED baseline (2026-08-17, HEAD `c8d08939` — superseded by the fix)
Before `7bb775ad` the loop advanced the comma OPTIONALLY
(`if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);`), so `f(1 2)`
was SILENTLY accepted and compiled to the same 2-arg call as `f(1, 2)` (dump rc=0, gcc
rc=0, run prints `3`; the emitted `.c` for `f(1 2)`/`f(1,2)`/`f(1,2,)` were byte-identical).
That silent-accept was the bug; the fix (F-STRICTCOMMA) makes the missing comma a hard
error, and the fixture is now a correct-rejection green-guard.
