# Win-hosted zig1 investigation — `-fsafe` walk report

**Status: investigation complete. The temp `-fsafe`-clean source passes the whole Linux
battery; the MinGW-built compiler still fails `std_async.zig:259` with NO trap, so the Windows
`-ffast` failure is not explained by a masked integer overflow. No commits, no production edits.**

- Repo: `/workspace/znineeight`, branch `zig1_improvements`, HEAD `c13de0bc`
- Date: 2026-10-25
- Mode: investigation only. Temp source copy `/tmp/inv/src_fsafe`; all probes/logs under
  `/tmp/inv`. Nothing under `release/seed/*`, `run.err`, `.opencode/memory`, or the untracked P4
  docs was touched.
- Seeds/compilers used: unmodified `/tmp/seed_v121/zig1_5_clean`
  (`11de43a053bdde3be3ddc61caac31df6`) and temp builds:
  - Linux `-fsafe`: `/tmp/inv/fsafe_linux/prog` md5 `68b4e6a1b56a2ceea1c53aa4a8903ddc`
  - Linux `-ffast`: `/tmp/inv/fast_linux/prog` md5 `b0b44c480d1441c7af0dee27d13345d7`
  - MinGW CRT `-fsafe`: `/tmp/inv/win_fsafe/zig1.exe` md5 `c62f8ea4a7f6e0cb2f9e014c610a92b1`
  - MinGW CRT `-ffast`: `/tmp/inv/win_fast/zig1.exe` md5 `f0270330898c86d137c28f5071edc586`
  - MinGW CRT `-fsafe` + `-mms-bitfields`: `/tmp/inv/win_fsafe_ms/zig1.exe` md5
    `fdbc97d6ee4b292543998592ac93862e`

## Phase A — Linux `-fsafe` baseline: FAIL (as expected), first trap confirmed

```bash
cp -r /workspace/znineeight/sf/src /tmp/inv/src_fsafe
mkdir -p /tmp/inv/fsafe_linux
cd /tmp/inv && /tmp/seed_v121/zig1_5_clean -fsafe -osl -o /tmp/inv/fsafe_linux src_fsafe/main.zig
cd /tmp/inv/fsafe_linux && sh build_target.sh linux prog
cp -r /tmp/seed_v121/lib /tmp/inv/fsafe_linux/lib
cd /workspace/znineeight && /tmp/inv/fsafe_linux/prog -osl -o /tmp/inv/p_hello examples/z98/hello/main.zig
```

Emit/build rc=0 (104 files: 52 `.c` + 52 `.h`); hello compile **rc=133 (SIGTRAP)**, 0 `.c`.
gdb:

```text
#0 pal_trap
#1 zF_8EC79679_parseU64
#2 zF_EF8134BD_lexerScanNumber
#3 zF_B976BEC9_lexerNextToken
#4 zF_7C3FD09B_parserPullOne
...
#22 zF_EEBAC601_moduleRegistryParse
```

Exact site: `sf/src/lexer.zig:597-598`

```zig
var max_u64: u64 = @intCast(u64, 0);
max_u64 -= 1;
```

**Classification: intentional wrap.** Deterministic `0 - 1` in `u64`, used as the `u64` max
constant. This is a correct `-fsafe` trap, not an emitter bug. Fix: `0xFFFFFFFFFFFFFFFF`.

## Phase B — trap walk and classification

Method: only `/tmp/inv/src_fsafe` was edited (`edit`/`fastedit`, bottom-to-top, re-read before
each `fastedit`). After each class the compiler was re-emitted `-fsafe -osl`, rebuilt with
`build_target.sh linux`, and hello/lisp/stdlib/corpus re-run. No sed/perl/python transforms.

### Every trap, in discovery order

