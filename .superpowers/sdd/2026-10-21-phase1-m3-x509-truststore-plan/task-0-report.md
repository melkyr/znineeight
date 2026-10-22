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

## Step 3 — tests

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

Full std gate (fixtures + crosscheck):

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_v114_build/zig1_5_clean
...
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

Code/fixture commit: `7a0bf60cc314ce041695edbcff374299e2e50ec8`
(`fix(std_crypto): reject oversized PSS salt_len (M2 carry-over)`).

Report committed separately (`docs(sdd): M3 T0 report`). Seed rotation not
performed (remains Task 3, v115).

## Concerns

- Host is 64-bit, so the negative KATs exercise the explicit `sl > em.len`
  rejection rather than an actual 32-bit `usize` overflow; the added guard is
  the overflow-independent defense for 32-bit targets.
