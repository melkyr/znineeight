# M3 Task 0 report — PSS salt-length hardening

Status: DONE

Branch: `zig1_improvements` (base `902861ce`)

## Step 1 — overflow-safe salt-length check

`sf/src/std_crypto.zig` `pssCheck` now rejects `sl > em.len` before the
`hlen + sl + 2` addition, so an oversized 32-bit `salt_len` cannot overflow
`usize` and bypass the length checks.

Diff:

```
@@ -1513,6 +1513,7 @@ fn mgf1(alg: HashAlg, seed: []const u8, out: []u8) void {
 fn pssCheck(alg: HashAlg, hash: []const u8, salt_len: u32, em: []const u8, em_bits: usize) bool {
     var hlen: usize = hashAlgLen(alg);
     var sl: usize = @intCast(usize, salt_len);
+    if (sl > em.len) return false;
     if (em.len < hlen + sl + 2) return false;
```

## Step 2 — negative KATs

`repro/mi_matrix/stdlib_rsa_verify_xmod/main.zig` adds two negative cases
expecting `error.BadSignature` (never a trap):

```
+    checkBadPss(n[0..], 65537, crypto.HashAlg.sha256, h256[0..], 0xFFFFFFFF, sig_pss_32[0..], "pss salt_len u32 max rejected");
+    checkBadPss(n[0..], 65537, crypto.HashAlg.sha256, h256[0..], 0x80000000, sig_pss_32[0..], "pss salt_len 2^31 rejected");
```

These are the spec-required cases, but they are **non-discriminating**
against the pre-fix `pssCheck`: `0x80000000` already fails the length check,
and `0xFFFFFFFF` wraps `hlen + sl + 2` to `33` on 32-bit `usize` and then the
PS scan fails for a real PSS encoding. A genuinely guard-only
public-API KAT is impossible without changing the API/plan: every
overflowing `salt_len` makes `ps_len = db_len + d - 1 >= db_len`, so the
pre-fix code reads uninitialized `db` past the decoded DB; making that
deterministically accept (or trap) would require exposing `pssCheck` or
crafting an invalid signature outside the public API. The limitation is
documented in the fixture next to the KATs.

## Step 3 — tests (fix round 1, refreshed sibling lib)

Review round 1 found the initial gate runs imported the pre-fix
`std_crypto` from the compiler's sibling `lib/`, not the submitted
`sf/src/std_crypto.zig`. Refreshed the sibling lib and reran all gates:

```
$ cp sf/src/std_crypto.zig /tmp/m2_t4_v114_build/lib/std_crypto.zig
$ md5sum /tmp/m2_t4_v114_build/lib/std_crypto.zig sf/src/std_crypto.zig
080f6218877586edf3b0cdc04d3e4765  /tmp/m2_t4_v114_build/lib/std_crypto.zig
080f6218877586edf3b0cdc04d3e4765  sf/src/std_crypto.zig
$ cmp -s /tmp/m2_t4_v114_build/lib/std_crypto.zig sf/src/std_crypto.zig && echo LIB_MATCH
LIB_MATCH
```

The compiler resolves imports from the binary-relative default lib
(`pal.getDefaultLibPath` -> `<exe_dir>/lib`, `sf/src/main.zig:508-514`,
`sf/src/emit_support.zig:1312`), so the refreshed sibling lib is the copy
used by the fixture builds below.

Targeted fixture, 3 runs:

```
$ for i in 1 2 3; do bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_rsa_verify_xmod; done
=== run 1 ===
PASS repro/mi_matrix/stdlib_rsa_verify_xmod
----------------------------------------
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
exit=0
=== run 2 ===
PASS repro/mi_matrix/stdlib_rsa_verify_xmod
----------------------------------------
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
exit=0
=== run 3 ===
PASS repro/mi_matrix/stdlib_rsa_verify_xmod
----------------------------------------
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
exit=0
```

Full std gate (fixtures + crosscheck), exact summary lines:

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_v114_build/zig1_5_clean
...
PASS repro/mi_matrix/stdlib_rsa_verify_xmod
run_fixtures: 320 PASS / 0 FAIL over 320 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
verify_stdlib exit=0
FAIL lines: 0
```

Standalone crosscheck:

```
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
run_crosscheck exit=0
```

## Step 4 — commit

Code/fixture commits:

- `7a0bf60cc314ce041695edbcff374299e2e50ec8`
  (`fix(std_crypto): reject oversized PSS salt_len (M2 carry-over)`)
- `3e7b57b21056239e4a234cecfa0518adfba0fe18`
  (`fix(std_crypto): document non-discriminating PSS salt_len KATs`)

Report committed separately (`docs(sdd): M3 T0 report`). The sibling-lib
refresh itself is test-environment state under `/tmp`, not a repo change.
Seed rotation not performed (remains Task 3, v115).

## Concerns

- The harness compiles and runs the fixture as 32-bit (`gcc -m32`), and Z98
  emits a 32-bit `usize`, so the KATs do run under 32-bit semantics. The
  supplied oversized cases still do not discriminate the guard from the
  pre-fix code (see Step 2); the guard itself is verified by inspection.
