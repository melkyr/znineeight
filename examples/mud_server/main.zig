const std = @import("std.zig");
const util = @import("util.zig");

// Platform socket wrappers
extern "c" fn plat_socket_init() i32;
extern "c" fn plat_socket_cleanup() void;
extern "c" fn plat_create_tcp_server(port: u16) i32;
extern "c" fn plat_bind_listen(sock: i32, backlog: i32) i32;
extern "c" fn plat_accept(server_sock: i32) i32;
extern "c" fn plat_recv(sock: i32, buf: [*]u8, len: i32) i32;
extern "c" fn plat_send(sock: i32, buf: [*]const u8, len: i32) i32;
extern "c" fn plat_close_socket(sock: i32) void;

// fd_set support
const plat_fd_set = struct {
    // The exact layout of fd_set depends on the platform,
    // but we treat it as an opaque blob in Zig since we use the PAL macros/functions.
    // On Windows, fd_set is 260 bytes (FD_SETSIZE=64). On Linux, it's 128 bytes (FD_SETSIZE=1024).
    // 512 bytes provides a safe buffer for most legacy environments.
    data: [512]u8,
};

extern "c" fn plat_socket_select(nfds: i32, readfds: *plat_fd_set, writefds: *plat_fd_set, exceptfds: *plat_fd_set, timeout_ms: i32) i32;

// Macros/Helper wrappers
extern "c" fn plat_socket_fd_zero(s: *plat_fd_set) void;
extern "c" fn plat_socket_fd_set(fd: i32, s: *plat_fd_set) void;
extern "c" fn plat_socket_fd_isset(fd: i32, s: *plat_fd_set) bool;

// Constants
const MAX_CLIENTS: usize = 10;
const BUFFER_SIZE: usize = 256;
const PORT: u16 = 4000;

// Player state
const Player = struct {
    socket: i32,
    room_id: u8,
    buffer: [BUFFER_SIZE]u8,
    pos: usize,
    is_active: bool,
};

// World: rooms with descriptions and exits
const Room = struct {
    desc: []const u8,
    north: u8,
    south: u8,
    east: u8,
    west: u8,
};

// Workaround for global constant array of aggregates
var rooms: [2]Room = undefined;

fn initRooms() void {
    rooms[0] = Room {
        .desc = "You are in a dark forest. There is a path to the north.\r\n",
        .north = @intCast(u8, 1),
        .south = @intCast(u8, 0),
        .east = @intCast(u8, 0),
        .west = @intCast(u8, 0)
    };
    rooms[1] = Room {
        .desc = "A sunny clearing. Exits: south back to forest.\r\n",
        .north = @intCast(u8, 0),
        .south = @intCast(u8, 0),
        .east = @intCast(u8, 0),
        .west = @intCast(u8, 0)
    };
}

// Command handling
const Command = union(enum) {
    Look,
    Go: u8, // direction encoded: 0=north,1=south,2=east,3=west
    Quit,
    Unknown,
};

fn parseCommand(line: []const u8) Command {
    if (util.eql(line, "look")) return .Look;
    if (util.eql(line, "quit")) return .Quit;
    if (util.eql(line, "north")) return .{ .Go = @intCast(u8, 0) };
    if (util.eql(line, "south")) return .{ .Go = @intCast(u8, 1) };
    if (util.eql(line, "east"))  return .{ .Go = @intCast(u8, 2) };
    if (util.eql(line, "west"))  return .{ .Go = @intCast(u8, 3) };
    return .Unknown;
}

