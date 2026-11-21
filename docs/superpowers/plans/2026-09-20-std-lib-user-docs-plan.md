# Z98 std-lib user documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write real user documentation for the Z98 standard library — a shared template, nine per-domain docs under `sf/docs/std_lib/`, and a curated `STD_README.MD` index — replacing the rejected signature-dump readme.

**Architecture:** One plan, twelve tasks, docs-only. Task 1 writes the shared `_template.md`. Tasks 2-10 write one domain doc each (overview + model + quick start + a structured entry per public function). Task 11 rewrites `STD_README.MD` as the curated index linking every domain doc. Task 12 is the whole-set review. No `sf/src`, script, fixture, or seed change; the fixed point and seed are untouched.

**Tech Stack:** Markdown, the Z98 std module sources in `sf/src/std_*.zig`, git.

**Spec:** `docs/superpowers/specs/2026-09-20-std-lib-user-docs-design.md`.

**Sequence:** PREVIOUS plan: none (a new documentation program). NEXT plan: none — final plan.

## Global Constraints

- **Docs only.** Do NOT edit `sf/src/**`, `scripts/**`, fixtures, `release/seed/**`, or any code. The compiler fixed point and seed are untouched.
- **Accuracy over volume.** Every documented type, function, and error member MUST match the module source in `sf/src/std_*.zig`. Read the source; never invent an API.
- **Per-function entry (binding order):** Purpose, When to use, Signature, Parameters, Returns, Errors, Example, Gotchas. Module-level: Overview, Quick start, API, See also.
- **Examples are illustrative**, reviewed by eye, not compiled. Use real signatures and idiomatic Z98 (no generics; `try`/`catch`; `?T` optionals; `[]u8` slices).
- **No blueprint references.** User docs must not cite `sf/docs/std_lib_extension.txt`; the blueprint is left unedited as an internal spec.
- **Uniform structure** across all domain docs, following `sf/docs/std_lib/_template.md`.
- **Edits only via `edit`/`fastedit`** (re-read the region immediately before each `fastedit`; edit bottom-to-top for multiple edits in one file). Never stage `mnemoria/` or `.zig1_*.tmp`.
- **STOP on a defect:** if a documented API contradicts the source (a real bug), STOP and report it — do not fix `sf/src`, do not document around it.

---

## File Structure

**Create (template):** `sf/docs/std_lib/_template.md`.

**Create (nine domain docs):**
- `sf/docs/std_lib/memory.md` — `std_arena`, `std_mem`.
- `sf/docs/std_lib/text.md` — `std_str`, `std_buf`.
- `sf/docs/std_lib/bits_math.md` — `std_bits`, `std_math`.
- `sf/docs/std_lib/os_time.md` — `std_os`, `std_time`, `std_debug`.
- `sf/docs/std_lib/io.md` — `std_io`, `std_file`, `std_stdin`.
- `sf/docs/std_lib/net.md` — `std_net`.
- `sf/docs/std_lib/async_stream.md` — `std_async`, `std_stream`.
- `sf/docs/std_lib/collections.md` — `std_map`, `std_sort`, `std_heap`, `std_rle`.
- `sf/docs/std_lib/codecs.md` — `std_base64`, `std_hex`, `std_utf8`, `std_crypto`, `std_parse`.

**Rewrite (index):** `STD_README.MD` (repo root).

**Verify (link):** `README.md` `## Standard Library` → `STD_README.MD`.

**Reference (read-only):** `sf/src/std_*.zig`, `sf/src/std.zig`, the design spec, `docs/sf/QUICK_REF.md`.

---

### Task 1: Shared template

**Files:**
- Create: `sf/docs/std_lib/_template.md`

**Interfaces:**
- Produces: the uniform structure every domain doc follows.

- [ ] **Step 1: Write `_template.md`** — a title/header block (layer(s), import paths), a **Module overview** section, a **Quick start** section, an **API** section showing the exact per-function entry skeleton (Purpose / When to use / Signature / Parameters / Returns / Errors / Example / Gotchas), and a **See also** section. Include one filled-in example entry so writers copy the shape.
- [ ] **Step 2: Confirm** the template matches spec §4 exactly.
- [ ] **Step 3: Commit** (`docs(std): add the std-lib doc template`).

---

### Task 2: `memory.md`

**Files:**
- Create: `sf/docs/std_lib/memory.md`

**Interfaces:**
- Consumes: Task 1's template.
- Produces: user docs for `std_arena` + `std_mem`.

- [ ] **Step 1: Read** `sf/src/std_arena.zig`, `sf/src/std_mem.zig` (every public type/function/error).
- [ ] **Step 2: Write** the doc per the template: the arena ownership model (R1), `init`/`alloc`/`reset`, the `ArenaError` (`OutOfMemory`) contract, and every `std_mem` function; a quick-start showing a caller-owned buffer + `arena.init` + `alloc`.
- [ ] **Step 3: Self-review** every signature/error against the source; commit (`docs(std): document std_arena + std_mem`).

---

### Task 3: `text.md`

**Files:**
- Create: `sf/docs/std_lib/text.md`

- [ ] **Step 1: Read** `sf/src/std_str.zig`, `sf/src/std_buf.zig`.
- [ ] **Step 2: Write** the doc: `std_str` slice operations (len/eql/copy/find/split/join/trim/replace/etc. — the real set), `std_buf` growable buffer + endian encoders, with the aliasing/lifetime gotchas and a quick start.
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document std_str + std_buf`).

---

### Task 4: `bits_math.md`

**Files:**
- Create: `sf/docs/std_lib/bits_math.md`

- [ ] **Step 1: Read** `sf/src/std_bits.zig`, `sf/src/std_math.zig`.
- [ ] **Step 2: Write** the doc: `std_bits` extract/insert/rotate + out-of-range trap semantics, `std_math` min/max/clamp/abs/align/isPowerOfTwo, with examples.
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document std_bits + std_math`).

