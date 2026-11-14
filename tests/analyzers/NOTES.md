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
| `capture_double_free.zig` | exactly 1 ERR_2005 | DoubleFreeAnalyzer capture propagation: the capture is an alias of the allocation; double `sandFree` through the capture -> ERR_2005 |
| `dead_arm.zig` | 0 errors, 0 warnings | Comptime-untaken arms do not exist for analysis (T3 Zig rule): double free + local-address behind `if (false)` produce nothing |
| `surface_types.zig` | 0 diagnostics | Current surface: arbitrary-width ints (`i7`/`u48`/`i3`/`u33`), packed-union types, tagged-union `.tag` member access |
| `sig_arb_width.zig` | 0 diagnostics | SIG-1: arbitrary-width ints (`i7`/`u48`/`i3`/`i63`/`u64`/`u1`) in parameters and returns are accepted |
| `sig_negative.zig` | exactly one each of `ERR_2010`, `ERR_2011`, `ERR_2012`, `WARN_7010` | SIG-1 negative shapes: `void` parameter, incomplete base nested in `?`, `anytype`, and a named return larger than 64 bytes |
| `gpa_double_free.zig` | >=1 error | GPA ownership (Task 7): module-qualified `gpa.gpaAlloc` / `gpa.gpaFree` calls recognized by final identifier; second free -> ERR_2005 |
| `gpa_use_after_free.zig` | >=4 errors | GPA ownership (Task 7): module-qualified alloc/free; direct indexed read plus comparison, compound-assignment, and arithmetic wrapper uses after free -> ERR_2006 (error[3079]) |
| `gpa_leak.zig` | 0 errors, >=1 warning | GPA ownership (Task 7): bare `gpaAlloc` allocation without a free in the same block -> WARN_6005_MEMORY_LEAK |
| `gpa_alias_negative.zig` | 0 errors, 0 warnings | GPA ownership documented limitation: a copied pointer still does not claim use-after-free after the original is freed; the copy is an alias for free/leak state, and the original free clears the leak warning |
| `df_alias_chain.zig` | exactly 1 ERR_2005 | DF-1: `var q = p` and `r = q` alias one allocation; free `p` then `r` -> double free, no WARN_6006/leak |
| `df_capture_alias_chain.zig` | exactly 1 ERR_2005 | DF-1 exact defect-c shape: `var op = p; if (op) \|q\| { free(p); free(q); }` -> double free |
| `df_field.zig` | exactly 1 ERR_2005 | DF-2: allocation stored in `st.p`, freed twice through the field chain; no false INFO_7001 |
| `df_index.zig` | exactly 1 ERR_2005 | DF-2: allocation stored in `arr[0]`, freed twice through the index chain; no false INFO_7001 |
| `df_owner_handle.zig` | 0 diagnostics | DF-3: allocator handles are not ownership-transferred; leak/double-free state stays correct |
| `df_transferred_free.zig` | 1 INFO_7001, 1 WARN_6006 | DF-4: a real ownership-taking call (`take`) transfers; freeing the `transferred` pointer keeps its state and reports the documented untracked-free diagnostic (no false ERR_2005/leak) |
| `df_alias_reassign.zig` | 0 diagnostics | DF-1 fix: reassigning the canonical name detaches its inbound aliases; `q` keeps the first allocation while `p` gets the second, so freeing both is not a double free and overwriting `p` is not a leak |
| `df_alias_branch.zig` | 0 diagnostics | DF-1 fix: aliases fork/merge with the state map; a then-arm alias cannot leak into the else fork (no false overwrite/leak) |
| `df_unknown_call.zig` | 0 diagnostics | DF-3 fix: unknown calls (`read`) do not transfer ownership, so `read(p); sandFree(s, p)` emits neither INFO_7001 nor WARN_6006 |
| `df_alloc_handle_var.zig` | 0 diagnostics | DF-3 fix: allocator handles supplied by `var` initializers (not only statement-level calls) are recorded, so `take(h)` on a handle is not a transfer |
| `df_alias_reassign_multi.zig` | 0 diagnostics | DF-1 fix round 2: reassigning the canonical name keeps all inbound aliases (`q`, `r`) in one class; freeing `q` releases the old allocation for the class and `r` is not a stale leak |
| `df_alias_reassign_multi_double.zig` | exactly 1 ERR_2005 | DF-1 fix round 2: after canonical reassignment the survivors are one class, so freeing `q` then `r` is a real double free of the old allocation |
| `df_alias_reassign_multi_leak.zig` | exactly 1 WARN_6005 | DF-1 fix round 2: one old allocation reported once at scope exit, not once per surviving alias |
| `df_untracked_free.zig` | exactly 1 WARN_6006 | DF-4 fix round 2: freeing an `untracked` (null) binding preserves the state and reports the untracked free instead of silently marking it freed |

Ownership transfer is restricted to explicit ownership-taking callee names
(`take`, `takeOwnership`, `take_ownership`, `transfer_ownership`, `consume`,
`destroy`, `deinit`, `release`, `drop`). Everything else is a read/plain call
and leaves allocation state unchanged.

`self_test_dive.md` is a historical C++-bootstrap deep dive (kept; not a
fixture).
