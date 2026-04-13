# Z98 MUD Server Example

A minimal telnet MUD (Multi-User Dungeon) server built using the Z98 bootstrap compiler's subset.

## Features

- Multiple concurrent clients using `select()`
- Basic room-based world
- Commands: `look`, `north`, `south`, `east`, `west`, `quit`
- Cross-platform networking via PAL (Win32 Winsock 1.1 and POSIX)

## Building

To compile the example using `zig0`:

```bash
./zig0 examples/mud_server/main.zig -o mud_server
```

Then compile the generated C code:

### Linux
```bash
gcc -m32 -std=c99 main.c zig_runtime.c -o mud_server
```

### Windows
```bash
cl /D_WIN32 main.c zig_runtime.c wsock32.lib /Fe:mud_server.exe
```

## Running

1. Start the server:
   ```bash
   ./mud_server
   ```
2. Connect using telnet:
   ```bash
   telnet localhost 4000
   ```

## Implementation Notes

- **Global Aggregate Arrays**: Uses an `initRooms()` function because global aggregate array initializers are not fully stabilized in the current bootstrap version.
- **Networking PAL**: Leverages the `plat_socket_*` abstraction layer for cross-platform compatibility.
- **Opaque `fd_set`**: Uses a 512-byte opaque buffer to represent `fd_set` safely across platforms.
