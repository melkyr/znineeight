const ctxmod = @import("ctx.zig");

pub const Cpu = ctxmod.Cpu;
pub const Bus = ctxmod.Bus;

pub const CODE_CACHE_BYTES: usize = 1048576;
pub const BLOCK_MAX_BYTES: usize = 4096;
pub const ENTRY_COUNT: usize = 4096;

pub const MEM_COMMIT: u32 = 0x1000;
pub const MEM_RESERVE: u32 = 0x2000;
pub const MEM_RELEASE: u32 = 0x8000;
pub const PAGE_EXECUTE_READWRITE: u32 = 0x40;

pub const ROM0_START: u16 = 0x0000;
pub const ROM0_END: u16 = 0x3FFF;
pub const ROMX_START: u16 = 0x4000;
pub const ROMX_END: u16 = 0x7FFF;
pub const ROM_END: u16 = 0x7FFF;

extern "c" fn mmap(addr: *void, len: usize, prot: i32, flags: i32, fd: i32, off: i32) *void;
extern "c" fn munmap(addr: *void, len: usize) i32;
extern "stdcall" fn VirtualAlloc(addr: *void, size: usize, typ: u32, protect: u32) *void;
extern "stdcall" fn VirtualFree(addr: *void, size: usize, typ: u32) i32;
extern "stdcall" fn FlushInstructionCache(process: *void, base: *const void, size: usize) i32;
extern "stdcall" fn GetCurrentProcess() *void;

pub const Entry = struct {
    valid: bool,
    bank: u16,
    pc: u16,
    code_off: u32,
    len: u32,
    glue_off: u32,
    pc_imm_off: u32,
    bank_imm_off: u32,
    chain_inc_off: u32,
    jmp_disp_off: u32,
    exit_off: u32,
    is_ret: bool,
    has_fixed_succ: bool,
    succ_bank: u16,
    succ_pc: u16,
    has_ret: bool,
    ret_bank: u16,
    ret_target: u16,
    link_valid: bool,
    link_bank: u16,
    link_pc: u16,
    link_target_off: u32,
};

pub const Stats = struct {
    blocks: u32,
    executed: u32,
    chained: u32,
    fallback: u32,
    resets: u32,
    collisions: u32,
    tinstr: u32,
    minstr: u32,
    rejected: u32,
};

pub const Dynarec = struct {
    mem: [*]u8,
    mapped: bool,
    used: usize,
    entries: [ENTRY_COUNT]Entry,
    stats: Stats,
    last_entry: u32,
};

const MAP_FAILED: usize = 0xFFFFF000;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

pub fn align16(v: usize) usize {
    return (v + 15) & ~@as(usize, 15);
}

pub fn align4(v: usize) usize {
    return (v + 3) & ~@as(usize, 3);
}

pub fn entryIndex(bank: u16, pc: u16) usize {
    const b: u32 = @intCast(u32, bank);
    const p: u32 = @intCast(u32, pc);
    return @intCast(usize, (p *% 31 +% b *% 257) & (ENTRY_COUNT - 1));
}

pub fn effectiveBank(bus: *const Bus, pc: u16) u16 {
    const off: usize = if (pc < ROMX_START) bus.cart.rom0_off else bus.cart.romx_off;
    return @intCast(u16, (off / 0x4000) & 0xFFFF);
}

pub fn clearEntries(d: *Dynarec) void {
    var i: usize = 0;
    while (i < ENTRY_COUNT) : (i += 1) {
        d.entries[i].valid = false;
        d.entries[i].link_valid = false;
    }
}

pub fn dynarecOpen(d: *Dynarec, bus: *Bus) bool {
    _ = bus;
    d.mapped = false;
    d.used = 0;
    d.last_entry = 0;
    d.stats = Stats{ .blocks = 0, .executed = 0, .chained = 0, .fallback = 0, .resets = 0, .collisions = 0, .tinstr = 0, .minstr = 0, .rejected = 0 };
    clearEntries(d);
    if (@isWindows()) {
        const raw = VirtualAlloc(nullVoid(), CODE_CACHE_BYTES, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        if (@ptrToInt(raw) == 0) return false;
        d.mem = @ptrCast([*]u8, raw);
    } else {
        const raw = mmap(nullVoid(), CODE_CACHE_BYTES, 7, 0x22, -1, 0);
        if (@ptrToInt(raw) >= MAP_FAILED) return false;
        d.mem = @ptrCast([*]u8, raw);
    }
    d.mapped = true;
    return true;
}

pub fn dynarecClose(d: *Dynarec) void {
    if (!d.mapped) return;
    if (@isWindows()) {
        _ = VirtualFree(@ptrCast(*void, d.mem), 0, MEM_RELEASE);
    } else {
        _ = munmap(@ptrCast(*void, d.mem), CODE_CACHE_BYTES);
    }
    d.mapped = false;
    d.used = 0;
    d.last_entry = 0;
    clearEntries(d);
}

pub fn dynarecFlush(d: *Dynarec) void {
    d.used = 0;
    d.last_entry = 0;
    clearEntries(d);
}

pub fn dynarecInvalidateBank(d: *Dynarec, bank: u16) void {
    var i: usize = 0;
    while (i < ENTRY_COUNT) : (i += 1) {
        if (d.entries[i].valid and d.entries[i].bank == bank) {
            d.entries[i].valid = false;
            d.entries[i].link_valid = false;
        }
    }
}

pub fn dynarecInvalidateRange(d: *Dynarec, lo: u16, hi: u16) void {
    var i: usize = 0;
    while (i < ENTRY_COUNT) : (i += 1) {
        if (d.entries[i].valid and d.entries[i].pc >= lo and d.entries[i].pc <= hi) {
            d.entries[i].valid = false;
            d.entries[i].link_valid = false;
        }
    }
}

pub fn dynarecInvalidateRom0(d: *Dynarec) void {
    dynarecInvalidateRange(d, ROM0_START, ROM0_END);
}

pub fn dynarecInvalidateRomx(d: *Dynarec) void {
    dynarecInvalidateRange(d, ROMX_START, ROMX_END);
}

pub fn dynarecLookup(d: *Dynarec, bank: u16, pc: u16) ?*Entry {
    const e: *Entry = &d.entries[entryIndex(bank, pc)];
    if (!e.valid) return null;
    if (e.bank != bank or e.pc != pc) return null;
    return e;
}

pub fn dynarecEnabled(d: *const Dynarec) bool {
    return d.mapped;
}

pub fn flushRange(d: *Dynarec, off: usize, len: usize) void {
    if (!d.mapped or len == 0) return;
    if (@isWindows()) {
        _ = FlushInstructionCache(GetCurrentProcess(), @ptrCast(*const void, d.mem + off), len);
    }
}