| # | Source site | Operands / context | Class | Temp safe form |
|---|---|---|---|---|
| 1 | `lexer.zig:597-598` `max_u64 -= 1` | `0 - 1`, u64 | intentional max constant | `0xFFFFFFFFFFFFFFFF` |
| 2 | `comptime_eval.zig:369` `ciToU64` neg | `0 - m`, u64 two's complement | intentional sign materialisation | `-%` |
| 3 | `c89_emit.zig:937` `cnameDedupKey` | `key*31 + byte`, u32 FNV-31 | intentional hash wrap | `*%` / `+%` |
| 4 | `c89_emit.zig:4424` signed-min literal | `0 - masked`, u64, `i64` MIN (`value=0x8000000000000000`) | intentional two's complement | `-%` |
| 5 | `lir_opt_pass.zig:1850` unary-neg fold | `0 - obits`, u64 | intentional two's complement | `-%` |
| 6 | `lir_opt_pass.zig:190` `lowMask(64)` | `0 - 1`, u64 | intentional all-ones mask | constant |
| 7 | `lir_opt_pass.zig:1993` int-cast fold | `0 - mag`, u64 | intentional two's complement | `-%` |
| 8 | `c89_emit.zig:4754,4764` | `0 - 1`, u64 | intentional all-ones mask | constant |
| 9 | `comptime_eval.zig:588` `ciDivMod` | `rem[k] << 1`, u32 top bit | intentional shifting out bit 32 | `*% 2` |
| 10 | `lexer.zig:946` `parseF64` | `mid << 32`, u64 | intentional keep-low-32 into the high half | `(mid & 0xFFFFFFFF) << 32` |
| 11 | `comptime_eval.zig:483` `ciMagSubOne` | `av - borrow`, borrow ran above the significant limbs | intentional borrow wrap | `-%` |
| 12 | **`semantic_analyzer.zig:3506`** `cpp_key` | `decl_cap << 16 \| ai`, u32; call node `node_idx=125453` | **REAL** (u32 index packing) | explicit `& 0xFFFF` (preserves `-ffast` key) |
| 13 | **`type_resolver.zig:298`** `alignUp(offset, ft.alignment)` | `v=21, a=0`; field type 75 `[2]Err`, elem type 29 named error set size/align 0 | **REAL** (layout model) | named `error_set` layout = 4/4 |
| 14 | `type_registry.zig:1081` error-set cache key | `(key ^ tag) * 1099511628211`, u64 | intentional FNV wrap | `*%` |
| 15 | **`lexer.zig:854,871/903`** `parseF64` digit count | `num_digits=801`, `h.digits[800]` read (array is `[800]u8`) | **REAL** (out-of-bounds index) | increment `num_digits` only when stored |

12 intentional wraps, 3 real defects. (Item 3 is the `cnameDedupKey` site the earlier phase-2
report suspected; it is real but only intentional hash wrapping, and it is not the phase-2 trap.)

### First REAL trap — captured fully

`semantic_analyzer.zig:3506`, while compiling
`repro/mi_matrix/stdlib_tls13_handshake_xmod/main.zig`:

```zig
var cpp_key = (@intCast(u32, decl_cap) << @intCast(u32, 16)) | @intCast(u32, ai);
```

Generated C guard (debug build):

```c
zT_272 = zig_wrap_shl_u(((zu64)(zT_270)), ((zu64)(zT_271)), 32u);
zT_275 = zig_overflow_flag_shl_u(...);
zT_277 = zT_275 == 0;
if (!(zT_277)) { pal_trap(); }
```

gdb:

```text
#0 pal_trap
#1 semanticAnalyzerRes... (semantic_analyzer_...c:22009)  [the shift guard]
#2 semanticAnalyzerRes...
...
#6 phase_SemanticAnalysis
#7 runCompiler
```

Operands: `node_idx=125453`; `decl_cap` is a `u32` AST node index and can exceed 65535, so
`decl_cap << 16` overflows u32. Under `-ffast` this silently wraps, truncating the high 16 bits
of the declaration index in the `(decl, arg)` key. `call_param_map` is only read at that site and
never populated anywhere in `sf/src` (grep: no `call_param_map` put), so the wrapped key has no
observed behavioural effect today — but it is a genuine index-packing overflow, and the first
real trap seen in the walk.

### Real layout defect (most consequential) — captured fully

`type_resolver.zig:298`, from `repro/mi_matrix/stdlib_method_syntax_ok_xmod`:

