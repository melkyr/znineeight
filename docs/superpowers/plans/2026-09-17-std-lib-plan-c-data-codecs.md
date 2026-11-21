# Z98 std-lib Plan C — L4 data structures + L5 encoders/decoders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the L4 data-structure/algorithm modules (`std_map`, `std_sort`, `std_heap`, `std_rle`) and the L5 encoder/decoder modules (`std_crypto`, `std_parse`, `std_base64`, `std_hex`, `std_utf8`) with fixtures and the layering gate green.

**Architecture:** One plan, nine module tasks plus the band's R7b usage programs in the closeout, ordered by the blueprint's construction order (L5 crypto early — it is pure and vector-gated — then L4, then the remaining L5 codecs). Each module is authored in `sf/src/std_<name>.zig` with the blueprint's exact signatures, gets `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixtures, and is validated by the six gates. A Task 1b I/F pair (added by the operator ruling m1670) pins and fixes a found compiler ICE (a compound field-store as a `while` continue expression); it is the one `sf/src` change and it moves the fixed point. **This plan runs after Plan B; it is the last plan in the std-lib extension program.**

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.arena`, bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` §4 (Plan C), §5, §6; module signatures in `sf/docs/std_lib_extension.txt` §3 (L4, L5).

**Sequence:** PREVIOUS plan: [`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md) (L3 + L6). NEXT plan: none — final plan in the std-lib extension program.

## Global Constraints

- **Precondition:** Task 0 + Plan A + Plan B complete.
- **Baseline (re-verify at Task 1).** Record HEAD, the fixed point, the seed version/archive md5, the corpus `EXPECTED_FAIL.md` header. Adding std modules MUST NOT move the fixed point — if it does, STOP. **Exceptions (operator rulings m1670/m1703/m1735/m1787):** the authorized `sf/src` changes in this plan are Task 1b-F (the found field-store-as-continue-expression ICE fix, including the operator-ruled nested-case extension), Task 2b-F (the found 64-bit/f64 literal limitations), Task 3b-F (the found discarded fallible-struct-call catch defect), and Task 4b-F (the found array-of-struct-literal defect); each MOVES the fixed point and rotates the seed. (The FramePool / `@asyncFrameSize` const-evaluator work is a separate authorized task.)
- **Build only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>`; never invoke `zig0`.
- **gcc flag-set (binding):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. `timeout 120` on every binary.
- **Layering (R3):** L4 and L5 both import L0-L2 only — never siblings, never each other. Plan C is independent of Plan B.
- **Arena (R1):** `std_map`/`std_heap` allocate at init; `std_rle`/`std_base64`/`std_hex` allocate output only; `std_sort`/`std_crypto`/`std_parse`/`std_utf8` do not allocate. `OutOfMemory` in every allocating function's error set.
- **Determinism (R6):** `std_map` iteration order is insertion-index order (deterministic); `std_sort` is not stable (documented).
- **Fixtures (R7):** one `repro/mi_matrix/stdlib_<module>_<name>_xmod` per public function.
- **Usage programs (R7b):** each layer band ships usage programs under `stdlib_test/`; every module in this band is complete only when its usage program is GREEN.
- **Seed `lib/` copy lists:** each task that adds a module extends both `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` `lib/` copy lists in the same commit; the closeout verifies the lists are complete. (`scripts/self_compile/build_zig1_5.sh:12` keeps its legacy 5-module list on the retired zig0 path — a known divergence; do not silently change it.)
- **Crypto gate:** RFC/FIPS normative vectors (RFC 3174 SHA-1, FIPS 180-4 SHA-256, RFC 1321 MD5, IEEE 802.3 CRC-32); streaming vs one-shot equality; empty input.
- **Edits only via `edit`/`fastedit`**; never stage `mnemoria/` or `.zig1_*.tmp`; declare every residual gap.
- **Recorded compiler gap (defer to Plan C; fix alongside the FramePool work).** `@asyncFrameSize(fn)` in array-size position — the natural way to declare a statically-sized frame buffer, `[@asyncFrameSize(co)]u8` — is rejected with `error[3050] array size is not a constant expression` because `evalConstU32Full` (`sf/src/type_resolver.zig`) has no builtin arm for `@asyncFrameSize`. Until it is fixed, frame buffers are sized by a runtime arena/sand allocation (`arena_mod.alloc(&arena, @intCast(usize, @asyncFrameSize(co)))`), the `examples/z98/mud_server` / `repro/mi_matrix/client_task_arena_xmod` idiom. Plan B's `stdlib_test/file_stream_usage` uses that idiom; the const-evaluator gap is a `sf/src` change (moves the fixed point) to be scheduled with the FramePool work.

---

## File Structure

**Create (modules):**
- `sf/src/std_crypto.zig` — L5, streaming hashes (no allocation; caller-provided state).
- `sf/src/std_parse.zig` — L5, number parse/format.
- `sf/src/std_map.zig` — L4, three concrete hash maps (no generics).
- `sf/src/std_sort.zig` — L4, introsort + vtable + binary search.
- `sf/src/std_heap.zig` — L4, binary min-heap over `(i64, *void)`.
- `sf/src/std_rle.zig` — L4, run-length encode/decode.
- `sf/src/std_base64.zig` — L5, base64.
- `sf/src/std_hex.zig` — L5, hex.
- `sf/src/std_utf8.zig` — L5, UTF-8 code point iteration.

**Modify (modules):**
- `sf/src/std.zig` — add re-exports only if the blueprint §6 distribution requires them (L4/L5 are by-path imports; confirm against §6).

**Create (fixtures):** one dir per public function under `repro/mi_matrix/`:
- `stdlib_crypto_<name>_xmod/` (KATs + streaming-vs-one-shot + empty).
- `stdlib_parse_<name>_xmod/` (valid/invalid tables; round-trip; overflow boundaries).
- `stdlib_map_<name>_xmod/` (collision stress; string key lifetime; iteration-order determinism).
- `stdlib_sort_<name>_xmod/` (random, sorted, reverse-sorted, duplicates; search on each).
- `stdlib_heap_<name>_xmod/` (push/pop ordering; tie stability; empty pop).
- `stdlib_rle_<name>_xmod/` (random/constant/alternating/empty).
- `stdlib_base64_<name>_xmod/`, `stdlib_hex_<name>_xmod/` (RFC 4648 vectors; whitespace rejection; round-trips).
- `stdlib_utf8_<name>_xmod/` (valid multi-byte; invalid continuation; overlong rejection).

**Create (usage programs, R7b):**
- `stdlib_test/map_sort_heap_usage/main.zig` — composes `std_map` + `std_sort` + `std_heap`.
- `stdlib_test/crypto_codec_usage/main.zig` — composes `std_crypto` + `std_base64`/`std_hex` + `std_utf8` + `std_buf`.

**Create (the found-ICE pin — Task 1b-I):**
- `repro/mi_matrix/field_store_continue_xmod/` — the compound field-store as a `while` continue expression (ICE before Task 1b-F).

**Modify (Task 1b-F):** `sf/src/lower.zig` (the field-store / continue-expression lowering) — the fix (the fixed point MOVES; the seed rotates).

**Modify (closeout):**
- `repro/mi_matrix/EXPECTED_FAIL.md` — bump once at Plan C closeout.
- `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` — the `lib/` copy list is extended per-task (one module per task commit); the closeout verifies it is complete.

**Reference (read-only):** `sf/docs/std_lib_extension.txt` §3 (L4/L5), `docs/sf/QUICK_REF.md`.

---

### Task 1: Baseline + `std_crypto` (L5)

**Files:**
- Create: `sf/src/std_crypto.zig`
- Create: the `stdlib_crypto_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_crypto.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: nothing (L0-L2 only; no allocation).
- Produces: `Sha1`, `Sha256`, `Md5` + `*Init`/`*Update`/`*Final` + `crc32Init`/`crc32Update`/`crc32Final` — blueprint §3 L5.

- [ ] **Step 1: Record the baseline** (HEAD; fixed point via a fresh seed build; seed md5; EXPECTED_FAIL header).
- [ ] **Step 2: Write the failing fixtures** (RFC/FIPS KATs; streaming vs one-shot equality; empty input).
- [ ] **Step 3: RED** (`error[3048]`).
- [ ] **Step 4: Implement `std_crypto.zig`.** No allocation; caller-provided state; `Update` callable any number of times with any chunk sizes.
- [ ] **Step 5: GREEN** — the KAT vectors must match byte-for-byte.
- [ ] **Step 6: Safety/determinism gates.**
- [ ] **Step 7: Fixed point UNMOVED + commit** (stage `sf/src/std_crypto.zig`, the fixtures, and both seed scripts).

---

### Task 1b-I: Pin the field-store-as-continue-expression ICE (I)

**Files:**
- Create: `repro/mi_matrix/field_store_continue_xmod/`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Interfaces:**
- Consumes: the corpus classifier.
- Produces: a RED pin for the found compiler ICE.

**Context (operator ruling m1670):** Plan C Task 1 found a pre-existing compiler ICE — a compound assignment to a struct field used as a `while` continue expression lowers to `error[3043]: internal: unsupported field-store base`. Minimal repro: `while (s.buf_len < 56) : (s.buf_len += 1) { ... }`. A workaround exists (move the increment into the loop body / use a local counter); `std_crypto.zig` uses it. The operator ruled: pin + fix as a separate I/F pair.

- [ ] **Step 1: Add the RED pin** — `repro/mi_matrix/field_store_continue_xmod/main.zig` with the continue-expr shape; the current compiler ICEs (`error[3043]`, 0 `.c`), so it classifies ICE (RED).
- [ ] **Step 2: Declare it** in `EXPECTED_FAIL.md` (the ICE, the trigger, the workaround); bump the header once.
- [ ] **Step 3: Commit** (`test(repro): pin the field-store continue-expression ICE (Plan C Task 1b-I)`). No `sf/src` change.

---

### Task 1b-F: Fix the field-store-as-continue-expression ICE (F)

**Files:**
- Modify: `sf/src/lower.zig` (the field-store / continue-expression lowering); the Task 1b-I fixture.
- Modify: `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md` (the seed rotation).

**Interfaces:**
- Consumes: the Task 1b-I RED pin.
- Produces: the fix; the fixed point MOVES; the seed rotates.

- [ ] **Step 1: Fix the lowering** so a compound field-store used as a `while` continue expression lowers correctly (the same field-store base handling the body form uses).
- [ ] **Step 2: Flip the pin RED -> GREEN**; run the full corpus + gates.
- [ ] **Step 3: Re-verify** (`check_emit_support.sh` 7/7; the self-compile; the corpus class map; `CLOSEOUT OK`); confirm the fixed point MOVED.
- [ ] **Step 4: Rotate the seed** and commit (`fix(lower): field-store base in a while continue expression (Plan C Task 1b-F)`).

---

### Task 2: `std_parse` (L5)

**Files:**
- Create: `sf/src/std_parse.zig`
- Create: the `stdlib_parse_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_parse.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: nothing.
- Produces: `parseInt`/`parseUint`/`parseInt64`/`parseUint64`/`parseFloat` + `itoa`/`utoa`/`itoa64`/`utoa64`/`ftoa` — blueprint §3 L5.

- [ ] **Step 1: Write the failing fixtures** (valid/invalid tables; round-trip; overflow boundaries).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_parse.zig`.** Parsing rejects whitespace/`+`/underscores; `null` on overflow or malformed; `itoa`/`utoa`/`ftoa` write backwards from `buf`'s end (returned slice points into `buf`).
- [ ] **Step 4: GREEN + safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_parse.zig`, the fixtures, and both seed scripts).

