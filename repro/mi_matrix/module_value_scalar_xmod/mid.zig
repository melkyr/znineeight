// mid.zig — middle module: re-exports leaf.zig as a nested module alias.
//
// `pub const leaf = @import("leaf.zig")` registers `leaf` as a MODULE symbol in
// this module (symbol_registrator.zig:242-256), i.e. a module alias that is
// itself a member of a module. Accessing a member of it from another module
// (`mid.leaf.X`) is the "nested module value-position" shape.
pub const leaf = @import("leaf.zig");