```text
#0 pal_trap
#1 alignUp(v=21, a=0) at type_resolver_...c:703
#2 layoutCompute(registry, tid=30) at type_resolver_...c:1207
#3 layoutEnsure(tid=30)
#4 typeResolverResolve
#6 phase_TypeResolution
```

gdb locals: `idx=30` (struct `Holder`), `offset=21`, `max_align=4`, `fi=3`,
`fe={name_id=49, type_id=75, offset=0}`, `ft={size=0, kind=19 (array_type), state=2,
alignment=0}`, `array_items[3]={elem=29,length=2}`, `types_items[29]={kind=23
(error_set_type), size=0, alignment=0, state=2}`.

Named error sets are registered with size/alignment 0 (`typeRegistryRegisterNamedType`) and the
topological pass marks them complete without any error-set layout arm, so a `[2]Err` field has
alignment 0. `alignUp(v,0)` computes `(v + 0 - 1) & ~(0 - 1) = (v-1) & 0 = 0`, resetting the
field offset to 0. `-ffast` quietly produces the wrong model.

Direct masking probe (`/tmp/inv/probe_errset/probe.zig`, `struct S { b: u8, errs: [2]Err }`):

| compiler build | `@sizeOf(S)` | `@offsetOf(S,"errs")` | `@sizeOf(Err)` | `@alignOf(Err)` |
|---|---:|---:|---:|---:|
| seed `-ffast` (unpatched source) | 1 | 0 | 0 | 0 |
| temp `-fsafe` source | 12 | 4 | 4 | 4 |

This is a concrete case where `-ffast` silently wrapped a real defect (`-fsafe` traps), with a
wrong compile-time layout model. Temp fix: named `error_set_type` layout is 4/4, matching
`typeRegistryGetOrCreateErrorSet`'s cached error-set type.

### Real out-of-bounds defect — captured fully

`lexer.zig` `parseF64`, from `repro/mi_matrix/lexer_float_rounding_xmod`:

```text
#0 pal_trap
#1 parseF64 at lexer_...c:7084
#2 lexerScanNumber
...
```

gdb `h = {num_digits = 801, ...}`; the array is `digits: [800]u8`, so `h.digits[num_digits - 1]`
reads index 800 (one past the end). `-fsafe`'s index guard traps; `-ffast` reads past the struct.
The digit counters incremented `num_digits` even when a digit was not stored. Fixed by counting
only stored digits; `truncated` already records the dropped non-zero digits and `int_digits`
still tracks the decimal point.

### Exact temp diff

`diff -ru /workspace/znineeight/sf/src /tmp/inv/src_fsafe` (also saved at
`/tmp/inv/logs/src_fsafe.diff`):