---

### Task 2b-I: Pin the 64-bit-literal + f64-literal limitations (I)

**Files:**
- Create: `repro/mi_matrix/lit64_decimal_xmod/`, `repro/mi_matrix/f64_literal_precision_xmod/`.
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`.

**Context (operator ruling m1703):** Plan C Task 2 found two pre-existing compiler limitations: (a) a 64-bit decimal literal materializes in a 32-bit temp and truncates (`9223372036854775808` -> 0); (b) an f64 literal emits at ~6 significant digits (`1.7976931348623157e308` -> `1.79769`). `std_parse` works around both. The operator ruled: pin + fix each as a separate I/F pair.

- [ ] **Step 1: Add the RED pins** — `lit64_decimal_xmod` (a `u64`/`i64` decimal literal beyond 32 bits) and `f64_literal_precision_xmod` (an f64 literal whose value needs >6 sig digits). The current compiler mis-lowers them, so the fixtures' asserts trap (RED).
- [ ] **Step 2: Declare both** in `EXPECTED_FAIL.md`; bump the header once.
- [ ] **Step 3: Commit** (`test(repro): pin the 64-bit/f64 literal limitations (Plan C Task 2b-I)`). No `sf/src` change.

---

### Task 2b-F: Fix the 64-bit-literal + f64-literal limitations (F)

**Files:**
- Modify: `sf/src/` (the literal materialization / emission); the Task 2b-I fixtures; the seed.
- Modify: `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md`.

- [ ] **Step 1: Fix the 64-bit decimal literal materialization** (no truncation to a 32-bit temp).
- [ ] **Step 2: Fix the f64 literal precision** (emit enough significant digits).
- [ ] **Step 3: Flip both pins RED -> GREEN**; run the full corpus + gates.
- [ ] **Step 4: Re-verify** (`check_emit_support.sh` 7/7; the self-compile; the corpus class map; `CLOSEOUT OK`); confirm the fixed point MOVED.
- [ ] **Step 5: Rotate the seed** and commit (`fix(emit): 64-bit decimal + f64 literal precision (Plan C Task 2b-F)`).

---

### Task 3: `std_map` (L4)

**Files:**
- Create: `sf/src/std_map.zig`
- Create: the `stdlib_map_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_map.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_arena`, `std_str`, `std_mem`.
- Produces: `Map32x32`, `Map32Ptr`, `MapStrPtr` + their `*Init`/`*Get`/`*Put`/`*Remove`/`*Len` — blueprint §3 L4.

- [ ] **Step 1: Write the failing fixtures** (collision stress; string-key lifetime; iteration-order determinism).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_map.zig`.** Open addressing, linear probing; string keys copied into the arena at put; deterministic iteration order (insertion index order); `put` on an existing key replaces.
- [ ] **Step 4: GREEN.**
- [ ] **Step 5: Arena gate** (exhaustion → `OutOfMemory`; no writes outside the arena).
- [ ] **Step 6: Safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_map.zig`, the fixtures, and both seed scripts).

---

### Task 3b-I: Pin the discarded fallible-struct-call catch defect (I)

**Files:**
- Create: `repro/mi_matrix/catch_discard_struct_xmod/`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Context (operator ruling m1735):** Plan C Task 3 found a pre-existing compiler defect — `_ = <fallible struct-returning call> catch |e| { ... }` mis-emits C (`incompatible types ... from type 'int'`). `std_map` works around it with a bound-variable helper.

- [ ] **Step 1: Add the RED pin** (the `_ = <fallible struct-returning call> catch |e| { ... }` shape).
- [ ] **Step 2: Declare it** in `EXPECTED_FAIL.md`; bump the header once.
- [ ] **Step 3: Commit** (`test(repro): pin the discarded fallible-struct-call catch defect (Plan C Task 3b-I)`). No `sf/src` change.

---

### Task 3b-F: Fix the discarded fallible-struct-call catch defect (F)

**Files:**
- Modify: `sf/src/` (the catch/discard lowering); the Task 3b-I fixture; the seed.

- [ ] **Step 1: Fix** the `_ = <fallible struct-returning call> catch |e| { ... }` emission.
- [ ] **Step 2: Flip the pin RED -> GREEN**; run the full corpus + gates.
- [ ] **Step 3: Re-verify** (`check_emit_support.sh` 7/7; the self-compile; the corpus class map; `CLOSEOUT OK`); confirm the fixed point MOVED.
- [ ] **Step 4: Rotate the seed** and commit (`fix(lower): discarded fallible struct-returning catch (Plan C Task 3b-F)`).

---


### Task 4: `std_sort` (L4)

**Files:**
- Create: `sf/src/std_sort.zig`
- Create: the `stdlib_sort_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_sort.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_str`.
- Produces: `Sortable` + `sort`/`sortI32`/`sortU32`/`sortStr`/`binarySearchU32` — blueprint §3 L4.

- [ ] **Step 1: Write the failing fixtures** (random, sorted, reverse-sorted, duplicates; search on each).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_sort.zig`.** Introsort; not stable (documented); `binarySearchU32` requires sorted input.
- [ ] **Step 4: GREEN + safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_sort.zig`, the fixtures, and both seed scripts).

---

### Task 4b-I: Pin + investigate the array-of-struct-literal defect (I)

**Files:**
- Create: `repro/mi_matrix/array_of_struct_literal_xmod/`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Context (operator ruling m1787):** Plan C Task 4 found a pre-existing compiler defect — an array literal of a user struct type is typed `void`. The inferred-length form (`[_]Pair{ .a = 1, .b = 2, ... }`) is rejected with `error[3000]` (rc 2, 0 `.c`); the annotated form (`var a: [2]Pair = [_]Pair{ ... };`) only warns but emits C that fails gcc (`'zT_2' undeclared`). `std_sort`'s vtable fixture works around it with `[N]Pair = undefined` + per-element assignment.

- [ ] **Step 1: Add the RED pin** (both shapes: the inferred-length literal and the annotated literal).
- [ ] **Step 2: Investigate related shapes** (the I-task questionnaire). Determine the exact locus and the full class a fix must cover: element types (plain struct, tagged union, optional, nested array, slice-of-struct, struct-containing-array), literal forms (`[_]T{...}` vs `[N]T{...}`), and positions (local, global, struct field, call argument). Report which shapes share the defect and which are already correct, with the locus in `sf/src`.
- [ ] **Step 3: Declare it** in `EXPECTED_FAIL.md`; bump the header once.
- [ ] **Step 4: Commit** (`test(repro): pin the array-of-struct-literal defect (Plan C Task 4b-I)`). No `sf/src` change.

---

### Task 4b-F: Fix the array-of-struct-literal defect (F)

**Files:**
- Modify: `sf/src/` (the array-literal typing/lowering); the Task 4b-I fixture; the seed.

- [ ] **Step 1: Fix** the array-of-struct-literal typing/emission for the shapes the Task 4b-I investigation confirms.
- [ ] **Step 2: Flip the pin RED -> GREEN**; run the full corpus + gates.
- [ ] **Step 3: Re-verify** (`check_emit_support.sh` 7/7; the self-compile; the corpus class map; `CLOSEOUT OK`); confirm the fixed point MOVED.
- [ ] **Step 4: Rotate the seed** and commit (`fix(lower): array-of-struct literal typing (Plan C Task 4b-F)`).

---

### Task 5: `std_heap` (L4)

**Files:**
- Create: `sf/src/std_heap.zig`
- Create: the `stdlib_heap_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_heap.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_arena`.
- Produces: `HeapItem`, `Heap` + `heapInit`/`heapPush`/`heapPop`/`heapPeek`/`heapLen` — blueprint §3 L4.

- [ ] **Step 1: Write the failing fixtures** (push/pop ordering; tie stability; empty pop).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_heap.zig`.** Min-heap on `key`; ties broken by insertion order (stable).
- [ ] **Step 4: GREEN + arena gate + safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_heap.zig`, the fixtures, and both seed scripts).

---

### Task 6: `std_rle` (L4)

**Files:**
- Create: `sf/src/std_rle.zig`
- Create: the `stdlib_rle_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_rle.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_arena`.
- Produces: `encode`/`decode`/`encodedLen`/`decodedLen` — blueprint §3 L4.

- [ ] **Step 1: Write the failing fixtures** (round-trip on random bytes; constant bytes; alternating bytes; empty input).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_rle.zig`.** Byte-oriented QOI-style variant (single byte vs run-of-N + value); format-specific headers are the caller's concern.
- [ ] **Step 4: GREEN + safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_rle.zig`, the fixtures, and both seed scripts).

---

### Task 7: `std_base64` + `std_hex` (L5)

**Files:**
- Create: `sf/src/std_base64.zig`, `sf/src/std_hex.zig`
- Create: the `stdlib_base64_*_xmod`, `stdlib_hex_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_base64.zig` + `std_hex.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_arena`.
- Produces: base64 `encode`/`decode`/`encodedLen`/`decodedLen`; hex `encodeLower`/`encodeUpper`/`decode` — blueprint §3 L5.

- [ ] **Step 1: Write the failing fixtures** (RFC 4648 vectors; whitespace rejection; round-trips).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement both modules.** Allocate output only.
- [ ] **Step 4: GREEN + safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_base64.zig`, `sf/src/std_hex.zig`, the fixtures, and both seed scripts).

