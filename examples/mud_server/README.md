# Z98 MUD Server Example

This is a minimal telnet MUD (Multi-User Dungeon) server implemented in the Z98 subset of Zig. It demonstrates the use of the new Platform Abstraction Layer (PAL) socket API.

## Features

- Multiple simultaneous connections using `select()`.
- Basic room-based movement (north, south, east, west).
- Look command for room descriptions.
- Simple line-based command processing.

## Building

To compile the MUD server using the Z98 bootstrap compiler:

```bash
./zig0 build-exe examples/mud_server/main.zig -m32
```

The resulting executable will be named `main` (or `main.exe` on Windows).

## Running

1. Start the server:
   ```bash
   ./main
   ```
   The server will listen on port 4000.

2. Connect via telnet from one or more terminals:
   ```bash
   telnet localhost 4000
   ```

## Z98 Subset Notes

- **Manual Socket Init**: Unlike modern Zig, you must explicitly call `plat_socket_init()` and `plat_socket_cleanup()`.
- **Minimal Stdlib**: This example uses a local `util.zig` for basic string operations as the Z98 standard library is extremely minimal.
- **Milestone 11 Features**: Uses tagged unions for commands, braceless control flow normalization, and array-to-slice coercions.