pub fn main() !void {
    initRooms();

    // Initialize sockets
    if (plat_socket_init() != 0) {
        std.debug.print("Failed to init sockets\n", .{});
        return;
    }

    const server = plat_create_tcp_server(PORT);
    if (server < 0) {
        std.debug.print("Failed to create server socket\n", .{});
        return;
    }

    if (plat_bind_listen(server, 5) < 0) {
        std.debug.print("Failed to listen\n", .{});
        return;
    }

    std.debug.print("MUD server listening on port 4000\n", .{});

    var players: [MAX_CLIENTS]Player = undefined;
    var i: usize = 0;
    while (i < MAX_CLIENTS) {
        players[i].is_active = false;
        i += 1;
    }

    var read_fds: plat_fd_set = undefined;

    while (true) {
        plat_socket_fd_zero(&read_fds);
        plat_socket_fd_set(server, &read_fds);

        var max_fd = server;
        i = 0;
        while (i < MAX_CLIENTS) {
            if (players[i].is_active) {
                plat_socket_fd_set(players[i].socket, &read_fds);
                if (players[i].socket > max_fd) max_fd = players[i].socket;
            }
            i += 1;
        }

        const ready_count = plat_socket_select(max_fd + 1, &read_fds, null, null, 100);
        if (ready_count < 0) {
            std.debug.print("select error\n", .{});
            break;
        }
        if (ready_count == 0) continue; // timeout

        // Check server socket for new connection
        if (plat_socket_fd_isset(server, &read_fds)) {
            const client = plat_accept(server);
            if (client >= 0) {
                // find free slot
                var found = false;
                i = 0;
                while (i < MAX_CLIENTS) {
                    if (!players[i].is_active) {
                        players[i] = Player{
                            .socket = client,
                            .room_id = @intCast(u8, 0),
                            .buffer = undefined,
                            .pos = @intCast(usize, 0),
                            .is_active = true,
                        };
                        const welcome: []const u8 = "Welcome to the MUD! Type 'look' to start.\r\n";
                        _ = plat_send(client, welcome.ptr, @intCast(i32, welcome.len));
                        found = true;
                        std.debug.print("New client connected\n", .{});
                        break;
                    }
                    i += 1;
                }
                if (!found) {
                    const full: []const u8 = "Server is full.\r\n";
                    _ = plat_send(client, full.ptr, @intCast(i32, full.len));
                    plat_close_socket(client);
                }
            }
        }

        // Data on client sockets
        i = 0;
        while (i < MAX_CLIENTS) {
            if (players[i].is_active and plat_socket_fd_isset(players[i].socket, &read_fds)) {
                var p = &players[i];
                const n = plat_recv(p.socket, &p.buffer[p.pos], @intCast(i32, BUFFER_SIZE - p.pos));
                if (n <= 0) {
                    // client disconnected
                    std.debug.print("Client disconnected\n", .{});
                    plat_close_socket(p.socket);
                    p.is_active = false;
                } else {
                    p.pos += @intCast(usize, n);
                    // Process complete lines (ending with \n)
                    var j: usize = 0;
                    while (j < p.pos) {
                        if (p.buffer[j] == '\n') {
                            var end = j;
                            if (end > 0 and p.buffer[end-1] == '\r') end -= 1;

                            const cmd_line = p.buffer[0..end];
                            const cmd = parseCommand(cmd_line);
                            const response = processCommand(p, cmd);
                            _ = plat_send(p.socket, response.ptr, @intCast(i32, response.len));

                            // move remaining data
                            if (j + 1 < p.pos) {
                                var k: usize = 0;
                                while (k < p.pos - (j + 1)) {
                                    p.buffer[k] = p.buffer[j + 1 + k];
                                    k += 1;
                                }
                                p.pos -= (j + 1);
                            } else {
                                p.pos = 0;
                            }
                            break;
                        }
                        j += 1;
                    }
                }
            }
            i += 1;
        }
    }

    plat_close_socket(server);
    plat_socket_cleanup();
}

fn processCommand(player: *Player, cmd: Command) []const u8 {
    return switch (cmd) {
        .Look => {
            const room = rooms[player.room_id];
            return room.desc;
        },
        .Go => |dir| {
            var new_room = player.room_id;
            if (dir == @intCast(u8, 0)) new_room = rooms[player.room_id].north;
            if (dir == @intCast(u8, 1)) new_room = rooms[player.room_id].south;
            if (dir == @intCast(u8, 2)) new_room = rooms[player.room_id].east;
            if (dir == @intCast(u8, 3)) new_room = rooms[player.room_id].west;

            if (new_room == player.room_id) {
                return "You cannot go that way.\r\n";
            }
            player.room_id = new_room;
            return rooms[player.room_id].desc;
        },
        .Quit => "Goodbye!\r\n",
        .Unknown => "Unknown command.\r\n",
        else => "Error\r\n",
    };
}
