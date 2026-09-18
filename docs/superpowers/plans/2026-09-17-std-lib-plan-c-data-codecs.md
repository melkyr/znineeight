# Z98 std-lib Plan C — L4 data structures + L5 encoders/decoders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the L4 data-structure/algorithm modules (`std_map`, `std_sort`, `std_heap`, `std_rle`) and the L5 encoder/decoder modules (`std_crypto`, `std_parse`, `std_base64`, `std_hex`, `std_utf8`) with fixtures and the layering gate green.

**Architecture:** One plan, nine module tasks plus the band's R7b usage programs in the closeout, ordered by the blueprint's construction order (L5 crypto early — it is pure and vector-gated — then L4, then the remaining L5 codecs). Each module is authored in `sf/src/std_<name>.zig` with the blueprint's exact signatures, gets `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixtures, and is validated by the six gates. **This plan runs after Plan B; it is the last plan in the std-lib extension program.**

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.arena`, bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` §4 (Plan C), §5, §6; module signatures in `sf/docs/std_lib_extension.txt` §3 (L4, L5).

**Sequence:** PREVIOUS plan: [`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md) (L3 + L6). NEXT plan: none — final plan in the std-lib extension program.

## Global Constraints

- **Precondition:** Task 0 + Plan A + Plan B complete.
- **Baseline (re-verify at Task 1).** Record HEAD, the fixed point, the seed version/archive md5, the corpus `EXPECTED_FAIL.md` header. Adding std modules MUST NOT move the fixed point — if it does, STOP.
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
- [ ] **Step 3: Run the full corpus + gates** (count; `check_emit_support` 5/5; `CLOSEOUT OK`; zero class movement on pre-existing dirs).
- [ ] **Step 4: Bump `EXPECTED_FAIL.md`** once (header + a Plan C section).
- [ ] **Step 5: Update the QUICK_REF std-module inventory + `MANIFEST.txt`** (every module + md5).
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

## Self-Review

- **Spec coverage:** spec §4 Plan C (all nine modules) → Tasks 1-8; §5 R1/R3/R6 → the constraints; §5 R7b → Task 9 Step 2; §6 crypto gate → Task 1 Step 5; §7 distribution → Task 9 Steps 1/5/6; §10 index → the `Sequence:` line + Task 9 Step 7.
- **Placeholder scan:** module signatures are referenced to the blueprint (§3 L4/L5) as the exact-signature source of record. Every step has a concrete command/expected output.
- **Type consistency:** module names and re-export names are used identically across tasks and the file structure; the `Map32x32`/`Map32Ptr`/`MapStrPtr` and `Sha1`/`Sha256`/`Md5` names match the blueprint.
