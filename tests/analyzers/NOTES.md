# tests/analyzers — analyzer fixture corpus (T5)

Source-level fixtures for the four passes in `sf/src/analyzer.zig`. The runner
is `testFixture` in `sf/src/tests/test_analyzer_bin.zig` (T5): it lexes +
parses each fixture and runs `runAllAnalyzers` over the parsed module, then
asserts the per-fixture contract below. Run the test binary from the repo root
(fixture paths are repo-relative).

## Invocation

```bash
# with the seed-built compiler (zig1_5_clean)
zig1_5_clean -ffast --dump-c89 --output-dir <out> sf/src/tests/test_analyzer_bin.zig
sh <out>/build_target.sh linux test_analyzer_bin
<out>/test_analyzer_bin          # "Analyzer tests passed." rc=0
```

`-ffast` is required: the default emission mode instruments integer overflow
and the embedded lexer's `parseU64` (`max_u64 -= 1`) traps on first number
literal under those checks (toolchain semantics, pre-existing).

## Fixtures

| fixture | contract | covers |
|---|---|---|
| `fnptr_opt_aggregate.zig` | 0 errors, 0 warnings | SignatureAnalyzer accepts fn-ptr returns of `?Aggregate` / `E!Aggregate` (D1 shapes, post-T1/T2); rules reach the aggregate bases through the wrappers |
| `capture_lifetime.zig` | 0 errors, >=1 warning | LifetimeAnalyzer capture propagation (tech-debt §2.1): `if (op) \|ptr\| { return ptr; }` inherits `op`'s local provenance -> WARN_6010 |
| `capture_double_free.zig` | >=1 error | DoubleFreeAnalyzer capture propagation: the capture inherits the allocated state (origin marked transferred); double `sandFree` through the capture -> ERR_2005 |
| `dead_arm.zig` | 0 errors, 0 warnings | Comptime-untaken arms do not exist for analysis (T3 Zig rule): double free + local-address behind `if (false)` produce nothing |
| `surface_types.zig` | 0 errors, 0 warnings | Current surface: arbitrary-width ints (`i7`/`u48`/`i3`/`u33`), packed-union types, tagged-union `.tag` member access |

`self_test_dive.md` is a historical C++-bootstrap deep dive (kept; not a
fixture).
