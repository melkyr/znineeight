z9play — manual Windows 9x (Win98) procedure
============================================

This file is the manual procedure for the *real* Win9x path. The automated
M6 gate (tests/tier_win9x.sh) builds the .exe with mingw and runs it under
Wine, but it deliberately drives the hermetic WAV sink (Z9PLAY_WAV_OUT), not
a real waveOut device. The real waveOut output path is therefore manual-only:
run it on a Win98 machine with a working sound card.

Nothing here is required to build or test the Linux player.


1. Build the .exe (Linux cross host)
------------------------------------

Prerequisites on the Linux host: a 32-bit mingw cross toolchain
(i686-w64-mingw32-gcc), gcc -m32, and the repo's bootstrap seed
(release/seed/zig1-seed.tgz). Wine is only needed for the optional smoke run.

The compiler must be rebuilt from seed v101; it carries the Win9x no-CRT
runtime and default profile:

    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed
    # resulting compiler: /tmp/z9play_seed/zig1_5_clean
    # md5:        b299b4b435e624d0ddbd2edde681cbc3
    # two-hop closure: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3

Then emit the default `-osw` profile (9x, no-CRT) from the repo root and build
it through the emitted mingw recipe:

    mkdir -p /tmp/z9play_win9x_build
    /tmp/z9play_seed/zig1_5_clean -osw -o /tmp/z9play_win9x_build \
        examples/z98/z9play/main.zig
    sh /tmp/z9play_win9x_build/build_target.sh mingw \
        /tmp/z9play_win9x_build/z9play.exe

The emitted `build_target.sh` mingw branch is the Win9x DEFAULT no-CRT link:

    -DZIG_NO_CRT -nostdlib -Wl,-e,_mainCRTStartup ... -lkernel32 -lwinmm

It produces a single PE32 i386 console executable. The resulting image imports
only the Win9x OS DLLs KERNEL32.dll and WINMM.dll (waveOut) — there is no
msvcrt.dll import and therefore no CRT redistributable to install.

The same emit tree also carries the native-toolchain scripts for building on
Windows itself: `build_target_nocrt.bat` (MSVC 6) and `build_owc_nocrt.bat`
(OpenWatcom) are the 9x no-CRT defaults; `build_target_crt.bat` and
`build_owc_crt.bat` are static-CRT alternates (still a single EXE, still no DLL
bundling). The plain `build_target.bat` / `build_owc.bat` names are aliases for
the no-CRT defaults. The native scripts and the no-CRT link design are
design-verified; hardware verification is operator-pending after the z9play
milestone.

An explicit `-osw nt` build is the opt-in CRT/NT profile (`-DZIG_WIN_NT`, no
`-nostdlib`, modern XP+ file APIs). It is NOT the Win9x default.

Reproducibility check (optional): the seed-v101 default `-osw` C89 dump md5 is

    timeout 300 /tmp/z9play_seed/zig1_5_clean -osw --dump-c89 \
        examples/z98/z9play/main.zig | md5sum
    # ad9ccfd34aa2ba26c38abbcf48eedeb0  -

The automated tier records this value stable 2x and gates the emitted no-CRT
build, imports, WAV parity and console restore:

    ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_win9x.sh
    # == tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
    # TIER_WIN9X PASS

If a prebuilt z9play.exe from a matching commit is available, skip the build
and use it directly (verify it is built with the seed-v101 compiler).



2. What to copy to the Win98 box
--------------------------------

Copy exactly two files to a directory on the Win98 machine:

    z9play.exe      the PE32 console executable from step 1
    song.ogg        any Ogg Vorbis file (the committed test fixtures work)

Nothing else is required. The player is a single drag-and-drop EXE: it imports
only the Win9x OS DLLs KERNEL32.dll and WINMM.dll, with no msvcrt.dll and no
CRT redistributable, and no separate decoder or runtime DLL to bundle or
install. Ogg Vorbis is decoded entirely in Z98 inside z9play.exe.


3. Run it
---------

Open an MS-DOS Prompt / Command Prompt window on the Win98 box, change to the
directory containing the two files, and run:

    z9play.exe song.ogg

Useful options (same CLI as the Linux build):

    z9play.exe song.ogg --volume 80
    z9play.exe song.ogg --start 30
    z9play.exe song.ogg --loop
    z9play.exe song.ogg --quiet

Interactive keys (raw, no Enter needed):

    space     pause / resume
    +  or  =  volume up 5 (maximum 100)
    -         volume down 5 (minimum 0)
    q         quit
    Ctrl-C    quit (see section 5)
    Ctrl-Break terminates immediately via the Win9x default handler

The arrows, Enter and Esc are decoded by the Win9x console backend and exposed
by the shared Console contract, but the current CLI does not use them.

