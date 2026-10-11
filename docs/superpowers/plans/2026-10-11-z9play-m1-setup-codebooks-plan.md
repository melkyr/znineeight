# z9play M1 — Setup header + codebooks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse the Vorbis **setup** header (`\x05vorbis`) — codebooks, time-domain transforms, floors, residues, mappings, modes — and construct the codebook decode structures, exposed via `z9play --dump-setup <file.ogg>`.

**Architecture:** Extend `vorbis_info.zig` with a `setup.zig` parser + a codebook builder. Pure byte/integer work: no floating point, no trig (that is M2), no PCM. The deliverable is a validated in-memory `Setup` that M3 consumes.

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `std_file`/`std_mem`/`std_arena`/`std_io.print`; fixtures + goldens from `vorbis-tools`.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m0-ogg-container-plan.md`. NEXT: `2026-10-11-z9play-m2-native-math-plan.md`.

## Global Constraints

Same as M0: example-only `examples/z98/z9play/**`; **no compiler change**; no seed rotation; Z98 rules (free functions, no generics, `@intCast`, every `switch` has `else`, D1/D2/D3/D4); build `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; the plan is the only authority (STOP-present on divergence). Reports under `.superpowers/sdd/2026-10-11-z9play-m1-setup-codebooks-plan/`.

## File Structure

- `examples/z98/z9play/vorbis_setup.zig` — setup-header parse + `Setup` struct.
- `examples/z98/z9play/codebook.zig` — codebook construction + Huffman decode.
- `examples/z98/z9play/tests/setup_test.zig` — unit harness.
- `examples/z98/z9play/tests/tier_setup.sh` — the M1 gate.

---

### Task 0: Next-milestone amendment review (M1's own precondition)

- [ ] Read this plan against M0's actual output (the `ogg.zig` packet API). Record assumptions confirmed or amend before starting. (This plan was reviewed by M0 Task 6; re-confirm.)

### Task 1: Setup header skeleton + codebook dimensions

**Files:** Create `vorbis_setup.zig`; test harness.
**Interfaces:** `pub const Setup = struct { ... }`; `pub fn parseSetup(arena, packet: []const u8) OggError!Setup` — consumes `\x05vorbis`, `codebook_count+1`, then per codebook the dimensions (sync pattern `0x564342` "BCV", dimensions, entries), ordered/unordered/sparse flags, lengths.
- [ ] Failing test: codebook count + first codebook's `dimensions`/`entries` for the fixtures. Implement. PASS. Commit `example(z9play): parse Vorbis setup header skeleton`.

### Task 2: Codebook Huffman decode tables

**Files:** `codebook.zig`.
**Interfaces:** `pub fn buildDecodeTable(arena, cb) !DecodeTable`; `pub fn decodeScalar(dt, bits: *BitReader) i32` and `pub fn decodeVector(...)`; lookup types 1 (tessellation) + 2 (sequence) + scalar.
- [ ] Failing test: build all fixture codebooks; assert canonical Huffman codes are decode-unique (round-trip encode→decode on synthetic bit patterns). Implement — **bit order (operator-approved amendment 2026-10-11): the byte-level bit reader is LSB-first (Vorbis `oggpack`), NOT MSB-first as originally written; the only "MSB-first" in Vorbis is the canonical-codeword index orientation (apply bit-reversal to the codeword index only, if a table-based decoder is used).** Also: grow `Codebook`/parser to retain lookup type / `value_bits` / `sequence_p` / `min` / `delta` / multiplicands (Task 1 discarded them; Task 2 `decodeVector` needs them); widen the lookup-type-2 tail multiplies (`entries*dims`, `value_bits*lv`) to u64 (a crafted ~80 KB header currently traps rc 133 under `-fsafe`); add a lookup-type-1 test vector. PASS. Commit `example(z9play): build codebook Huffman decode tables`.

### Task 3: Time-domain transforms, floors, residues, mappings, modes

**Files:** `vorbis_setup.zig`.
**Interfaces:** parse `time_count`, floors (0/1), `residue_count`, residues, `mapping_count`, mappings (channel coupling/`mux`), `mode_count` (+ framing). Store as concrete structs; no math.
- [ ] Failing test: for the fixtures assert floor types, residue types/partitions, mapping coupling steps, and mode count/blockflag. Implement. PASS. Commit `example(z9play): parse floors/residues/mappings/modes`.

### Task 4: `z9play --dump-setup` + gate

**Files:** `cli.zig`/`main.zig`; `tests/tier_setup.sh`; docs.
- [ ] Add `--dump-setup` printing a fixed summary (codebook count, floor/residue/mapping/mode counts). `tests/tier_setup.sh`: assert the summary against a golden captured from `ogginfo -v` (or a fixture-committed expected file). Run PASS. Commit `example(z9play): M1 --dump-setup + tier_setup`.

**Gate:** `tests/tier_setup.sh` green (setup parsed, codebooks built and decode-unique, counts match); `--dump-c89` md5 recorded.

### Task 5: Next-milestone amendment review (M2)

- [ ] Read `2026-10-11-z9play-m2-native-math-plan.md`. Judge whether M1's codebook/bit-reader output changes M2's assumptions (M2 is std-only math, so likely independent — but confirm the exact f64 functions M3 will need and that M2's list covers them: `sqrt`, `sin`, `cos`, and any residue/window helper). If the needed function set differs, **STOP-present** the M2 amendment. Else record "no amendment needed".

**Gate:** approved M2 amendment or justified "no amendment needed".