---

### Task 7b-F: Give the base64/hex decoders an invalid-input error channel (F)

**Files:**
- Modify: `sf/src/std_base64.zig`, `sf/src/std_hex.zig` (the `decode` error sets); the `stdlib_base64_*`/`stdlib_hex_*` fixtures.

**Context (operator ruling m1842):** Task 7's review found that both decoders signalled invalid/whitespace input by returning a length-0 slice, colliding with a valid empty result — forced by the blueprint's `error{OutOfMemory}`-only set. The operator ruled: extend the API with an error channel.

- [ ] **Step 1: Add `error.InvalidInput`** to the `decode` error sets (both modules) and return it for malformed/whitespace input; keep a length-0 slice (no error) for a valid empty input.
- [ ] **Step 2: Amend the fixtures** so invalid input is pinned as `error.InvalidInput` and empty input as a valid empty slice; keep the RFC 4648 vectors GREEN.
- [ ] **Step 3: GREEN + safety/determinism gates + fixed point UNMOVED + commit** (`fix(std): base64/hex decode invalid-input error channel (Plan C Task 7b-F)`). Std-only: the fixed point stays UNMOVED; no seed rotation.

---

### Task 8: `std_utf8` (L5)

**Files:**
- Create: `sf/src/std_utf8.zig`
- Create: the `stdlib_utf8_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_utf8.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: nothing.
- Produces: `codepointLen`/`decode`/`encode`/`countCodepoints` — blueprint §3 L5.

- [ ] **Step 1: Write the failing fixtures** (valid multi-byte sequences; invalid continuation; overlong rejection).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_utf8.zig`.** No encoding tables for other codepages.
- [ ] **Step 4: GREEN + safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_utf8.zig`, the fixtures, and both seed scripts).

---

### Task 9: Plan C closeout + program completion

**Files:**
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (verify the `lib/` copy list is complete), `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `release/seed/CHANGELOG.md`
- Create: `stdlib_test/map_sort_heap_usage/main.zig`, `stdlib_test/crypto_codec_usage/main.zig` (R7b usage programs)