---

### Task 5: `os_time.md`

**Files:**
- Create: `sf/docs/std_lib/os_time.md`

- [ ] **Step 1: Read** `sf/src/std_os.zig`, `sf/src/std_time.zig`, `sf/src/std_debug.zig` (and their `*_pal` units for the platform notes).
- [ ] **Step 2: Write** the doc: OS primitives + clocks + diagnostics (`log`/`logInt`/`assert`/`panic`/`backtrace`/`writeCoreDump`/the trap hook), the per-OS PAL notes, and the win32 caveats.
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document std_os + std_time + std_debug`).

---

### Task 6: `io.md`

**Files:**
- Create: `sf/docs/std_lib/io.md`

- [ ] **Step 1: Read** `sf/src/std_io.zig`, `sf/src/std_file.zig`, `sf/src/std_stdin.zig`.
- [ ] **Step 2: Write** the doc: console I/O, the file API (open/read/write/seek/close), stdin line reading, the `FileError` set, and the buffering gotcha (raw `std.io.print` vs buffered `std_io` output ordering).
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document std_io + std_file + std_stdin`).

---

### Task 7: `net.md`

**Files:**
- Create: `sf/docs/std_lib/net.md`

- [ ] **Step 1: Read** `sf/src/std_net.zig` (TCP + UDP + non-blocking + `fd_set`/`select` + byte-order helpers).
- [ ] **Step 2: Write** the doc: `init`/`cleanup`, TCP server/client, UDP, `setNonBlocking`/`recvNonBlocking`/`sendNonBlocking` (the `error.WouldBlock`/`0`-at-close contract), `NetError`, and a loopback quick start.
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document std_net`).

---

### Task 8: `async_stream.md`

**Files:**
- Create: `sf/docs/std_lib/async_stream.md`

- [ ] **Step 1: Read** `sf/src/std_async.zig`, `sf/src/std_stream.zig`.
- [ ] **Step 2: Write** the doc: the Model C cooperative-yield model, the scheduler (`tick`/`addTask`/`awaitTask`/`waitFor`/`waitAll`/`cancel`), `suspendUntil(pred)`, the frame/pool model, then `std_stream`'s `FileLineReader`/`SocketLineReader`/`MsgReader` (sync vs async, the u32-BE frame contract, `FrameTooLarge`, EOF), with a worked driver example.
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document std_async + std_stream`).

---

### Task 9: `collections.md`

**Files:**
- Create: `sf/docs/std_lib/collections.md`

- [ ] **Step 1: Read** `sf/src/std_map.zig`, `sf/src/std_sort.zig`, `sf/src/std_heap.zig`, `sf/src/std_rle.zig`.
- [ ] **Step 2: Write** the doc: the three maps (concrete key/value types, arena-backed), sort/search, the heap, and RLE; the capacity/OOM contract and the arena rule.
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document std_map + std_sort + std_heap + std_rle`).

---

### Task 10: `codecs.md`

**Files:**
- Create: `sf/docs/std_lib/codecs.md`

- [ ] **Step 1: Read** `sf/src/std_base64.zig`, `sf/src/std_hex.zig`, `sf/src/std_utf8.zig`, `sf/src/std_crypto.zig`, `sf/src/std_parse.zig`.
- [ ] **Step 2: Write** the doc: base64/hex encode/decode (the `InvalidInput` + empty-is-valid contract), UTF-8 validation/decoding, the streaming hashes (SHA-1/SHA-256/MD5 + CRC-32), and number parsing/formatting; worked round-trip examples.
- [ ] **Step 3: Self-review** against source; commit (`docs(std): document the codecs (base64/hex/utf8/crypto/parse)`).

---

### Task 11: Rewrite `STD_README.MD`

**Files:**
- Rewrite: `STD_README.MD`
- Verify: `README.md` link.

- [ ] **Step 1: Replace `STD_README.MD`** entirely with the curated index (spec §5): what std is/is not; the L0–L6 + R1–R7 model in plain terms; a "which module for which job" table; a short composed worked example; links to every `sf/docs/std_lib/*.md`. **Discard the old signature dump; no blueprint reference.**
- [ ] **Step 2: Verify** `README.md`'s `## Standard Library` section links to `STD_README.MD`.
- [ ] **Step 3: Commit** (`docs(std): rewrite STD_README.MD as the curated std-lib index`).

---

### Task 12: Whole-set review + closeout

**Files:**
- Review: all `sf/docs/std_lib/*.md` + `STD_README.MD`.

- [ ] **Step 1: Review the set** for template adherence, cross-doc consistency (shared rules stated once, not contradicted), working relative links, absence of blueprint references, and no code changes.
- [ ] **Step 2: Fix** any inconsistency found (docs only).
- [ ] **Step 3: Commit** (`docs(std): std-lib user docs closeout — whole-set review`).

---

## Self-Review

- **Spec coverage:** §2 architecture → Tasks 1-11; §3 grouping → Tasks 2-10; §4 per-function template → Task 1 + every doc task; §5 `STD_README.MD` → Task 11; §6 conventions → the Global Constraints; §7 plan index → the `Sequence:` line.
- **Placeholder scan:** every task names concrete files + the observable result; module lists are the real `sf/src/std_*.zig` set.
- **Type consistency:** the nine doc filenames and their module groupings match the design spec §3 exactly.
