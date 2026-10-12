# Logfmt to Mnemoria Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate ~2035 entries (1604 active + 431 deleted) from flat logfmt files in `.opencode/memory/` to the mnemoria structured memory store, preserving timestamps, type, scope, and tags.

**Architecture:** Three phases: (1) validate pipeline with deletions first, (2) migrate active memories newest-first so the latest entries are immediately queryable, (3) document usage in AGENTS.md. Each logfmt file is processed by its own subagent that parses entries, generates summaries via LLM, and outputs importable JSON.

**Tech Stack:** mnemoria CLI, subagents (task with general agent), Python (for parsing + JSON generation in subagents), bash (orchestration)

## Global Constraints

- Store at `.opencode/memory/` — use no-name init so store lives at `--path/mnemoria/` subdirectory
- Active entries use agent name `legacy-zni`; deleted entries use `legacy-deleted`
- Preserve original timestamps (ISO 8601 → epoch ms)
- Import newest-first for active memories so latest entries are queryable immediately
- Type mapping: learning→discovery, decision→decision, plan→intent, blocker→problem, pattern→pattern, context→discovery, preference→discovery
- Do NOT delete logfmt files after migration (preserve originals in `.opencode/memory/`)

---

### Task 1: Clean slate + init mnemonia store

**Files:**
- Create: `.opencode/memory/` (already exists with logfmt files)
- Delete: `.opencode/memory/mnemoria` (exploration artifact, if exists)

- [ ] **Step 1: Remove old mnemonia subdirectory**

```bash
rm -rf /workspace/znineeight/.opencode/memory/mnemoria
```

- [ ] **Step 2: Init fresh mnemonia store**

```bash
mnemoria --path /workspace/znineeight/.opencode/memory init
```

Expected output: "Created memory at .../memory/mnemoria"

- [ ] **Step 3: Verify empty store**

```bash
mnemoria --path /workspace/znineeight/.opencode/memory stats
```

Expected: "Total entries: 0, File size: 0 bytes"

---



### Task 2: Phase 1 — Migrate deletions.logfmt (validation)

**Files:**
- Read: `.opencode/memory/deletions.logfmt` (431 entries)
- Create: `/tmp/migrate/deletions.json` (importable JSON output)

- [ ] **Step 1: Dispatch subagent for deletions.logfmt**

Dispatch a general subagent with this prompt:

```
Read the file /workspace/znineeight/.opencode/memory/deletions.logfmt.

Each line is in logfmt format with these fields:
ts=<ISO8601 timestamp> type=<type> scope=<scope> content="<text>" tags=<comma-sep>

Parse each line. For each entry:
1. Convert ts from ISO 8601 to epoch milliseconds (e.g. `date -d "2026-06-27T00:05:07.998Z" +%s%3N`)
2. Map type to mnemonia entry_type: learning→discovery, decision→decision, plan→intent, blocker→problem, pattern→pattern, context→discovery, preference→discovery
3. Prepend "[scope=<scope>]" to the content text
4. Append "\nTags: <tags>" to the content text if tags exist
5. Generate a concise 5-15 word summary from the content using your own understanding
6. Generate a UUID for each entry (use `uuidgen` in bash)

Output a single JSON array to /tmp/migrate/deletions.json in this exact format:
[
  {
    "id": "uuid-v4",
    "agent_name": "legacy-deleted",
    "entry_type": "discovery",
    "summary": "concise summary",
    "content": "[scope=project] original content here\nTags: tag1, tag2",
    "embedding": null,
    "timestamp": 1782575855105,
    "checksum": 0,
    "prev_checksum": 0
  }
]

IMPORTANT: Do NOT use `uuidgen` — it's not available. Instead, construct IDs like "del-001", "del-002" sequentially.
```

- [ ] **Step 2: Verify JSON output is valid**

```bash
python3 -c "import json; d=json.load(open('/tmp/migrate/deletions.json')); print(f'{len(d)} entries, first ts: {d[0][\"timestamp\"]}, last ts: {d[-1][\"timestamp\"]}')"
```

Expected: "431 entries" with valid timestamps

- [ ] **Step 3: Import into mnemonia**

```bash
mnemoria --path /workspace/znineeight/.opencode/memory import /tmp/migrate/deletions.json
```

Expected: "Imported 431 entries"

- [ ] **Step 4: Verify import**

```bash
mnemoria --path /workspace/znineeight/.opencode/memory stats
mnemoria --path /workspace/znineeight/.opencode/memory timeline --limit 5
mnemoria --path /workspace/znineeight/.opencode/memory search --agent legacy-deleted "keyword"
```

Expected: 431 entries visible, timeline shows correct chronological order

---

### Task 3: Phase 2 — Migrate active memories

**Files:**
- Read: `.opencode/memory/2026-*.logfmt` (52 files)
- Create: `/tmp/migrate/active-*.json` (per-file JSON output)

**Strategy:** Dispatch one subagent per logfmt file, processing newest first (2026-06-27 down to 2026-04-27). Each subagent does the same parsing+summary+JSON as Task 2 but with agent_name="legacy-zni".