```diff
diff -ru sf/src/c89_emit.zig /tmp/inv/src_fsafe/c89_emit.zig
--- sf/src/c89_emit.zig
+++ /tmp/inv/src_fsafe/c89_emit.zig
@@ -934,7 +934,7 @@
     var dedup_key: u32 = @intCast(u32, 0);
     var h_ci: usize = @intCast(usize, 0);
     while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
-        dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
+        dedup_key = dedup_key *% @intCast(u32, 31) +% @intCast(u32, cname[h_ci]);
     }
     return dedup_key;
 }
@@ -4421,7 +4421,7 @@
                 var wbm2 = @intCast(u64, 1) << @intCast(u64, width_bits);
                 magnitude = wbm2 - masked;
             } else {
-                magnitude = @intCast(u64, 0) - masked;
+                magnitude = @intCast(u64, 0) -% masked;
             }
             neg_magnitude = @intCast(u8, 1);
             if (!writeMinSignedIntLiteral(emitter, temp_type_id, width_bits, magnitude)) {
@@ -4751,7 +4751,7 @@
     if (width_bits < @intCast(u32, 64)) {
         um = (@intCast(u64, 1) << @intCast(u64, width_bits)) - @intCast(u64, 1);
     } else {
-        um = @intCast(u64, 0) - @intCast(u64, 1);
+        um = 0xFFFFFFFFFFFFFFFF;
     }
     return writeSatUnsDecimal(um, buf);
 }
@@ -4761,7 +4761,7 @@
     if (width_bits < @intCast(u32, 64)) {
         mask = (@intCast(u64, 1) << @intCast(u64, width_bits)) - @intCast(u64, 1);
     } else {
-        mask = @intCast(u64, 0) - @intCast(u64, 1);
+        mask = 0xFFFFFFFFFFFFFFFF;
     }
     var ib: [24]u8 = undefined;
     var il = itoa_mod.itoa64(mask, ib[0..]);
diff -ru sf/src/comptime_eval.zig /tmp/inv/src_fsafe/comptime_eval.zig
--- sf/src/comptime_eval.zig
+++ /tmp/inv/src_fsafe/comptime_eval.zig
@@ -366,7 +366,7 @@
     var m: u64 = @intCast(u64, 0);
     if (v.len > @intCast(u8, 0)) { m = @intCast(u64, v.mag[0]); }
     if (v.len > @intCast(u8, 1)) { m = m | (@intCast(u64, v.mag[1]) << @intCast(u64, 32)); }
-    if (v.neg) { m = @intCast(u64, 0) - m; }
+    if (v.neg) { m = @intCast(u64, 0) -% m; }
     return m;
 }
@@ -480,7 +480,7 @@
     var i: usize = 0;
     while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) {
         var av: u32 = a.mag[i];
-        var d: u32 = av - borrow;
+        var d: u32 = av -% borrow;
         if (av < borrow) { borrow = @intCast(u32, 1); } else { borrow = @intCast(u32, 0); }
         out.mag[i] = d;
     }
@@ -585,7 +585,7 @@
         var carry: u32 = @intCast(u32, 0);
         k = 0;
         while (k < @intCast(usize, 9)) : (k += 1) {
-            var nv: u32 = (rem[k] << 1) | carry;
+            var nv: u32 = (rem[k] *% @intCast(u32, 2)) | carry;
             carry = rem[k] >> 31;
             rem[k] = nv;
         }
diff -ru sf/src/lexer.zig /tmp/inv/src_fsafe/lexer.zig
--- sf/src/lexer.zig
+++ /tmp/inv/src_fsafe/lexer.zig
@@ -594,8 +594,7 @@
         var base_u64 = @intCast(u64, @intCast(u32, base));
         if (digit >= base_u64) break;
-        var max_u64: u64 = @intCast(u64, 0);
-        max_u64 -= 1;
+        var max_u64: u64 = 0xFFFFFFFFFFFFFFFF;
         var max_before_mul = max_u64 / base_u64;
         if (result > max_before_mul) return max_u64;
         result = result * base_u64;
@@ -854,10 +853,10 @@
         if (!isDigit(c)) { i -= 1; break; }
         if (h.num_digits < 800) {
             h.digits[@intCast(usize, h.num_digits)] = c - @intCast(u8, '0');
+            h.num_digits += 1;
         } else {
             if (c != '0') h.truncated = true;
         }
-        h.num_digits += 1;
         int_digits += 1;
     }
@@ -871,10 +870,10 @@
             if (!isDigit(c)) break;
             if (h.num_digits < 800) {
                 h.digits[@intCast(usize, h.num_digits)] = c - @intCast(u8, '0');
+                h.num_digits += 1;
             } else {
                 if (c != '0') h.truncated = true;
             }
-            h.num_digits += 1;
         }
     }
@@ -944,7 +943,7 @@
                     var hl: u64 = m_hi * p_lo;
                     var hh: u64 = m_hi * p_hi;
                     var mid: u64 = (ll >> 32) + (lh & 0xFFFFFFFF) + (hl & 0xFFFFFFFF);
-                    var lo: u64 = (mid << 32) | (ll & 0xFFFFFFFF);
+                    var lo: u64 = ((mid & 0xFFFFFFFF) << 32) | (ll & 0xFFFFFFFF);
                     var hi: u64 = hh + (lh >> 32) + (hl >> 32) + (mid >> 32);
                     return fastRound(hi, lo, false, e, h.negative);
                 } else {
diff -ru sf/src/lir_opt_pass.zig /tmp/inv/src_fsafe/lir_opt_pass.zig
--- sf/src/lir_opt_pass.zig
+++ /tmp/inv/src_fsafe/lir_opt_pass.zig
@@ -187,7 +187,7 @@
 };
 
 fn lowMask(w: u32) u64 {
-    if (w >= @intCast(u32, 64)) return @intCast(u64, 0) - @intCast(u64, 1);
+    if (w >= @intCast(u32, 64)) return 0xFFFFFFFFFFFFFFFF;
     return (@intCast(u64, 1) << @intCast(u64, w)) - @intCast(u64, 1);
 }
@@ -1847,7 +1847,7 @@
         if (resDeclIntType(c, res, &rw, &rs) == @intCast(u8, 0)) return @intCast(u8, 0);
         if (rw != ow or rs != os) return @intCast(u8, 0);
         if (op == @intCast(u8, 0) or op == @intCast(u8, 3)) {
-            var v: u64 = (@intCast(u64, 0) - obits) & om;
+            var v: u64 = (@intCast(u64, 0) -% obits) & om;
             out_value.* = v;
             out_is_bool.* = @intCast(u8, 0);
             return @intCast(u8, 1);
@@ -1990,7 +1990,7 @@
             var tm = lowMask(tw);
             var v: u64 = @intCast(u64, 0);
             if (is_neg != @intCast(u8, 0)) {
-                v = (@intCast(u64, 0) - mag) & tm;
+                v = (@intCast(u64, 0) -% mag) & tm;
             } else {
                 v = mag & tm;
             }
diff -ru sf/src/semantic_analyzer.zig /tmp/inv/src_fsafe/semantic_analyzer.zig
--- sf/src/semantic_analyzer.zig
+++ /tmp/inv/src_fsafe/semantic_analyzer.zig
@@ -3503,7 +3503,7 @@
         while (ai < args_n) : (ai += 1) {
             var expected: u32 = @intCast(u32, 0);
             if (has_params != @intCast(u8, 0) and ai < @intCast(usize, pcount)) {
-                var cpp_key = (@intCast(u32, decl_cap) << @intCast(u32, 16)) | @intCast(u32, ai);
+                var cpp_key = ((@intCast(u32, decl_cap) & @intCast(u32, 0xFFFF)) << @intCast(u32, 16)) | @intCast(u32, ai);
                 expected = type_mod.TYPE_UNDEFINED;
                 if (hash_mod.u32ToU32MapGet(self.call_param_map, cpp_key)) |cpp_v| { expected = cpp_v; } else { expected = self.registry.xt_items[@intCast(usize, pstart) + ai]; }
                 hash_mod.u32ToU32MapPut(self.call_arg_types, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, ai)), expected);
diff -ru sf/src/type_registry.zig /tmp/inv/src_fsafe/type_registry.zig
--- sf/src/type_registry.zig
+++ /tmp/inv/src_fsafe/type_registry.zig
@@ -1078,7 +1078,7 @@
     var ki: u16 = 0;
     while (ki < tags_count) : (ki += 1) {
         var tag = self.xn_items[@intCast(usize, tags_start + @intCast(u32, ki))];
-        key = (key ^ @intCast(u64, tag)) * @intCast(u64, 1099511628211);
+        key = (key ^ @intCast(u64, tag)) *% @intCast(u64, 1099511628211);
     }
     if (hash_mod.u64ToU32MapGet(&self.es_cache, key)) |existing| return existing;
     esAppend(self, ErrorSetPayload{ .tags_start = tags_start, .tags_count = tags_count });
diff -ru sf/src/type_resolver.zig /tmp/inv/src_fsafe/type_resolver.zig
--- sf/src/type_resolver.zig
+++ /tmp/inv/src_fsafe/type_resolver.zig
@@ -400,6 +400,10 @@
         ty.alignment = @intCast(u16, max_align);
         if (ty.size == @intCast(u32, 0)) { ty.size = @intCast(u32, 1); ty.alignment = @intCast(u16, 1); }
         registry.types_items[idx] = ty;
+    } else if (ty.kind == TypeKind.error_set_type) {
+        ty.size = @intCast(u32, 4);
+        ty.alignment = @intCast(u16, 4);
+        registry.types_items[idx] = ty;
     }
 }
```

