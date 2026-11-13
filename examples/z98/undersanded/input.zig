// input.zig — UNDERSANDED fight-screen key mapping (spec §28).
//
// Pure mapping: a key event in, an Action out. No I/O and no game-state
// mutation, so it is testable headless and replay recording (M3) can consume
// the same Action stream. The modal keys follow spec §9.3: F and Esc both
// decline (identical, consume no RNG).

const def = @import("def.zig");
const fight = @import("fight.zig");

pub const KEY_ESC: u8 = 27;
pub const VK_ESC: u16 = 0x1B;

pub const Key = struct { ch: u8, code: u16 };

fn lower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn isChar(k: Key, c: u8) bool {
    return lower(k.ch) == c;
}

fn isEsc(k: Key) bool {
    if (k.ch == KEY_ESC) return true;
    if (k.code == VK_ESC) return true;
    if (k.code == KEY_ESC) return true;
    return false;
}

fn mapModal(k: Key) ?def.Action {
    if (isEsc(k)) return def.Action{ .kind = def.ACT_DECLINE, .arg = 0 };
    if (isChar(k, 'a')) return def.Action{ .kind = def.ACT_ATTEMPT, .arg = 0 };
    if (isChar(k, 'f')) return def.Action{ .kind = def.ACT_DECLINE, .arg = 0 };
    return null;
}

fn mapFight(k: Key) ?def.Action {
    if (isChar(k, 's') or isChar(k, '1')) return def.Action{ .kind = def.ACT_STRIKE, .arg = 0 };
    if (isChar(k, 'r') or isChar(k, '2')) return def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 };
    if (isChar(k, 'e') or isChar(k, '3')) return def.Action{ .kind = def.ACT_EQUIP, .arg = 0 };
    if (isChar(k, 'f') or isChar(k, '4')) return def.Action{ .kind = def.ACT_FLEE, .arg = 0 };
    return null;
}

// `screen` is GameState.screen (fight.zig SCREEN_*). Esc has no fight action
// (it opens the menu per §28); inside the subdue modal it declines.
pub fn mapKey(screen: i32, key: Key) ?def.Action {
    if (screen == fight.SCREEN_SUBDUE or screen == fight.SCREEN_SUBDUE_POST) {
        return mapModal(key);
    }
    if (screen == fight.SCREEN_FIGHT) return mapFight(key);
    return null;
}
