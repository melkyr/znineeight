const sand_mod = @import("lib/sand.zig");
const rng_mod = @import("lib/rng.zig");
const scenario = @import("lib/scenario.zig");

const point_mod = @import("lib/point.zig");
const entity_mod = @import("lib/entity.zig");
const combat_mod = @import("lib/combat.zig");
const tile_mod = @import("lib/tile.zig");
const room_mod = @import("lib/room.zig");
const persistence = @import("lib/persistence.zig");
const net_mod = @import("lib/net.zig");
const ui_mod = @import("ui.zig");
const std = @import("../mud_server/std.zig");

const MULTIPLAYER_ENABLED: bool = false;

// External functions for input
extern "c" fn getchar() i32;
extern "c" fn kbhit() i32;
extern "c" fn __bootstrap_print(s: [*]const u8) void;
extern "c" fn __bootstrap_print_int(n: i32) void;

var buffer: [512 * 1024]u8 = undefined;
var temp_buffer: [512 * 1024]u8 = undefined;
var local_cells: [80 * 50]ui_mod.Cell = undefined;

pub fn main() !void {
    ui_mod.initUI();
    var arena = sand_mod.sand_init(buffer[0..], true);

    var temp_arena = sand_mod.sand_init(temp_buffer[0..], false);

    var rng = rng_mod.Random_init(@intCast(u32, 12345));

    __bootstrap_print("Welcome to Rogue MUD!\n");

    var server: net_mod.Server = undefined;
    if (MULTIPLAYER_ENABLED) {
        server = net_mod.Server_init(4000) catch |err| {
            __bootstrap_print("Warning: Network server failed to start, running in local-only mode.\n");
            // We continue anyway, just without networking
            var s = net_mod.Server { .listen_socket = -1, .clients = undefined };
            var si: usize = 0;
            while (si < @intCast(usize, 5)) : (si += 1) {
                s.clients[si].active = false;
            }
            s
        };
    } else {
        __bootstrap_print("Running in single-player ASCII mode.\n");
        server = net_mod.Server { .listen_socket = -1, .clients = undefined };
        var si: usize = 0;
        while (si < @intCast(usize, 5)) : (si += 1) {
            server.clients[si].active = false;
        }
    }
    defer if (server.listen_socket != -1) net_mod.Server_deinit(&server);

    __bootstrap_print("Generating dungeon...\n");

    var dungeon = try scenario.generateDungeon(&arena, &rng, @intCast(u8, 60), @intCast(u8, 30));

    // Place player in the center of the first room
    if (dungeon.room_count > 0) {
        const first_room = dungeon.rooms[0];
        const px = room_mod.Room_centerX(first_room);
        const py = room_mod.Room_centerY(first_room);
        var p_typ: entity_mod.EntityType = undefined;
        p_typ = .Player;
        combat_mod.addEntity(&dungeon, p_typ, px, py, @intCast(i16, 20));
    } else {
        __bootstrap_print("Error: No rooms generated!\n");
        return;
    }

    // Add some enemies
    var i: usize = 1;
    while (i < @intCast(usize, dungeon.room_count)) : (i += 1) {
        const room = dungeon.rooms[i];
        const ex = room_mod.Room_centerX(room);
        const ey = room_mod.Room_centerY(room);
        var g_typ: entity_mod.EntityType = undefined;
        g_typ = .Goblin;
        combat_mod.addEntity(&dungeon, g_typ, ex, ey, @intCast(i16, 5));
    }

    __bootstrap_print("Game started! Use WASD to move, Q to quit, L to look, V to save, B to load.\n");

    game_loop: while (true) {
        // Handle Networking and Local Input via select
        // Z98 Constraint: MSVC 6.0 and OpenWatcom may require individual field assignments
        // for local aggregates. Passing addresses of locals to C89 structs can trigger
        // "expression must be constant" errors if the lifter wraps them in Optionals.
        var read_fds: net_mod.plat_fd_set = undefined;
        net_mod.plat_socket_fd_zero(@ptrCast(*u8, &read_fds));

        var max_fd: i32 = -1;

        // Add stdin (FD 0) to select for non-blocking local input on POSIX
        if (!ui_mod.plat_is_windows()) {
            net_mod.plat_socket_fd_set(0, @ptrCast(*u8, &read_fds));
            max_fd = 0;
        }

        if (server.listen_socket != -1) {
            net_mod.plat_socket_fd_set(server.listen_socket, @ptrCast(*u8, &read_fds));
            if (server.listen_socket > max_fd) max_fd = server.listen_socket;

            var i: usize = 0;
            while (i < @intCast(usize, 5)) : (i += 1) {
                if (server.clients[i].active) {
                    net_mod.plat_socket_fd_set(server.clients[i].socket, @ptrCast(*u8, &read_fds));
                    if (server.clients[i].socket > max_fd) max_fd = server.clients[i].socket;
                }
            }
        }

        // We use a timeout so we can still poll for local input if kbhit is available,
        // or just to keep the game responsive.
        const ready_count = net_mod.plat_socket_select(max_fd + 1, @ptrCast(*u8, &read_fds), null, null, 50);

        if (ready_count == 0) {
            // Periodic local UI update
            if (!ui_mod.plat_is_windows()) {
                renderLocal(&temp_arena, dungeon);
                sand_mod.sand_reset(&temp_arena);
            }
        }

        // 1. Process New Connections
        if (server.listen_socket != -1 and net_mod.plat_socket_fd_isset(server.listen_socket, @ptrCast(*u8, &read_fds))) {
            const client_sock = net_mod.plat_accept(server.listen_socket);
            if (client_sock >= 0) {
                var found = false;
                var i: usize = 0;
                while (i < @intCast(usize, 5)) : (i += 1) {
                    if (!server.clients[i].active) {
                        // Create a new entity for this player
                        const first_room = dungeon.rooms[0];
                        const px = room_mod.Room_centerX(first_room);
                        const py = room_mod.Room_centerY(first_room);
                        var p_typ_2: entity_mod.EntityType = undefined;
                        p_typ_2 = .Player;
                        combat_mod.addEntity(&dungeon, p_typ_2, px, py, 20);

                        server.clients[i] = net_mod.Client {
                            .socket = client_sock,
                            .active = true,
                            .entity_idx = dungeon.entity_count - 1,
                            .buffer = undefined,
                            .pos = @intCast(usize, 0),
                        };
                        // Basic Telnet negotiation: Do echo, Do suppress go ahead, Will echo, Will suppress go ahead
                        const telnet_init: []const u8 = "\xff\xfd\x01\xff\xfd\x03\xff\xfb\x01\xff\xfb\x03";
                        _ = net_mod.plat_send(client_sock, telnet_init.ptr, @intCast(i32, telnet_init.len));

                        const msg: []const u8 = "Welcome to Rogue MUD!\r\nUse WASD to move.\r\n";
                        _ = net_mod.plat_send(client_sock, msg.ptr, @intCast(i32, msg.len));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    const msg: []const u8 = "Server full.\r\n";
                    _ = net_mod.plat_send(client_sock, msg.ptr, @intCast(i32, msg.len));
                    net_mod.plat_close_socket(client_sock);
                }
            }
        }

        // 2. Process Client Data
        var client_idx: usize = 0;
        while (client_idx < @intCast(usize, 5)) : (client_idx += 1) {
            var client = &server.clients[client_idx];
            if (client.active and net_mod.plat_socket_fd_isset(client.socket, @ptrCast(*u8, &read_fds))) {
                const n = net_mod.plat_recv(client.socket, &client.buffer[client.pos], @intCast(i32, 1024 - client.pos));
                if (n <= 0) {
                    // Client disconnected
                    dungeon.entities[client.entity_idx].active = false;
                    client.active = false;
                    net_mod.plat_close_socket(client.socket);
                } else {
                    client.pos += @intCast(usize, n);
                    // Process input character by character for now (primitive)
                    var j: usize = 0;
                    while (j < client.pos) : (j += 1) {
                        const cc = client.buffer[j];
                        // Ignore telnet commands (0xFF ...)
                        if (cc == 0xFF) {
                            j += 2; // skip 3-byte command
                            continue;
                        }
                        var cdx: i8 = 0;
                        var cdy: i8 = 0;

                        switch (cc) {
                            'w', 'W' => cdy = -1,
                            's', 'S' => cdy = 1,
                            'a', 'A' => cdx = -1,
                            'd', 'D' => cdx = 1,
                            else => {},
                        }

                        if (cdx != 0 or cdy != 0) {
                            combat_mod.moveEntity(&dungeon, client.entity_idx, cdx, cdy);
                            combat_mod.updateEnemies(&temp_arena, &dungeon);
                            sand_mod.sand_reset(&temp_arena);
                            // Broadcast update to all clients
                            broadcastDungeon(server, dungeon);
                        }
                    }
                    client.pos = 0;
                }
            }
        }

        // 3. Process Local Input
        var c: i32 = -1;
        if (!ui_mod.plat_is_windows()) {
            if (net_mod.plat_socket_fd_isset(0, @ptrCast(*u8, &read_fds))) {
                c = getchar();
            }
        } else {
            // Fallback for Windows (though still potentially blocking if we don't have a good kbhit/poll)
            renderLocal(&temp_arena, dungeon);
            sand_mod.sand_reset(&temp_arena);
            c = getchar();
        }

        var dx: i8 = 0;
        var dy: i8 = 0;

        if (c != -1) switch (c) {
            'q', 'Q' => break :game_loop,
            'w', 'W' => dy = -1,
            's', 'S' => dy = 1,
            'a', 'A' => dx = -1,
            'd', 'D' => dx = 1,
            'l', 'L' => ui_mod.lookSurroundings(dungeon),
            'v', 'V' => {
                __bootstrap_print("Saving dungeon to 'save.dat'...\n");
                persistence.saveDungeon(&arena, dungeon, "save.dat") catch {
                    __bootstrap_print("Failed to save dungeon!\n");
                };
            },
            'b', 'B' => {
                __bootstrap_print("Loading dungeon from 'save.dat'...\n");
                persistence.loadDungeon(&arena, &dungeon, "save.dat") catch {
                    __bootstrap_print("Failed to load dungeon!\n");
                };
            },
            else => {},
        }

        if (dx != 0 or dy != 0) {
            combat_mod.moveEntity(&dungeon, @intCast(usize, 0), dx, dy);
            combat_mod.updateEnemies(&temp_arena, &dungeon);
            sand_mod.sand_reset(&temp_arena);
            broadcastDungeon(server, dungeon);

            // Immediate UI update for local player
            if (!ui_mod.plat_is_windows()) {
                renderLocal(&temp_arena, dungeon);
                sand_mod.sand_reset(&temp_arena);
            }
        }

        // Simple turn feedback
        if (!dungeon.entities[0].active) {
            __bootstrap_print("You have died. Game Over.\n");
            break :game_loop;
        }
    }
}

fn broadcastDungeon(server: net_mod.Server, dungeon: scenario.Dungeon_t) void {
    var i: usize = 0;
    while (i < @intCast(usize, 5)) : (i += 1) {
        if (server.clients[i].active) {
            drawDungeonToSocket(server.clients[i].socket, dungeon);
        }
    }
}

fn drawDungeonToSocket(sock: net_mod.PlatSocket, dungeon: scenario.Dungeon_t) void {
    // Clear screen for telnet (simple escape)
    const clear: []const u8 = "\x1b[2J\x1b[H";
    _ = net_mod.plat_send(sock, clear.ptr, @intCast(i32, clear.len));

    var y: u8 = 0;
    while (y < dungeon.height) : (y += 1) {
        var x: u8 = 0;
        var line: [256]u8 = undefined;
        var line_pos: usize = 0;

        while (x < dungeon.width) : (x += 1) {
            if (line_pos >= 250) break; // Safety break
            var found_entity = false;
            var i: usize = 0;
            while (i < dungeon.entity_count) : (i += 1) {
                const e = dungeon.entities[i];
                if (e.active and e.x == x and e.y == y) {
                    line[line_pos] = switch (e.typ) {
                        .Player => @intCast(u8, '@'),
                        .Goblin => @intCast(u8, 'g'),
                        .Orc => @intCast(u8, 'o'),
                        else => @intCast(u8, '?'),
                    };
                    line_pos += 1;
                    found_entity = true;
                    break;
                }
            }

            if (!found_entity) {
                const idx = @intCast(usize, y) * @intCast(usize, dungeon.width) + @intCast(usize, x);
                const tile = dungeon.tiles[idx];
                line[line_pos] = switch (tile) {
                    .Wall => @intCast(u8, '#'),
                    .Floor => @intCast(u8, '.'),
                    .Door => @intCast(u8, '+'),
                    else => @intCast(u8, '?'),
                };
                line_pos += 1;
            }
        }
        line[line_pos] = '\r';
        line[line_pos+1] = '\n';
        _ = net_mod.plat_send(sock, &line[0], @intCast(i32, line_pos + 2));
    }
}

fn renderLocal(arena: *sand_mod.Sand, dungeon: scenario.Dungeon_t) void {
    const rows = @intCast(usize, dungeon.height) + 1;
    const cols = @intCast(usize, dungeon.width);
    const cell_count = rows * cols;

    const cells = local_cells[0..cell_count];

    var y: u8 = 0;
    while (y < dungeon.height) : (y += 1) {
        var x: u8 = 0;
        while (x < dungeon.width) : (x += 1) {
            const idx = @intCast(usize, y) * cols + @intCast(usize, x);
            var cell = ui_mod.Cell{ .ch = ' ', .fg = ui_mod.COLOR_WHITE, .bg = ui_mod.COLOR_BLACK };

            // Check for entities first
            var found_entity = false;
            var i: usize = 0;
            while (i < dungeon.entity_count) : (i += 1) {
                const e = dungeon.entities[i];
                if (e.active and e.x == x and e.y == y) {
                    cell.ch = switch (e.typ) {
                        .Player => '@',
                        .Goblin => 'g',
                        .Orc => 'o',
                        else => '?',
                    };
                    cell.fg = switch (e.typ) {
                        .Player => ui_mod.COLOR_GREEN | ui_mod.COLOR_BRIGHT,
                        .Goblin => ui_mod.COLOR_RED | ui_mod.COLOR_BRIGHT,
                        .Orc => ui_mod.COLOR_RED,
                        else => ui_mod.COLOR_WHITE,
                    };
                    found_entity = true;
                    break;
                }
            }

            if (!found_entity) {
                const tidx = @intCast(usize, y) * @intCast(usize, dungeon.width) + @intCast(usize, x);
                const tile = dungeon.tiles[tidx];
                cell.ch = switch (tile) {
                    .Wall => '#',
                    .Floor => '.',
                    .Door => '+',
                    else => '?',
                };
                cell.fg = switch (tile) {
                    .Wall => ui_mod.COLOR_BLUE,
                    .Floor => ui_mod.COLOR_WHITE,
                    .Door => ui_mod.COLOR_YELLOW,
                    else => ui_mod.COLOR_WHITE,
                };
            }
            cells[idx] = cell;
        }
    }

    // Status Bar row
    const player = dungeon.entities[0];
    const status_y = @intCast(usize, dungeon.height);
    var sx: usize = 0;
    while (sx < cols) : (sx += 1) {
        cells[status_y * cols + sx] = ui_mod.Cell{ .ch = ' ', .fg = ui_mod.COLOR_WHITE, .bg = ui_mod.COLOR_BLUE };
    }

    // Status text injection
    const status_idx = status_y * cols;
    injectString(@ptrCast([*]ui_mod.Cell, &cells[status_idx + 1]), "Pos:(");
    injectInt(@ptrCast([*]ui_mod.Cell, &cells[status_idx + 6]), @intCast(i32, player.x));
    cells[status_idx + 9].ch = ',';
    injectInt(@ptrCast([*]ui_mod.Cell, &cells[status_idx + 10]), @intCast(i32, player.y));
    cells[status_idx + 13].ch = ')';

    injectString(@ptrCast([*]ui_mod.Cell, &cells[status_idx + 15]), "HP:");
    injectInt(@ptrCast([*]ui_mod.Cell, &cells[status_idx + 18]), @intCast(i32, player.hp));
    cells[status_idx + 21].ch = '/';
    injectInt(@ptrCast([*]ui_mod.Cell, &cells[status_idx + 22]), @intCast(i32, player.max_hp));

    ui_mod.draw(rows, cols, cells[0..cell_count]);
}

fn injectString(cells: [*]ui_mod.Cell, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        cells[i].ch = s[i];
    }
}

fn injectInt(cells: [*]ui_mod.Cell, n: i32) void {
    if (n == 0) {
        cells[0].ch = '0';
        return;
    }
    var val = @intCast(u32, if (n < 0) -n else n);
    var i: usize = 0;
    var temp: [10]u8 = undefined;
    while (val > 0) {
        temp[i] = @intCast(u8, @intCast(u32, '0') + (val % 10));
        val /= 10;
        i += 1;
    }
    var j: usize = 0;
    while (j < i) : (j += 1) {
        cells[j].ch = temp[i - 1 - j];
    }
}