The temp source is **not** a production patch. The explicit choice at `semantic_analyzer.zig:3506`
preserves the `-ffast` wrapped key exactly; the other real-defect fixes are the natural corrections
(error-set layout 4/4, bounded digit storage).

## Phase C — MinGW CRT `-fsafe`: still fails `std_async`, NO trap

Recipe (same as phase 2, with the temp source):

```bash
cd /tmp/inv
/tmp/seed_v121/zig1_5_clean -fsafe -osw -o /tmp/inv/win_fsafe src_fsafe/main.zig
cd /tmp/inv/win_fsafe
i686-w64-mingw32-gcc -m32 -std=c89 -O0 -DZIG_WIN32 -I . -c *.c
i686-w64-mingw32-gcc -m32 *.o -o zig1.exe -lkernel32 -lwinmm -lwsock32
cp -r /tmp/seed_v121/lib /tmp/inv/win_fsafe/lib
```

Emit rc=0 (52 `.c`), compile rc=0, link rc=0. Usage under Wine rc=0.

| Probe (`wine zig1.exe`) | Result |
|---|---|
| `-osw` no-std struct probe (`nsrc/min.zig`) | **rc=0**, 5 `.c` — Windows-hosted compiler works on a no-std program |
| `-osw` hello | **rc=2**, 0 `.c`, first errors `std_async.zig:259` `t.state` / `:262` `s.count` / `:263` `s.tasks`, then `std_debug.zig:64` `tag.len` |
| `-osl` hello | **rc=2**, identical `std_async.zig:259` first failure |
| `-mms-bitfields` rebuild of the same `-fsafe` C | **rc=2**, identical first failure (no change) |
| temp `-ffast` MinGW build (Phase D) | **rc=2**, identical first failure |

