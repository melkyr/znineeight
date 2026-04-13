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
    data: [512]u8, // opaque platform-specific size
};

extern "c" fn plat_socket_select(nfds: i32, readfds: ?*plat_fd_set, writefds: ?*plat_fd_set, exceptfds: ?*plat_fd_set, timeout_ms: i32) i32;

// fd_set manipulation helpers
extern "c" fn plat_socket_fd_zero(s: *plat_fd_set) void;
extern "c" fn plat_socket_fd_set(fd: i32, s: *plat_fd_set) void;
extern "c" fn plat_socket_fd_isset(fd: i32, s: *plat_fd_set) bool;

const MAX_CLIENTS = 10;
const BUFFER_SIZE = 256;
const PORT: u16 = 4000;

const Direction = enum(u8) {
    North = 0,
    South = 1,
    East  = 2,
    West  = 3,
};

const Player = struct {
    socket: i32,
    room_id: u8,
    buffer: [BUFFER_SIZE]u8,
    pos: usize,
    active: bool,
};

const Room = struct {
    desc: []const u8,
    exits: [4]u8, // indexed by Direction
};

var rooms: [2]Room = undefined;

fn initRooms() void {
    rooms[0] = Room{
        .desc = "You are in a dark forest. Paths: north.\r\n",
        .exits = [4]u8{ @intCast(u8, 1), @intCast(u8, 0), @intCast(u8, 0), @intCast(u8, 0) },
    };
    rooms[1] = Room{
        .desc = "A sunny clearing. Paths: south.\r\n",
        .exits = [4]u8{ @intCast(u8, 0), @intCast(u8, 0), @intCast(u8, 0), @intCast(u8, 0) },
    };
}

const Command = union(enum) {
    Look,
    Go: Direction,
    Quit,
    Unknown,
};

fn parseCommand(line: []const u8) Command {
    if (util.eql(line, "look")) return Command.Look;
    if (util.eql(line, "quit")) return Command.Quit;
    if (util.eql(line, "north")) return Command{ .Go = Direction.North };
    if (util.eql(line, "south")) return Command{ .Go = Direction.South };
    if (util.eql(line, "east"))  return Command{ .Go = Direction.East };
    if (util.eql(line, "west"))  return Command{ .Go = Direction.West };
    return Command.Unknown;
}

pub fn main() !void {
    initRooms();

    if (plat_socket_init() != 0) {
        std.debug.print("Failed to init sockets\n", .{});
        return;
    }
    defer plat_socket_cleanup();

    const server = plat_create_tcp_server(PORT);
    if (server < 0) {
        std.debug.print("Failed to create server socket\n", .{});
        return;
    }
    defer plat_close_socket(server);

    if (plat_bind_listen(server, 5) < 0) {
        std.debug.print("Failed to listen\n", .{});
        return;
    }

    std.debug.print("MUD server listening on port 4000\n", .{});

    var players: [MAX_CLIENTS]Player = undefined;
    var i: usize = @intCast(usize, 0);
    while (i < MAX_CLIENTS) : (i += 1) {
        players[i].active = false;
    }

    var read_fds: plat_fd_set = undefined;

    while (true) {
        plat_socket_fd_zero(&read_fds);
        plat_socket_fd_set(server, &read_fds);

        var max_fd = server;
        var p_idx: usize = @intCast(usize, 0);
        while (p_idx < MAX_CLIENTS) : (p_idx += 1) {
            if (players[p_idx].active) {
                plat_socket_fd_set(players[p_idx].socket, &read_fds);
                if (players[p_idx].socket > max_fd) max_fd = players[p_idx].socket;
            }
        }

        const ready = plat_socket_select(max_fd + 1, &read_fds, null, null, 100);
        if (ready < 0) {
            std.debug.print("select error\n", .{});
            break;
        }
        if (ready == 0) continue;

        // New connection
        if (plat_socket_fd_isset(server, &read_fds)) {
            const client = plat_accept(server);
            if (client >= 0) {
                var idx: usize = @intCast(usize, 0);
                var free_idx: i32 = -1;
                while (idx < MAX_CLIENTS) : (idx += 1) {
                    if (!players[idx].active) {
                        free_idx = @intCast(i32, idx);
                        break;
                    }
                }

                if (free_idx >= 0) {
                    var new_p = &players[@intCast(usize, free_idx)];
                    new_p.socket = client;
                    new_p.room_id = @intCast(u8, 0);
                    new_p.pos = @intCast(usize, 0);
                    new_p.active = true;

                    const welcome: []const u8 = "Welcome to the MUD! Type 'look' to start.\r\n";
                    _ = plat_send(client, welcome.ptr, @intCast(i32, welcome.len));
                    std.debug.print("New client connected\n", .{});
                } else {
                    const full: []const u8 = "Server is full.\r\n";
                    _ = plat_send(client, full.ptr, @intCast(i32, full.len));
                    plat_close_socket(client);
                }
            }
        }

        // Handle client I/O
        var slot_idx: usize = @intCast(usize, 0);
        while (slot_idx < MAX_CLIENTS) : (slot_idx += 1) {
            var p = &players[slot_idx];
            if (p.active) {
                if (plat_socket_fd_isset(p.socket, &read_fds)) {
                    const n = plat_recv(p.socket, &p.buffer[p.pos], @intCast(i32, BUFFER_SIZE - p.pos));
                    if (n <= 0) {
                        std.debug.print("Client disconnected\n", .{});
                        plat_close_socket(p.socket);
                        p.active = false;
                    } else {
                        p.pos += @intCast(usize, n);
                        // Process all complete lines in the buffer
                        var processing: bool = true;
                        while (processing) {
                            var found_newline: bool = false;
                            var j: usize = @intCast(usize, 0);
                            while (j < p.pos) : (j += 1) {
                                if (p.buffer[j] == '\n') {
                                    var end = j;
                                    if (end > 0 and p.buffer[end-1] == '\r') end -= 1;

                                    const cmd_line = p.buffer[0..end];
                                    const cmd = parseCommand(cmd_line);
                                    const response = processCommand(p, cmd);
                                    _ = plat_send(p.socket, response.ptr, @intCast(i32, response.len));

                                    const remaining = p.pos - (j + 1);
                                    if (remaining > 0) {
                                        var k: usize = @intCast(usize, 0);
                                        while (k < remaining) : (k += 1) {
                                            p.buffer[k] = p.buffer[j + 1 + k];
                                        }
                                    }
                                    p.pos = remaining;
                                    found_newline = true;
                                    break;
                                }
                            }
                            if (!found_newline) {
                                processing = false;
                            }
                        }
                    }
                }
            }
        }
    }
}

fn processCommand(player: *Player, cmd: Command) []const u8 {
    return switch (cmd) {
        Command.Look => rooms[player.room_id].desc,
        Command.Go => |dir| {
            const new_room = rooms[player.room_id].exits[@intCast(usize, @enumToInt(dir))];
            if (new_room == player.room_id) {
                return "You cannot go that way.\r\n";
            }
            player.room_id = new_room;
            return rooms[new_room].desc;
        },
        Command.Quit => "Goodbye!\r\n",
        Command.Unknown => "Unknown command.\r\n",
        else => "Error\r\n",
    };
}
