// ctx.zig — dynarec execution context shared by the emitter and helpers.
//
// The generated block is cdecl `fn (*DynCtx) u32`: `cpu` and `bus` point at
// the live interpreter state and `cycles` accumulates block cycles for the
// dispatcher. Task 2 only needs the pointer pair and the cycle slot.

const cpumod = @import("../cpu.zig");
const mmumod = @import("../mmu.zig");

pub const Cpu = cpumod.Cpu;
pub const Bus = mmumod.Bus;
pub const Page = mmumod.Page;
pub const PageKind = mmumod.PageKind;

pub const DynCtx = struct { cpu: *Cpu, bus: *Bus, cycles: u32 };
