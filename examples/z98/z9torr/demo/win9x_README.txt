z9torr - manual Windows 9x (Win98) run procedure
================================================

Milestone: M5 (Win9x cross-compat). This is the T5 procedure: a MANUAL run on a
real Windows 9x machine. It is not automated and does not gate anything.

  * T4 - automated Wine smoke:
      examples/z98/z9torr/tests/tier4_wine.sh
    Emits the Windows tree with -osw, cross-builds with mingw, and runs
    z9torr_run.exe under 32-bit Wine against the host mock_tracker/mock_peer.
    Asserts exit 0 + the golden output SHA-1 (recorded as PARITY=OK).
  * T5 - THIS DOCUMENT: copy the artifacts to a real Win98 box and run there.
    The Win98 machine is outside the repository; there is no in-repo gate.

Every build here uses -fsafe (checked arithmetic). Since M5 S1/S2 the client,
the tiers and the mocks are all built -fsafe; -ffast is no longer used anywhere
in this example.

Binding seed: seed v96, /tmp/z9_m5_seed/zig1_5_clean
(closure 46e3e7af98af3b5ff2a960c7c96025e3).


1. Build z9torr.exe (on a Linux host, cross to win32)
-----------------------------------------------------

From the repository root:

    mkdir -p /tmp/z9torr_win
    timeout 120 /tmp/z9_m5_seed/zig1_5_clean -fsafe -osw -o /tmp/z9torr_win \
        examples/z98/z9torr/main.zig
    sh /tmp/z9torr_win/build_target.sh mingw /tmp/z9torr_win/z9torr.exe

The same build through the committed cross harness (dumps with -osw --dump-c89,
compiles every emitted .c with i686-w64-mingw32-gcc, links -lwsock32):

    bash scripts/win32_cross/cross_build_run.sh \
        /tmp/z9_m5_seed/zig1_5_clean \
        examples/z98/z9torr/main.zig \
        /tmp/z9torr_x /tmp/z9torr_x/z9torr.exe

Sanity: `file z9torr.exe` reports
  "PE32 executable (console) Intel 80386, for MS Windows".

The mingw link line always adds -lwsock32 (Winsock 1.1). The emitted
build_target.sh mingw branch sets LIBS="-lwsock32"; cross_build_run.sh does the
same.

-osw emit md5 (byte-identity over the Windows-target C89 dump):

    cd /workspace/znineeight
    timeout 120 /tmp/z9_m5_seed/zig1_5_clean -osw --dump-c89 \
        examples/z98/z9torr/main.zig | md5sum
    # 52ac7ecf85d11c79817c55288ec6636e  -

(stable 3x for the M5 source. The `-osw -o` tree carries the module .c/.h plus
build_target.sh, build_target.bat, build_owc.bat and net_prelude.h.)


2. What to copy to the Win98 machine
------------------------------------

  * z9torr.exe                         - the PE32 built above
  * testdata/t1_single_1m.torrent      - announce = http://127.0.0.1:6969/announce
  * EITHER the mock binaries built for win32 (2a),
    OR a Linux peer serving the same payload on the LAN (2b).

Put everything in one short directory, e.g. C:\z9.

