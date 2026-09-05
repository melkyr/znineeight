/* net_prelude.h — target-neutral net include prelude for std_net extern calls
   (S2 std_net extern rewrite). The include set mirrors the legacy socket-builtin
   net include block (c89_emit.zig emitBuiltinIncludes); whichever C toolchain
   compiles the dump (gcc -m32 / i686-w64-mingw32-gcc) selects the branch, so the
   only prototype source for every std_net extern is the matching OS header. */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock.h>
#pragma comment(lib, "wsock32.lib")
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/select.h>
#include <sys/time.h>
#include <unistd.h>
#include <netdb.h>
#endif

/* std_net extern-call aliases. std_net's public API owns the names
   accept/connect/send/recv/close/select, so those externs are declared with an
   _os Z98 identifier and mapped here to the real OS symbols. Declared AFTER the
   includes so they never rewrite the OS headers; only the emitted std_net call
   sites (compiled into the same TU) are affected. */
#define accept_os accept
#define connect_os connect
#define send_os send
#define recv_os recv
#define close_os close
#define select_os select
