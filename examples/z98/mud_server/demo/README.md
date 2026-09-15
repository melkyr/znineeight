# mud_server — coroutine-conversion demo session

`session.sh` starts the server on port 4000, drives `canonical_feed.txt`
(`look`, `north`, `quit`) from one client over `bash /dev/tcp`, captures BOTH the
server stdout (`canonical_expected.txt`) and the bytes the client receives
(`canonical_client_expected.txt`), kills the server by PID, and verifies the
port is clear. Both files are byte-identity targets for the converted program.

Golden md5s (re-captured at the Task-0d fixed point
`7297eb442d012f6e07b60617c4f8e4e8`, seed v19
`23a16154e83736cf6b636685396a124a`; 3× deterministic):

- `canonical_expected.txt` — `66c8f0abb926cca7baf9a0d1692ab318` (75 bytes; server stdout: the three lifecycle lines) — UNCHANGED by the Task-0d fix
- `canonical_client_expected.txt` — `93147d0f0bbd983a9d844fea8b7a6fa7` (158 bytes; client-received: welcome + `look` + `north` responses + full `Goodbye!\r\n`)

Task 0d (Track 4 S19 F) fixed the switch-expression string-literal-prong
slice-length defect: `applyCoercion` (`sf/src/lower.zig`) defaulted `sllen = 1`
when the `string_to_slice` coercion was keyed on the wrapper node; the switch/if
resolver now coerces each string-literal prong directly to the expected
`[]const u8`. The `quit` response now sends the full `Goodbye!\r\n` (10 bytes)
instead of the single `G`, so this golden grew 149 → 158 bytes. The server stdout
is byte-identical. See the Task-1 report (Fix round 1) and the Task-0d report.
