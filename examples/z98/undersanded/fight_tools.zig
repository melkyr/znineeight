// fight_tools.zig — equipped-tool predicates for the fight resolver.
//
// Pure reads of FightState: which tool is active determines hook/shield/lure/
// sonar interactions. fight.zig owns the action state machine.

const def = @import("def.zig");

pub fn hookActive(s: *const def.GameState) bool {
    return s.fight.tool_active != 0 and s.fight.tool == def.TOOL_PRESSURE_HOOK;
}

pub fn shieldActive(s: *const def.GameState) bool {
    return s.fight.tool_active != 0 and s.fight.tool == def.TOOL_CORAL_SHIELD;
}

pub fn lureActive(s: *const def.GameState) bool {
    return s.fight.tool_active != 0 and s.fight.tool == def.TOOL_LURE;
}

pub fn sonarActive(s: *const def.GameState) bool {
    return s.fight.tool_active != 0 and s.fight.tool == def.TOOL_SONAR;
}
