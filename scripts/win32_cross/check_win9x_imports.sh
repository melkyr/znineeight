#!/usr/bin/env bash
# check_win9x_imports.sh — closed-world PE import gate for the 9x/nt profiles.
#
# usage: check_win9x_imports.sh <exe> <9x|nt>
#
# Windows 9x resolves the complete import table at load time, so the mechanical
# per-DLL/per-import whitelist is the loadability gate (Wine is not a Win98
# loader). Unknown DLLs and unknown import names FAIL. On the 9x profile
# msvcrt.dll is a policy failure even though the DLL exists on 9x (the default
# profile is no-CRT).
set -u

EXE=${1:?usage: check_win9x_imports.sh <exe> <9x|nt>}
PROFILE=${2:?usage: check_win9x_imports.sh <exe> <9x|nt>}
case "$PROFILE" in 9x|nt) ;; *) echo "error: profile must be 9x or nt" >&2; exit 2;; esac

[ -f "$EXE" ] || { echo "error: '$EXE' not found" >&2; exit 2; }
command -v i686-w64-mingw32-objdump >/dev/null 2>&1 || { echo "error: objdump missing" >&2; exit 2; }

if ! file "$EXE" | grep -q 'PE32 executable.*Intel 80386'; then
    echo "FAIL: not a PE32 i386 executable: $EXE"
    file "$EXE"
    exit 1
fi

KERNEL32_9X="CloseHandle ContinueDebugEvent CreateFileA CreateProcessA DeleteCriticalSection DeleteFileA EnterCriticalSection ExitProcess FillConsoleOutputCharacterA FindClose FindFirstFileA FindNextFileA FlushFileBuffers FlushInstructionCache FreeLibrary GetCommandLineA GetConsoleCursorInfo GetConsoleMode GetConsoleScreenBufferInfo GetCurrentDirectoryA GetCurrentProcess GetEnvironmentVariableA GetFileAttributesA GetFileSize GetFileType GetLastError GetModuleFileNameA GetModuleHandleA GetNumberOfConsoleInputEvents GetProcAddress GetStartupInfoA GetStdHandle GetSystemTimeAsFileTime GetThreadContext GetTickCount InitializeCriticalSection LeaveCriticalSection LoadLibraryA MoveFileA QueryPerformanceCounter QueryPerformanceFrequency ReadConsoleInputA ReadFile ReadProcessMemory SetConsoleCursorInfo SetConsoleCursorPosition SetConsoleMode SetFilePointer SetLastError SetThreadContext SetUnhandledExceptionFilter Sleep TerminateProcess TlsGetValue VirtualProtect VirtualQuery WaitForDebugEvent WriteConsoleA WriteFile WriteProcessMemory"
KERNEL32_NT="$KERNEL32_9X GetFileAttributesExA GetFileSizeEx SetFilePointerEx"
WINMM_ALL="waveOutClose waveOutOpen waveOutPrepareHeader waveOutReset waveOutUnprepareHeader waveOutWrite"
WSOCK32_ALL="WSACleanup WSAGetLastError WSAStartup accept bind closesocket connect gethostbyname getsockopt htonl htons ioctlsocket listen recv recvfrom select send sendto setsockopt socket"
MSVCRT_ALL="__getmainargs __initenv __p__acmdln __p__commode __p__fmode __set_app_type __setusermatherr _amsg_exit _cexit _initterm _iob _onexit abort calloc exit fprintf free fwrite getchar getenv malloc memcpy putchar signal strlen strncmp vfprintf time"

in_list() {
    local name=$1 list=$2
    case " $list " in *" $name "*) return 0;; *) return 1;; esac
}

TMP=$(mktemp "${TMPDIR:-/tmp}/win9x_imports.XXXXXX") || exit 2
trap 'rm -f "$TMP"' EXIT

i686-w64-mingw32-objdump -p "$EXE" | awk '
    /DLL Name:/ { dll=toupper($3); print "DLL " dll; in_imports=1; next }
    in_imports && /^\t[0-9a-fA-F]+\t/ { print "IMP " dll " " $3; next }
    /^$/ { in_imports=0 }
' > "$TMP"

fail=0
any=0
cur=""
while read -r kind a b; do
    if [ "$kind" = "DLL" ]; then
        cur=$a
        any=1
        echo "DLL $cur"
        case "$cur" in
            KERNEL32.DLL|KERNEL32.dll) ;;
            WINMM.DLL) ;;
            WSOCK32.DLL) ;;
            MSVCRT.DLL)
                if [ "$PROFILE" = "9x" ]; then
                    echo "  FAIL msvcrt.dll is not allowed on the 9x no-CRT profile"
                    fail=1
                fi
                ;;
            *)
                echo "  FAIL unknown DLL"
                fail=1
                ;;
        esac
    elif [ "$kind" = "IMP" ]; then
        name=$b
        case "$cur" in
            KERNEL32.DLL)
                if [ "$PROFILE" = "9x" ]; then
                    in_list "$name" "$KERNEL32_9X" || { echo "  FAIL $name not in 9x KERNEL32 whitelist"; fail=1; }
                else
                    in_list "$name" "$KERNEL32_NT" || { echo "  FAIL $name not in nt KERNEL32 whitelist"; fail=1; }
                fi
                ;;
            WINMM.DLL)
                in_list "$name" "$WINMM_ALL" || { echo "  FAIL $name not in WINMM whitelist"; fail=1; }
                ;;
            WSOCK32.DLL)
                in_list "$name" "$WSOCK32_ALL" || { echo "  FAIL $name not in WSOCK32 whitelist"; fail=1; }
                ;;
            MSVCRT.DLL)
                if [ "$PROFILE" = "nt" ]; then
                    in_list "$name" "$MSVCRT_ALL" || { echo "  FAIL $name not in msvcrt whitelist"; fail=1; }
                fi
                ;;
        esac
    fi
done < "$TMP"

if [ "$any" -eq 0 ]; then
    echo "FAIL: no import table found"
    exit 1
fi
if [ "$fail" -ne 0 ]; then
    echo "IMPORT GATE FAILED ($PROFILE): $EXE"
    exit 1
fi
echo "IMPORT GATE PASS ($PROFILE): $EXE"
exit 0