No `pal_trap`/`SIGTRAP` occurred in any of these runs. Because a fully `-fsafe`-clean source
still produces the same analyzer field-resolution diagnostics, the Windows `std_async` failure is
**not** a down-stream effect of an unchecked overflow that `-ffast` masked. `-mms-bitfields` had
no effect, so the classic MS bitfield-layout switch is not the cause of this failure. The
remaining class is MinGW/Win32-PAL-built compiler state (analyzer/type registry) or a
toolchain-specific layout/ABI difference — the secondary hypothesis named in the brief.

## Phase D — `-ffast` comparison (not a fix)

- Temp source built `-ffast` on Linux (`/tmp/inv/fast_linux/prog`): hello `Hello, world!` and
  lisp `(+ 1 2)` → `b3d9f897…`, i.e. correct.
- Temp source built `-ffast` with MinGW CRT (`/tmp/inv/win_fast/zig1.exe`): hello **fails exactly
  like the `-fsafe` MinGW build**, first error `std_async.zig:259`, no trap.
- **Fixing the source does not remove the `std_async` failure.** Therefore the failure is not
  explained by wrapped real overflow.
- `-ffast` masking is nevertheless real elsewhere:
  - layout probe: seed `-ffast` reports `@sizeOf(S)=1`, `@offsetOf(S,"errs")=0`,
    `@sizeOf(Err)=0`, `@alignOf(Err)=0`; the temp-safe source reports `12/4/4/4`.
  - `parseF64` over-800-digit literals: `-ffast` retains the out-of-bounds `digits[800]` read;
    the temp-safe source clamps storage. (The corpus fixture's runtime output still matched under
    the seed `-ffast` compiler — the UB read happened to land on zero — so this was a latent
    real bug, not an observed gate movement.)
  - `cpp_key` and error-set cache keys silently wrap under `-ffast`; the explicit safe forms give
    identical wrapped values for the key paths.

## Phase E — canonical battery with the temp `-fsafe` compiler