2a. Mock binaries for Win98 (single machine, all on localhost)
    Build mock_tracker.exe and mock_peer.exe the same way (separate dirs so the
    emitted .c sets do not collide):

    mkdir -p /tmp/mocks/tr /tmp/mocks/pe
    timeout 120 /tmp/z9_m5_seed/zig1_5_clean -fsafe -osw -o /tmp/mocks/tr \
        examples/z98/z9torr/tools/mock_tracker.zig
    sh /tmp/mocks/tr/build_target.sh mingw /tmp/mocks/tr/mock_tracker.exe
    timeout 120 /tmp/z9_m5_seed/zig1_5_clean -fsafe -osw -o /tmp/mocks/pe \
        examples/z98/z9torr/tools/mock_peer.zig
    sh /tmp/mocks/pe/build_target.sh mingw /tmp/mocks/pe/mock_peer.exe

    Also copy the 1 MiB payload the peer serves (under a name distinct from the
    client's output `t1.bin`), generated with the same recipe the tiers use:

    awk 'BEGIN{srand(1);for(i=0;i<1048576;i++)printf "%c",int(rand()*256)}' \
        > /tmp/mocks/payload.bin
    sha1sum /tmp/mocks/payload.bin
    # 7a985d40cf76ef129b2889fa5bfce75304067dc9

2b. Linux peer on the LAN
    Run the native mocks on a Linux host as tier2 does. The committed
    t1_single_1m.torrent announces http://127.0.0.1:6969/announce, so that works
    only when the tracker, the peer and the client share a machine. To use a
    separate Linux peer, point the torrent's announce URL at the Linux host's IP
    and start mock_tracker there advertising that IP:port; the wire format is
    unchanged, only the address differs.


3. Run it on Win98
------------------

Open a Command Prompt (command.com) in C:\z9 and start the two mocks, then the
client (the client takes the torrent path as argv[1]):

    mock_tracker.exe --port 6969 --peers 127.0.0.1:6970
    (second window) mock_peer.exe --port 6970 --file payload.bin ^
        --piece-length 262144 --mode normal
    z9torr.exe t1_single_1m.torrent


4. Expected console output
--------------------------

t1_single_1m.torrent is 1 MiB. The metadata header is printed first:

    name: t1.bin
    length: 1048576
    piece length: 262144
    pieces: 4
    info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5

Then a 1 Hz progress line is rewritten in place with a carriage return (no
newline), so on a console you see a single line that updates:

    0.0% [----------------------------------------] 0.00MB/1.00MB 0KB/s peers=4 eta=--

(the bar fills with '#', the MB pair grows, KB/s is a 5-sample average and eta
counts down), then a newline and:

    z9torr: download complete
    summary: fetched=1048576 requests=64

The client exits 0 and `t1.bin` in the current directory SHA-1s to
7a985d40cf76ef129b2889fa5bfce75304067dc9.

Captured Win32 sample (the T4 Wine smoke; stdout redirected, so the CR bytes
show literally as ^M at the start of each refresh):

    name: t1.bin
    length: 1048576
    piece length: 262144
    pieces: 4
    info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
    ^M0.0% [----------------------------------------] 0.00MB/1.00MB 0KB/s peers=4 eta=--^M0.0% [----------------------------------------] 0.00MB/1.00MB 0KB/s peers=4 eta=--^M0.0% [----------------------------------------] 0.00MB/1.00MB 0KB/s peers=4 eta=--
    z9torr: download complete
    summary: fetched=1048576 requests=64

Carriage-return progress and redirection (the "GetFileType" fallback):
  - Attached to a Win9x console, stdout is a character device and `\r` returns
    the cursor to column 0, so each refresh overwrites the previous line in
    place (what you see in this section).
  - Redirected to a file (`z9torr.exe file.torrent > log.txt`), `\r` does NOT
    overwrite: each refresh is appended as bytes CR + text, so the log carries
    raw CR bytes (the ^M above) rather than a clean one-line-per-refresh file.
    The M5 blueprint (examples/ztorr_blp.txt) recommends detecting this with
    GetFileType(GetStdHandle(STD_OUTPUT_HANDLE)) and falling back to one line
    per refresh. The M5 example does NOT implement that probe: the runtime
    stdout path is WriteConsoleA and then WriteFile
    (sf/src/include/zig_pal.c:100). To see the in-place progress line, run the
    client attached to a real console, not redirected.

Runtime notes: sockets are Winsock 1.1 (wsock32). The non-blocking connect
checks WSAGetLastError and, after select() reports the socket writable, reads
getsockopt(SO_ERROR) - Win9x select can report writable before the connection
completes, so the SO_ERROR read is mandatory. On Win9x select()'s nfds argument
is 0. See spec section 12 risks 2 and 5.


5. Disk behaviour on FAT (no sparse files) - the T0 64-bit seek
---------------------------------------------------------------

At open, disk.zig `openTarget` pre-extends the output file to its full
`total_length` by seeking to the LAST byte and writing one zero
(examples/z98/z9torr/disk.zig:53-74). On a POSIX filesystem that hole is sparse
(no data blocks). FAT/FAT32 has NO sparse-file support: the filesystem fills
the gap with zeros up to the offset, so the pre-extend must allocate zero
clusters for the whole extent immediately. Consequences on Win9x:

  - Disk use tracks the high-water offset, not the bytes actually downloaded.
  - A payload near/over the FAT limit (FAT32: 4 GiB max file; FAT16: 2 GiB)
    fails to allocate even though the client's own seeks are 64-bit.
  - This is the Win9x face of the M5 Task 0 amendment: POSIX now uses 64-bit
    lseek/_llseek so payloads > 2 GiB work on the Linux host (spec section 12
    risk 7); the Windows equivalent is SetFilePointerEx (already i64). The FAT
    filesystem itself still caps the file and cannot represent the hole
    sparsely.
  - The end-of-file zero byte (seek to total_length-1, write 0) is what extends
    the file; later block writes seek to their 64-bit offset and write through.
    On NTFS that pre-extend is sparse; on FAT it is fully allocated.


6. Path handling: MAX_PATH and reserved names
---------------------------------------------

M1's `torrent.load` sanitizes `info.name` (examples/z98/z9torr/torrent.zig:129):
it rejects an empty name, any '/', any '\', and a ".." component. That is the
only up-front name validation.

MAX_PATH (260 bytes) and the Win9x reserved device names (CON, PRN, AUX, NUL,
COM1..COM9, LPT1..LPT9) are NOT checked by z9torr. `std_file.open` copies the
path into a 4096-byte stack buffer (sf/src/std_file.zig:45) and calls
CreateFileA, so an over-length path (> MAX_PATH) or a reserved name is handed to
Win9x, which fails the open; z9torr maps that to DiskError.OpenFailed and exits
5. Keep the torrent and payload in a short path such as C:\z9 and avoid
reserved names when picking an output name; the committed fixture name `t1.bin`
is safe.