Startup prints the metadata line, for example:

    z9play: song.ogg  00:02  2ch 44100Hz

Unless --quiet is used, a fixed-width status line is then redrawn in place
once per second with a carriage return (the same format as Linux):

    00:00 / 00:02  vol  80%  [--------------------]

On a normal finish or quit the player prints the final position and exits:

    Stopped at 00:02.

Expected exit codes: 0 ok, 1 arguments, 2 open, 3 decoder, 4 audio,
5 internal.

To test without a sound card (or to capture what would play), set the WAV-sink
override before running. This selects the hermetic WAV writer on Windows too,
so no waveOut device is touched:

    set Z9PLAY_WAV_OUT=C:\z9play_test.wav
    z9play.exe song.ogg --volume 100

The resulting WAV is the same canonical 44-byte-header 16-bit PCM WAV shape as
the Linux --pcm/--wav output. Unset it (or open a new prompt) to use waveOut:

    set Z9PLAY_WAV_OUT=


4. Expected console behavior
----------------------------

The Win9x console backend does not emit ANSI escape sequences. It uses the
Win32 console API: WriteConsoleA for text, FillConsoleOutputCharacterA plus
SetConsoleCursorPosition for clear, SetConsoleCursorPosition for cursor
addressing, and GetConsoleScreenBufferInfo for width/height. The status line
redraw is a plain carriage return over a fixed-width line, so it works in the
Win98 console window.

In raw mode the console has line input, echo and processed input disabled, so
keys arrive immediately and are not echoed. The session remains a normal
console window; output is text (the backend writes with WriteConsoleA, so
non-ASCII metadata is subject to the console's code page).


5. Ctrl-C semantics (Amendment 1, Option 3)
-------------------------------------------

Z98 cannot define a stdcall function (compiler defect D5), so the backend does
NOT install a SetConsoleCtrlHandler callback. Instead enterRaw also clears
ENABLE_PROCESSED_INPUT: Ctrl-C is delivered to the input buffer as an ordinary
KEY_EVENT with character 0x03, which readKey maps to Key.sigint. The CLI treats
that exactly like `q`: it stops cleanly, prints `Stopped at mm:ss.`, restores
the console mode and exits 0. Ctrl-C is therefore a normal, clean quit.

Ctrl-Break is different: it still terminates the process through the Win9x
default handler, without the player's clean-quit path.


6. Raw-mode restore caveat
--------------------------

enterRaw saves the original console input mode; leaveRaw writes it back
byte-for-byte and is idempotent. Normal exits restore it explicitly:
`q`, Ctrl-C (Option 3), end of track (`Stopped at ...`), and the playback error
paths all call leaveRaw before exiting. An atexit handler is installed as a
crash/CRT-exit backstop on the first enterRaw.

Abnormal termination can still leave the console without echo/line input:
Ctrl-Break (default handler), closing the console window, a crash, or a machine
reset. Console-close/shutdown restore is moot because that console is gone.

Recovery: close the affected MS-DOS/console window and open a fresh one (Start
> Programs > MS-DOS Prompt). The input mode belongs to that console; a new
window starts with the default mode. `mode con` changes display geometry only
and is not an input-mode reset; there is no `stty sane` equivalent on Win98.


7. Known limitations
--------------------

- waveOut is best-effort and manual-only. The automated tier uses the WAV sink
  under Wine; it does not prove audio comes out of a real device. A Win9x
  machine with a working sound card is the only real-device test.
- Supported output formats are 16-bit PCM at 44100 or 48000 Hz, mono or
  stereo. Other rates/channel counts are rejected as unsupported and the
  player exits 4 with `z9play: cannot open the audio device`. A missing or
  unopenable device also exits 4.
- The backend queues two 500 ms buffers and blocks when both are in flight
  (waveOut writes are asynchronous). Drain waits for the queued audio; close
  resets and closes the device. Very slow machines may still underrun, which
  waveOut cannot fully prevent.
- Ctrl-Break is not a clean quit (see sections 5 and 6).
- Playback pacing and all decoding are the same as on Linux; the M6 changes
  are only the audio and console backends and the compile-time @isWindows()
  selection.


8. If it does not work
----------------------

- "cannot open the audio device" (exit 4): no sound card/driver, the device is
  busy, or the file's rate/channels are outside 44100/48000 and 1/2 channels.
- "cannot open the file" (exit 2): wrong path or the .ogg is not readable.
- Decoder errors (exit 3): the file is not a valid Ogg Vorbis stream.
- No keys respond: make sure stdin is the console (run from an interactive
  prompt, not with redirected input); a non-console handle makes raw mode a
  safe no-op and keys are not polled.
- Console left raw after a crash or Ctrl-Break: close the window and open a
  new MS-DOS Prompt (section 6).
