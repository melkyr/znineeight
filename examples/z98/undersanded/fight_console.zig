// fight_console.zig — playable console fight loop (spec §26 console mode).
//
// Plain text I/O (std_io) only: pick one of the five M2 creatures, then feed
// stdin keys through input.mapKey -> game.gameStep and print the render_term
// Screen after every action. The GUI entry (under.exe) keeps the M1 skeleton;
// this module is reached only from the CONSOLE entry (undtool.exe).

const io = @import("std_io.zig");
const def = @import("def.zig");
const fight = @import("fight.zig");
const game = @import("game.zig");
const creatures = @import("creatures_t1.zig");
const input = @import("input.zig");
const render = @import("render_term.zig");

fn outcomeName(o: i32) []const u8 {
    switch (o) {
        def.OUT_SUBDUE => return "SUBDUE",
        def.OUT_KILL => return "KILL",
        def.OUT_OVERKILL => return "OVERKILL",
        def.OUT_CREATURE_FLED => return "CREATURE_FLED",
        def.OUT_PLAYER_FLED => return "PLAYER_FLED",
        else => return "ONGOING",
    }
}

fn readKey() input.Key {
    var b = io.readByte();
    while (b == 10 or b == 13 or b == ' ') {
        b = io.readByte();
    }
    return input.Key{ .ch = b, .code = 0 };
}

fn printFrame(s: *const def.GameState, d: *const def.CreatureDef) void {
    var sc: render.Screen = undefined;
    render.renderFrame(s, d, &sc);
    var buf: [4096]u8 = undefined;
    io.write(render.dump(&sc, buf[0..]));
}

fn chooseCreature() i32 {
    io.write("Choose a creature:\n");
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const d = creatures.defAt(i);
        io.write("  ");
        io.printInt(i + 1);
        io.write(") ");
        io.write(render.creatureName(d.id));
        io.write(" (");
        io.write(render.roleName(d.role));
        io.write(")\n");
    }
    io.write("> ");

    var pick: i32 = -1;
    while (pick < 0) {
        const k = readKey();
        if (k.ch >= '1' and k.ch <= '5') {
            pick = @intCast(i32, k.ch - '1');
        } else {
            io.write("Choose 1-5.\n> ");
        }
    }
    return pick;
}

pub fn run() void {
    const index = chooseCreature();
    const d = creatures.defAt(index);
    io.write("\n");

    var s: def.GameState = undefined;
    game.startFight(&s, index);
    printFrame(&s, &d);

    var steps: i32 = 0;
    while (s.fight.outcome == def.OUT_ONGOING) {
        io.write("> ");
        const k = readKey();
        const maybe = input.mapKey(s.screen, k);
        if (maybe) |a| {
            game.gameStep(&s, a);
            steps += 1;
            printFrame(&s, &d);
        } else {
            io.write("Unknown action key.\n");
        }
    }

    io.write("Outcome: ");
    io.write(outcomeName(s.fight.outcome));
    io.write(" after ");
    io.printInt(steps);
    io.write(" actions.\n");
}