| Gate | Result |
|---|---|
| Corpus (`scripts/corpus/classify`, current tree 1188 dirs) | **1014 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH**; byte-identical per-dir classes to the seed `-ffast` baseline (diff empty). The documented frozen-1124 component is 950 OK / 58 GREEN / 116 FAIL = 1124; the extra 64 post-1124 dirs are all OK. |
| Stdlib (`scripts/stdlib/verify_stdlib.sh`) | **336/336 PASS, 0 FAIL; `STDLIB GATE OK`** (includes crosscheck `10 PASS / 0 FAIL over 10 modules`) |
| Closeout `scripts/closeout/verify_upgraded.sh` | **CLOSEOUT OK**; A1–A5/B1–B7 PASS, including the five goldens A2 `96654b39…`, A3 masked, B2 `3fb6709e…`, B3 `cf3c82f9…`, B4 `ad947e1e…` |
| Runtime goldens | gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `(+ 1 2)` `b3d9f8974da24ddbf9d389f3d7d97322`; lisp canonical 12-line `96654b3910a54d8bb7ec3ddfc0f26c6a`; json `8bda3d5a1ec07d14a301bc343df32bf8`; mud server `66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7`. **5/5 (mud pair counted as one) and mud pair both exact.** |
| 8 dump-MD5 pins (both modes) | **8/8 identical to the seed v121 baseline** on this build (same-build comparison): safe mud `bab44607…`, gol `738c7ca4…`, lisp `7facfa7c…`, json `452e8875…`; fast mud `0436db27…`, gol `222fab7c…`, lisp `de8f1afd…`, json `f4f19376…`. (The v119 table in QUICK_REF is from a different compiler build and is not directly comparable.) |
| Markers (`--markers --dump-c89` on mud_server) | rc=0; **3252 lines / 37293 B** (recorded; differs from the v98 3437/38384 due to the source changes) |
| Examples matrix (26 dirs: 27 entries minus `z9dbg`) | **26/26 emit+build rc=0**. Run: 22 exit 0 including the four gate programs; gol needs ~10 s of internal sleeps (passes with a longer timeout and matches its golden); mud/rogue are servers (session script passes for mud); z9play/z9torr return rc=1 under `/dev/null` for environment reasons (no terminal/args), not compiler diagnostics. |

First stdlib run before all fixes was `290 PASS / 46 FAIL`; after the fixes it is `336 PASS / 0
FAIL`. First corpus run showed 3 `CRASH` dirs (`ast_walk_error_set_xmod`,
`lexer_float_rounding_xmod`, `sig_known_type_ok_xmod`); all three became OK after the error-set
FNV/digit-count fixes.

## Root cause / conclusions

1. **Shipped zip under `-fsafe` (host-independent):** the compiler source is not `-fsafe`-clean.
   The first failure on the very first integer literal is the intentional `max_u64 -= 1`
   (`lexer.zig:597-598`); the full walk found 12 intentional wraps and 3 real defects. This is a
   compiler-source profile problem, exactly as the operator correction stated.
2. **`-ffast` Linux-hosted compiler:** silently wraps those intentional expressions and the three
   real defects. The real layout defect can produce wrong compile-time layout (probe:
   `@sizeOf(S)=1`, `@offsetOf(...,"errs")=0`), and `parseF64` has a real 1-element OOB read for
   >800-digit literals. These are genuine compiler defects, but none of them causes the Windows
   `std_async` diagnostic.
3. **Windows-hosted MinGW compiler:** after making the source `-fsafe`-clean and fixing every real
   safe-mode trap found by the whole Linux battery, the MinGW-built compiler **still** fails
   `hello` at `std_async.zig:259` `t.state` (and `std_debug` `tag.len`) with **no trap**, on both
   `-osw` and `-osl` targets, under both `-fsafe` and `-ffast` builds, and with `-mms-bitfields`.
   So **the `std_async` failure is not explained by an unchecked/masked integer overflow**. It is
   a separate MinGW-built-compiler/analyzer/type-registry (secondary layout/ABI or Win32-PAL)
   problem that must be root-caused by its own task.
4. The earlier phase-2 claim that the 2a `-fsafe` trap was `cnameDedupKey` remains corrected:
   the first trap is `parseU64`, and `cnameDedupKey` is an intentional FNV wrap that is only hit
   later during emission.

## MSVC/OpenWatcom prediction (unconfirmed — no operator probe)

- As shipped, the `-fsafe` zip C contains checked arithmetic, so the same `parseU64` `0 - 1`
  trap should occur on any C toolchain (MSVC/OW included), independent of ABI. The source fixes
  are required in all cases.
