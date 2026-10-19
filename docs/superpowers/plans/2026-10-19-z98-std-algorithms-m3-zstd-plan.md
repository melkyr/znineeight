# M3 Zstd: std_zstd Frame Decoder — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the zstd frame decoder (RFC 8878 subset) with caller-overridable window cap.

**Architecture:** `std_zstd.zig` L4 stateless single-shot decoder — frame parse → block dispatch (raw/RLE/compressed) → FSE/Huffman literal + sequence decode into caller `dst`. History = output buffer; no heap; Huffman/FSE tables function-local (~2–4 KB). No `ref/` crosscheck: host `zstd` CLI is the generation-time reference; committed vectors freeze the agreement.

**Tech Stack:** Z98 → C89; host `zstd` CLI (acquisition script pattern = `tests/get_flac_tools.sh`).

**Spec:** `docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md` (§5, §6.4)

## Global Constraints

M1 plan Global Constraints bind verbatim. Extra: decoder allocates nothing beyond caller `dst`; anything outside the §6.4 subset is `error.*`, never UB; window cap is a caller parameter (operator ruling).

## Review Focus

1. FSE/Huffman table construction — wrong normalized counts decode "almost right"; only byte-exact corpus catches it.
2. Window-override semantics — frame window_log > `max_window_log` must be `error.WindowTooBig` BEFORE decode, never a partial write.
3. Sequence overlap copies — match before/after literal edge cases corrupt silently without bounds discipline.
4. Skippable frames — skip per RFC MUST, payload never surfaced, never counted as corruption.
5. Single-shot history invariant — every back-reference must resolve within `dst[0..written]`; an early offset read is the classic zstd decoder CVE class.

---

### Task 1: `std_zstd` — frame + blocks + FSE/Huffman decode

**Files:**
- Create: `sf/src/std_zstd.zig`
- Create: `scripts/stdlib/vectors/std_zstd/*.{in,expected}` (binary; host `zstd`/`zstd -d` generated once, committed)
- Create: `scripts/stdlib/get_zstd_tools.sh` (no-root acquisition, M8 pattern)
- Create: `repro/mi_matrix/stdlib_zstd_{basic,cross}_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`, seed copy lists (`build_from_seed.sh:146`, `archive_seed.sh:115`)

**Interfaces:**
- Consumes: none beyond L0–L2.
- Produces: `std_zstd.{ZSTD_DEFAULT_WINDOW_LOG,zstdDecompress}` — §6.4 signature verbatim (`pub fn zstdDecompress(src: []const u8, dst: []u8, max_window_log: u8) !u32`; errors `Corrupt`/`OutputTooSmall`/`WindowTooBig`).

- [ ] **Step 1: Vector generation setup.** `get_zstd_tools.sh` acquires `zstd` CLI; generate corpus (text/binary/incompressible; window logs 10–21; block sizes 1/64 KB) with `zstd -1/-19`; `zstd -d` produces `.expected`; commit pairs. Verification: `.expected` byte-equals originals (the frozen agreement).
- [ ] **Step 2: Write failing fixtures.** `stdlib_zstd_basic_xmod`: round-trip decode all corpus vectors byte-exact; empty content; single raw/RLE block; `WindowTooBig` (frame with window_log 22 vs `max_window_log=21` — generated via `zstd --long=22` or crafted); custom `max_window_log=24` accepts it; truncations + bit-flips → `error.Corrupt`; dst-too-small → `error.OutputTooSmall`; skippable frame + valid frame = decodes, payload ignored.
- [ ] **Step 3: Run — FAIL (module absent).**
- [ ] **Step 4: Implement decoder** — frame magic `0xFD2FB528` + header (window descriptor, content-size optional, single-segment); block header parse; raw/RLE passthrough; compressed: FSE literals (predefined/raw/RLE/compressed modes) + FSE sequences (litlen/offset/matchlen modes) + repeat-sequences handling; sequence execution with overlap-safe copies; every back-reference inside `dst[0..written]`.
- [ ] **Step 5: Crosscheck pass green** — `stdlib_zstd_cross_xmod --crosscheck` decodes vectors (no ref binary; committed `.expected` is the authority — the three-way compare degrades to Z98 == `.expected`); determinism 3×.
- [ ] **Step 6: Gates + commit.** Full §4 RUN set; import-resolvability; stack discipline checked (no `>4 KB` function-local arrays beyond the documented tables). `feat(std_zstd): RFC 8878 subset decoder (M3)`.

### Task 2: M3 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/zstd.md`; Modify: `release/seed/CHANGELOG.md` (via archive script)

- [ ] **Step 1: Docs** — subset boundaries (no dictionaries), window-override usage (default 21; 256 MB box passes 24–28), offline-compress workflow, error contract.
- [ ] **Step 2: Rotate seed** — archive + manifest (36 files); binary md5 + fixed point unchanged.
- [ ] **Step 3: Full gate re-run + commits** (`docs(std_lib): zstd docs (M3)`, `chore(seed): rotate (M3)`).