- [ ] **Step 1: Verify the seed scripts' `lib/` copy list is complete** — Tasks 1-8 each appended their module in the same commit; confirm `std_crypto.zig`/`std_parse.zig`/`std_map.zig`/`std_sort.zig`/`std_heap.zig`/`std_rle.zig`/`std_base64.zig`/`std_hex.zig`/`std_utf8.zig` are present in both scripts. Add any missing entry here.
- [ ] **Step 2: Create the Plan C usage programs (R7b)** — `stdlib_test/map_sort_heap_usage/main.zig` composes `std_map` + `std_sort` + `std_heap`; `stdlib_test/crypto_codec_usage/main.zig` composes `std_crypto` + `std_base64`/`std_hex` + `std_utf8` + `std_buf`. Each has a deterministic stdout contract and is compiled/run under the fixture gates (3× emission md5, `-fsafe`/`-ffast` parity). Confirm `scripts/corpus/list_corpus_dirs.sh | grep stdlib_test` enumerates both.
- [ ] **Step 3: Run the full corpus + gates** (count; `check_emit_support` 7/7; `CLOSEOUT OK`; zero class movement on pre-existing dirs).
- [ ] **Step 4: Bump `EXPECTED_FAIL.md`** once (header + a Plan C section).
- [ ] **Step 5: Update the QUICK_REF std-module inventory** (Ruling F2: drop the `MANIFEST.txt` part — no such file exists; the QUICK_REF inventory is canonical).
- [ ] **Step 6: Rotate the seed** if the distribution changed (the `lib/` payload grows even though the fixed point does not move):

