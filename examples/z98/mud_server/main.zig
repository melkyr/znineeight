const std = @import("std");
const util = @import("util.zig");
const std_net = @import("std_net");
const std_arena = @import("std_arena");

@cInclude("zig_runtime.h");

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

var client_tasks: [MAX_CLIENTS]std.async.Task = undefined;
var client_task_ptrs: [MAX_CLIENTS]*std.async.Task = undefined;
var client_args: [MAX_CLIENTS]ClientTaskArgs = undefined;
var client_recs: [MAX_CLIENTS]ClientCoroutineArgs = undefined;
var client_sched: std.async.Scheduler = undefined;
// 8-aligned backing; a bare [N]u8 is 1-aligned and trips contextInit's @panic.
var async_storage: [32 * 1024]u64 = undefined;

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
    if (std_net.init() != 0) {
        std.io.print("Failed to init sockets\n", .{});
        return;
    }

    const server = std_net.createTcpServer(PORT);
    if (server < 0) {
        std.io.print("Failed to create server socket\n", .{});
        return;
    }

    if (std_net.bindListen(server, 5) < 0) {
        std.io.print("Failed to listen\n", .{});
        return;
    }

    std.io.print("MUD server listening on port 4000\n", .{});

    var players: [MAX_CLIENTS]Player = undefined;
    var i: usize = 0;
    while (i < MAX_CLIENTS) {
        players[i].is_active = false;
        i += 1;
    }

    var async_arena = std_arena.init(@ptrCast([*]u8, &async_storage)[std.async.HEADER_SIZE .. 32 * 1024 * 8]);
    var async_ctx: *std.async.Context = std.async.contextInit(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8]);
    client_sched = std.async.schedulerInit(client_task_ptrs[0..]);
    i = 0;
    while (i < MAX_CLIENTS) {
        client_task_ptrs[i] = &client_tasks[i];
        client_task_ptrs[i].frame = @ptrFromInt(*void, 0);
        client_task_ptrs[i].state = .done;
        client_task_ptrs[i].cancel_requested = false;
        i += 1;
    }

    var read_fds: std_net.fd_set = undefined;

    while (true) {
        std_net.fdZero(@ptrCast(*u8, &read_fds));
        std_net.fdSet(server, @ptrCast(*u8, &read_fds));
        var max_fd = server;
        i = 0;
        while (i < MAX_CLIENTS) {
            if (players[i].is_active) {
                std_net.fdSet(players[i].socket, @ptrCast(*u8, &read_fds));
                if (players[i].socket > max_fd) max_fd = players[i].socket;
            }
            i += 1;
        }
        const ready_count = std_net.select(max_fd + 1, @ptrCast(*u8, &read_fds), null, null, 100);
        if (ready_count < 0) { std.io.print("select error\n", .{}); break; }
        if (ready_count == 0) continue;
        if (std_net.fdIsset(server, @ptrCast(*u8, &read_fds))) {
            const client = std_net.accept(server);
            if (client >= 0) {
                // find free slot
                var found = false;
                i = 0;
                while (i < MAX_CLIENTS) {
                    if (!players[i].is_active) {
                        players[i] = Player{ .socket = client, .room_id = @intCast(u8, 0),
                            .buffer = undefined, .pos = @intCast(usize, 0), .is_active = true };
                        client_args[i] = ClientTaskArgs{ .player = &players[i], .rooms = &rooms };
                        client_recs[i] = ClientCoroutineArgs{ .cta = &client_args[i] };
                        const csz = @intCast(usize, @asyncFrameSize(clientCoroutine));
                        const cframe = std_arena.alloc(&async_arena, csz) catch {
                            const full2: []const u8 = "Server is full.\r\n";
                            _ = std_net.send(client, full2.ptr, @intCast(i32, full2.len));
                            std_net.close(client);
                            players[i].is_active = false;
                            i += 1;
                            continue;
                        };
                        client_task_ptrs[i].frame = @asyncInit(async_ctx, @ptrCast([*]u8, cframe), clientCoroutine, @ptrCast(*const void, &client_recs[i]));
                        client_task_ptrs[i].ctx = async_ctx;
                        client_task_ptrs[i].arg = @ptrCast(*void, &client_recs[i]);
                        client_task_ptrs[i].result = @ptrCast(*void, &client_recs[i]);
                        client_task_ptrs[i].cancel_requested = false;
                        client_task_ptrs[i].waiting_on = client_task_ptrs[i];
                        client_task_ptrs[i].has_waiting_on = false;
                        _ = std.async.addTask(&client_sched, client_task_ptrs[i]);
                        const welcome: []const u8 = "Welcome to the MUD! Type 'look' to start.\r\n";
                        _ = std_net.send(client, welcome.ptr, @intCast(i32, welcome.len));
                        found = true;
                        std.io.print("New client connected\n", .{});
                        break;
                    }
                    i += 1;
                }
                if (!found) {
                    const full: []const u8 = "Server is full.\r\n";
                    _ = std_net.send(client, full.ptr, @intCast(i32, full.len));
                    std_net.close(client);
                }
            }
        }
        i = 0;
        while (i < MAX_CLIENTS) {
            if (players[i].is_active and std_net.fdIsset(players[i].socket, @ptrCast(*u8, &read_fds))) {
                const step = @asyncResume(client_task_ptrs[i].frame, null);
                if (step == null) {
                    // coroutine completed (quit or disconnect): free the slot
                    std.async.waitFor(&client_sched, client_task_ptrs[i]) catch {};
                    std_net.close(players[i].socket);
                    players[i].is_active = false;
                    client_task_ptrs[i].state = .done;
                }
            }
            i += 1;
        }
        std.async.tick(&client_sched) catch {};
    }

    std_net.close(server);
    std_net.cleanup();
}

fn processCommand(player: *Player, cmd: Command) []const u8 {
    return switch (cmd) {
        .Look => {
            return rooms[player.room_id].desc;
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

pub const ClientTaskArgs = struct {
    player: *Player,
    rooms: [*]Room,
};

// B3 (option a): the `@asyncInit` args record's fields ARE the coroutine's
// parameters; the record is `{ cta: *ClientTaskArgs }`.
pub const ClientCoroutineArgs = struct { cta: *ClientTaskArgs };

pub fn clientCoroutine(cta: *ClientTaskArgs) void {
    const p = cta.player;
    while (true) {
        if (!p.is_active) return;
        const n = std_net.recv(p.socket, &p.buffer[p.pos], @intCast(i32, BUFFER_SIZE - p.pos));
        if (n <= 0) {
            std.io.print("Client disconnected\n", .{});
            p.is_active = false;
            return;
        }
        p.pos += @intCast(usize, n);
        var j: usize = 0;
        while (j < p.pos) {
            if (p.buffer[j] == '\n') {
                var end = j;
                if (end > 0 and p.buffer[end - 1] == '\r') end -= 1;
                const cmd = parseCommand(p.buffer[0..end]);
                const response = processCommand(p, cmd);
                _ = std_net.send(p.socket, response.ptr, @intCast(i32, response.len));
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
        _ = @asyncSuspend(null);
    }
}