Subagents can run in parallel batches of 5 at a time to avoid overload.

- [ ] **Step 1: List files in reverse chronological order**

```bash
ls -1 /workspace/znineeight/.opencode/memory/2026-*.logfmt | sort -r
```

- [ ] **Step 2: Dispatch subagents for first batch (5 newest files)**

Dispatch 5 parallel subagents, each with this prompt (adjust filename per subagent):

```
Read the file /workspace/znineeight/.opencode/memory/2026-06-27.logfmt.

Each line is in logfmt format with these fields:
ts=<ISO8601 timestamp> type=<type> scope=<scope> content="<text>" tags=<comma-sep>

Parse each line. For each entry:
1. Convert ts from ISO 8601 to epoch milliseconds
2. Map type to mnemonia entry_type: learning→discovery, decision→decision, plan→intent, blocker→problem, pattern→pattern, context→discovery, preference→discovery
3. Prepend "[scope=<scope>]" to the content text
4. Append "\nTags: <tags>" to the content text if tags exist
5. Generate a concise 5-15 word summary from the content using your own understanding
6. Use sequential IDs like "active-2026-06-27-001", "active-2026-06-27-002", etc.

Output a single JSON array to /tmp/migrate/active-2026-06-27.json in this exact format:
[
  {
    "id": "active-2026-06-27-001",
    "agent_name": "legacy-zni",
    "entry_type": "discovery",
    "summary": "concise summary",
    "content": "[scope=project] original content here\nTags: tag1, tag2",
    "embedding": null,
    "timestamp": 1782575855105,
    "checksum": 0,
    "prev_checksum": 0
  }
]

Return the path /tmp/migrate/active-2026-06-27.json when done.
```

- [ ] **Step 3: Import each completed batch**

After each batch of 5 subagents completes:

```bash
for f in /tmp/migrate/active-*.json; do
  mnemoria --path /workspace/znineeight/.opencode/memory import "$f"
done
```

Verify after each batch:

```bash
mnemoria --path /workspace/znineeight/.opencode/memory stats
```

- [ ] **Step 4: Repeat for remaining files**

Continue dispatching batches until all 52 files are processed.

---



### Task 4: Verification

- [ ] **Step 1: Verify total entry count**

```bash
mnemoria --path /workspace/znineeight/.opencode/memory stats
```

Expected: 2035 entries (431 deleted + 1604 active)

- [ ] **Step 2: Verify agent separation**

```bash
mnemoria --path /workspace/znineeight/.opencode/memory timeline --agent legacy-zni --limit 3
mnemoria --path /workspace/znineeight/.opencode/memory timeline --agent legacy-deleted --limit 3
```

Both should return entries with correct agent names.

- [ ] **Step 3: Verify chronological order**

```bash
mnemoria --path /workspace/znineeight/.opencode/memory timeline --limit 10
```

Expected: Most recent entries first (reverse chronological).

- [ ] **Step 4: Verify search works**

Known keywords present in the data: "P1.3", "semantic_analyzer", "resolveExpr", "M1/M2", "Convergence"

```bash
mnemoria --path /workspace/znineeight/.opencode/memory search --agent legacy-zni "resolveExpr"
mnemoria --path /workspace/znineeight/.opencode/memory ask --agent legacy-zni "What issues were found in the semantic analyzer?"
```

Both should return relevant results.

- [ ] **Step 5: Verify edge cases**

Check that the oldest entry exists:

```bash
mnemoria --path /workspace/znineeight/.opencode/memory timeline --since 2026-04-27 --until 2026-04-28
```

Confirm entries from the earliest logfmt file are present.

---

### Task 5: Update AGENTS.md

**Files:**
- Modify: `AGENTS.md` (add mnemoria usage section)

- [ ] **Step 1: Add memory conventions section**

Append to AGENTS.md:

```markdown
## Memory (Mnemoria)

Memories are stored using `mnemoria` CLI. The store lives at `.opencode/memory/`.

### Agent Conventions

| agent_name | Purpose |
|---|---|
| `legacy-zni` | Pre-migration memories from the old logfmt system |
| `legacy-deleted` | Previously deleted (forgotten) memories, retained for reference |

New memories should use descriptive agent names matching the subsystem (e.g. `semantic-analyzer`, `lower`, `parser`).

### Type Mapping

| memory type | mnemonia entry_type |
|---|---|
| learning | discovery |
| decision | decision |
| plan | intent |
| blocker | problem |
| pattern | pattern |
| context | discovery |
| preference | discovery |

### Usage

```bash
# Search legacy memories
mnemoria --path .opencode/memory search --agent legacy-zni "keyword"

# Ask a question about legacy memories (RAG)
mnemoria --path .opencode/memory ask "What patterns exist in the semantic analyzer?"

# View recent timeline
mnemoria --path .opencode/memory timeline --limit 10

# Add a new memory
mnemoria --path .opencode/memory add \
  --agent semantic-analyzer \
  --type discovery \
  --summary "Brief description" \
  "Detailed memory content here"

# Get stats
mnemoria --path .opencode/memory stats
```


