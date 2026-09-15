# mud_server — coroutine-conversion demo session

`session.sh` starts the server on port 4000, drives `canonical_feed.txt`
(`look`, `north`, `quit`) from one client over `bash /dev/tcp`, captures the
server stdout to `canonical_expected.txt`, kills the server by PID, and verifies
the port is clear. The expected file is the PRE-coroutine-conversion capture
(Track 4 Task 1).

Pre-conversion golden md5 (reference compiler `b844bfb5bedc453c2b385d37af558363`,
seed v19 `23a16154e83736cf6b636685396a124a`; 3× deterministic):

- `canonical_expected.txt` — `66c8f0abb926cca7baf9a0d1692ab318` (75 bytes)

Note: `session.sh` captures the server's **stdout** only. The `look`/`north`/
`quit` responses are written to the client socket (`std_net.send`,
`main.zig:175`), not to stdout, so the golden is the three server lifecycle
lines (`MUD server listening on port 4000`, `New client connected`,
`Client disconnected`). The response bytes were confirmed present on the
client socket out-of-band; they are not part of this committed golden.