```bash
cd /workspace/znineeight
bash scripts/seed/archive_seed.sh /tmp/planC_build/zig1_5_clean /tmp/planC_build/gen release/seed/zig1-seed.tgz --update-changelog
```

- [ ] **Step 7: Record the program-completion pointer.**

```markdown
## Next plan
Plan C complete. The std-lib extension program is COMPLETE.
No successor plan. Program spec: `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md`.
```

- [ ] **Step 8: Commit** (`chore(std-lib): Plan C closeout — L4 + L5 landed; program complete`).

---

## Next plan

Plan C complete. The std-lib extension program is COMPLETE.
No successor plan. Program spec: `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md`.

---

## Self-Review

- **Spec coverage:** spec §4 Plan C (all nine modules) → Tasks 1-8; §5 R1/R3/R6 → the constraints; §5 R7b → Task 9 Step 2; §6 crypto gate → Task 1 Step 5; §7 distribution → Task 9 Steps 1/5/6; §10 index → the `Sequence:` line + Task 9 Step 7; the Task 1b I/F pair (the found field-store ICE) → Tasks 1b-I/1b-F.
- **Fixed point:** Tasks 1-9 (std modules + fixtures) leave it UNMOVED; Tasks 1b-F, 2b-F, 3b-F, and 4b-F (the authorized `sf/src` fixes) MOVE it and rotate the seed. (The FramePool / `@asyncFrameSize` const-evaluator work, if scheduled, is a separate authorized task.)
- **Placeholder scan:** module signatures are referenced to the blueprint (§3 L4/L5) as the exact-signature source of record. Every step has a concrete command/expected output.
- **Type consistency:** module names and re-export names are used identically across tasks and the file structure; the `Map32x32`/`Map32Ptr`/`MapStrPtr` and `Sha1`/`Sha256`/`Md5` names match the blueprint.
