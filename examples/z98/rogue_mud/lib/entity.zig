// examples/rogue_mud/lib/entity.zig
pub const EntityType = union(enum) {
    Player,
    Goblin,
    Orc,
};

pub const Entity = struct {
    typ: EntityType,
    hp: i16,
    max_hp: i16,
    x: u8,
    y: u8,
    active: bool,
};