- After the source fixes, whether MSVC/OW reproduces the `std_async` field-resolution failure is
  **unknown**. The failure is present in a MinGW-built compiler and is unaffected by
  `-mms-bitfields`; it could be a MinGW CRT/toolchain artifact (in which case MSVC/OW with a
  conforming layout may work) or a Win32-PAL/registry defect (in which case MSVC/OW will fail
  identically). This needs a real MSVC/OW probe.

## Seed decision

- The Win9x zip **stays `-fsafe`**; `-ffast` is not a fallback and was not adopted.
- The temp `/tmp` fixes are evidence, not a production patch. Source fixes (intentional-wrap
  rewrites, error-set layout, `parseF64` digit bound, `cpp_key` packing) are a separate compiler
  task with its own gates and seed rotation.
- No commits and no seed-artifact changes were made.

## Production preservation (2026-10-25)

- **Copy exact.** Operator-authorized `cp` of the 7 files from `/tmp/inv/src_fsafe` into `sf/src`;
  `diff -rq sf/src /tmp/inv/src_fsafe` is empty, and the `git diff` hunk bodies are identical to
  `/tmp/inv/logs/src_fsafe.diff` (17 hunks covering the 15 intended sites: 12 intentional wraps +
  3 real defects). `git diff --check` clean; only those 7 files are in the fix commit.
- **Fix commit:** `5dbd24448fdb0f12b73f0bf9ec8faa79502ca470`
  (`fix(src): make the compiler -fsafe-clean (12 wraps + 3 real defects)`). No seed artifact was
  modified or committed.
- **Build from the committed v120 seed** (`git show c13de0bc:release/seed/zig1-seed.tgz`, archive
  md5 `18c21ebfc18f3014f0ccab2f10f38688`) with `scripts/seed/build_from_seed.sh`: hop1 == hop2
  == **`F_new` `dcfc9e70e475a8a08c0487dafd2e6b45`**, moved from the v120 fixed point
  `11de43a053bdde3be3ddc61caac31df6`.
- **`-ffast` production battery** on `/tmp/fixed_v121_build/zig1_5_clean`: corpus frozen-1124
  **950 OK / 58 GREEN / 116 FAIL, 0 movers** vs the v120 seed baseline (all 1188 dirs also
  identical); goldens **5/5** exact; dump-MD5 pins **8/8 unchanged** (both modes); markers
  **3252 lines / 37293 B**; examples **26/26**; `verify_stdlib` **336 PASS / 0 FAIL**; crosscheck
  **10 PASS / 0 FAIL**. All pass.
- **Accepted temp `-fsafe` evidence:** the copied source is byte-identical to `/tmp/inv/src_fsafe`,
  so the prior agent's full `-fsafe` battery (Phase E above: corpus 0 movers, stdlib 336/0,
  goldens 5/5, pins 8/8, examples 26/26, `CLOSEOUT OK`) is accepted as-is; no duplicate full
  `-fsafe` battery was run.
- **Remaining MinGW `std_async` result (not fixed here):** a fully `-fsafe`-clean source still
  makes the MinGW-CRT-built compiler reject `hello` at `std_async.zig:259` (`t.state`) with **no
  trap**, on both `-osw` and `-osl`, under `-fsafe`, `-ffast`, and `-mms-bitfields` (Phase C/D).
  It remains a separate Windows layout/ABI or Win32-PAL/registry task.
- Exact commands/results: `production-validation.md`.

## Remaining uncertainty

- The exact MinGW-only mechanism behind the `std_async`/`std_debug` field-resolution failure is
  not root-caused here. `-mms-bitfields`, target (`-osw`/`-osl`), and safety mode are ruled out as
  causes; the no-std path works. The next step is a symbolic/debug build of the MinGW compiler at
  the first `Task.state` lookup (type id/registry state) and a comparison against the Linux-gcc
  build of the same C.
- The corpus has grown from the frozen 1124 to 1188 dirs; the 1124 component matches the
  documented baseline exactly, but no explicit historical per-dir list was available in-tree for
  a set-difference check.
- MSVC/OpenWatcom remains a prediction only.
- Logs are under `/tmp/inv/logs/` and are not committed.
