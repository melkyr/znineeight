# mud_server — coroutine-conversion demo session

`session.sh` starts the server on port 4000, drives `canonical_feed.txt`
(`look`, `north`, `quit`) from one client over `bash /dev/tcp`, captures BOTH the
server stdout (`canonical_expected.txt`) and the bytes the client receives
(`canonical_client_expected.txt`), kills the server by PID, and verifies the
port is clear. Both files are the PRE-coroutine-conversion captures (Track 4
Task 1) and are byte-identity targets for the converted program.

Pre-conversion golden md5s (reference compiler `b844bfb5bedc453c2b385d37af558363`,
seed v19 `23a16154e83736cf6b636685396a124a`; 3× deterministic):

- `canonical_expected.txt` — `66c8f0abb926cca7baf9a0d1692ab318` (75 bytes; server stdout: the three lifecycle lines)
- `canonical_client_expected.txt` — `3db75510fbf0a0e8192da5859eb71a1f` (149 bytes; client-received: welcome + `look` + `north` responses)

Note: the `quit` response is emitted by the reference compiler with length 1
(switch-expression string-literal prong emits `zT_5 = 1` in the C), so the
client receives only `G` of `Goodbye!\r\n`. This is a **pre-existing** emitter
defect (present before Task 0/0b; reproduced with a minimal `switch`-expression
fixture), not a conversion regression. The golden faithfully records the
baseline bytes. See the Task 1 report, Fix round 1.
