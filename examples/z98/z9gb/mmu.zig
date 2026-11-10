// mmu.zig — z9gb 64 KiB bus, IO routing, and OAM DMA.
//
// The 64 KiB address space is covered by a 256-entry page table of 256-byte
// pages. Every access is one table index plus a kind switch plus a direct
// `base[addr & 0xFF]`; there is no per-access mapping arithmetic. Echo pages
// alias WRAM through their bases, and cartridge windows are rebased whenever
// an MBC register write changes the cached bank offsets.

const cartmod = @import("cart.zig");
const timermod = @import("timer.zig");
const serialmod = @import("serial.zig");
const apumod = @import("apu.zig");

pub const PageKind = enum(u8) { rom0, romx, vram, cart_ram, rtc, wram, echo, oam, io, hram };

pub const Page = struct { kind: PageKind, base: [*]u8 };

pub const Dma = struct {
    active: bool,
    source: u16,
    index: u16,
    dots: u32,
};

pub const Bus = struct {
    pages: [256]Page,
    wram: [8192]u8,
    vram: [8192]u8,
    oam: [160]u8,
    hram: [127]u8,
    io: [128]u8,
    stub: [256]u8,
    cart: *cartmod.Cart,
    ie: u8,
    dma: Dma,
    timer: timermod.Timer,
    serial: serialmod.Serial,
    apu: apumod.Apu,
    lyc_dirty: bool,
    ppu_oam_blocked: bool,
    ppu_vram_blocked: bool,
};

fn stubBase(self: *Bus) [*]u8 {
    return @ptrCast([*]u8, &self.stub[0]);
}

fn rebuildCartPages(self: *Bus) void {
    const wram_base: [*]u8 = @ptrCast([*]u8, &self.wram[0]);
    const ram_base: [*]u8 = @ptrCast([*]u8, &self.cart.ram[0]);
    const stub_base: [*]u8 = stubBase(self);
    const have_rom: bool = self.cart.rom.len != 0;
    const rom_base: [*]u8 = if (have_rom) @ptrCast([*]u8, self.cart.rom.ptr) else wram_base;

    var i: usize = 0;
    while (i < 0x40) : (i += 1) {
        const base: [*]u8 = if (have_rom) rom_base + self.cart.rom0_off + i * 256 else wram_base;
        self.pages[i] = Page{ .kind = .rom0, .base = base };
    }
    i = 0;
    while (i < 0x40) : (i += 1) {
        const base: [*]u8 = if (have_rom) rom_base + self.cart.romx_off + i * 256 else wram_base;
        self.pages[0x40 + i] = Page{ .kind = .romx, .base = base };
    }
    i = 0;
    const rtc_window: bool = self.cart.mbc == .mbc3 and self.cart.ram_bank >= 8;
    while (i < 0x20) : (i += 1) {
        if (rtc_window) {
            self.pages[0xA0 + i] = Page{ .kind = .rtc, .base = stub_base };
            continue;
        }
        const off: usize = self.cart.ram_off + i * 256;
        var base: [*]u8 = stub_base;
        if (self.cart.ram_enable and self.cart.ram_size != 0 and off < self.cart.ram_size) {
            base = ram_base + off;
        }
        self.pages[0xA0 + i] = Page{ .kind = .cart_ram, .base = base };
    }
}

pub fn busInit(bus: *Bus, cart: *cartmod.Cart) void {
    bus.cart = cart;
    bus.ie = 0;
    bus.lyc_dirty = false;
    bus.ppu_oam_blocked = false;
    bus.ppu_vram_blocked = false;
    bus.dma.active = false;
    bus.dma.source = 0;
    bus.dma.index = 0;
    bus.dma.dots = 0;

    var i: usize = 0;
    while (i < 8192) : (i += 1) {
        bus.wram[i] = 0;
        bus.vram[i] = 0;
    }
    i = 0;
    while (i < 160) : (i += 1) {
        bus.oam[i] = 0;
    }
    i = 0;
    while (i < 127) : (i += 1) {
        bus.hram[i] = 0;
    }
    i = 0;
    while (i < 128) : (i += 1) {
        bus.io[i] = 0;
    }
    i = 0;
    while (i < 256) : (i += 1) {
        bus.stub[i] = 0xFF;
    }

    bus.timer.divider = 0;
    bus.timer.tima = 0;
    bus.timer.tma = 0;
    bus.timer.tac = 0;
    bus.timer.reload = 0;
    serialmod.serialReset(&bus.serial);
    apumod.apuReset(&bus.apu, 44100);

    const wram_base: [*]u8 = @ptrCast([*]u8, &bus.wram[0]);
    const vram_base: [*]u8 = @ptrCast([*]u8, &bus.vram[0]);
    const oam_base: [*]u8 = @ptrCast([*]u8, &bus.oam[0]);
    const hram_base: [*]u8 = @ptrCast([*]u8, &bus.hram[0]);

    i = 0;
    while (i < 256) : (i += 1) {
        bus.pages[i] = Page{ .kind = .io, .base = wram_base };
    }

    i = 0;
    while (i < 0x20) : (i += 1) {
        bus.pages[0x80 + i] = Page{ .kind = .vram, .base = vram_base + i * 256 };
    }
    i = 0;
    while (i < 0x20) : (i += 1) {
        bus.pages[0xC0 + i] = Page{ .kind = .wram, .base = wram_base + i * 256 };
    }
    i = 0;
    while (i < 0x1E) : (i += 1) {
        bus.pages[0xE0 + i] = Page{ .kind = .echo, .base = wram_base + i * 256 };
    }
    bus.pages[0xFE] = Page{ .kind = .oam, .base = oam_base };
    bus.pages[0xFF] = Page{ .kind = .hram, .base = hram_base - 0x80 };

    rebuildCartPages(bus);

    bus.io[0x00] = 0xCF;
    bus.io[0x0F] = 0xE1;
    bus.io[0x40] = 0x91;
    bus.io[0x44] = 0x91;
    bus.io[0x47] = 0xFC;
    bus.io[0x48] = 0xFF;
    bus.io[0x49] = 0xFF;
    bus.io[0x4A] = 0x00;
    bus.io[0x4B] = 0x00;
}

pub fn busRaiseIrq(bus: *Bus, mask: u8) void {
    bus.io[0x0F] |= mask;
}

pub fn ioRead(self: *Bus, addr: u16) u8 {
    if (addr == 0xFF01) return self.serial.sb;
    if (addr == 0xFF02) return self.serial.sc;
    if (addr >= 0xFF04 and addr <= 0xFF07) return timermod.timerRead(&self.timer, addr);
    if (addr >= 0xFF10 and addr <= 0xFF3F) return apumod.apuRead(&self.apu, addr);
    return self.io[@intCast(usize, addr & 0x7F)];
}

pub fn ioWrite(self: *Bus, addr: u16, value: u8) void {
    if (addr == 0xFF01 or addr == 0xFF02) {
        serialmod.serialWrite(&self.serial, addr, value, self);
        return;
    }
    if (addr >= 0xFF04 and addr <= 0xFF07) {
        timermod.timerWrite(&self.timer, addr, value, self);
        return;
    }
    if (addr >= 0xFF10 and addr <= 0xFF3F) {
        apumod.apuWrite(&self.apu, addr, value);
        return;
    }
    if (addr == 0xFF46) {
        self.io[0x46] = value;
        self.dma.active = true;
        self.dma.source = @intCast(u16, value) << 8;
        self.dma.index = 0;
        self.dma.dots = 0;
        return;
    }
    if (addr == 0xFF45) self.lyc_dirty = true;
    self.io[@intCast(usize, addr & 0x7F)] = value;
}

fn readRaw(self: *Bus, addr: u16) u8 {
    if (addr == 0xFFFF) return self.ie;
    const page: Page = self.pages[@intCast(usize, addr >> 8)];
    const off: usize = @intCast(usize, addr & 0xFF);
    switch (page.kind) {
        .rom0, .romx, .cart_ram, .wram, .vram, .echo => return page.base[off],
        .rtc => {
            if (!self.cart.ram_enable) return 0xFF;
            const reg: u8 = self.cart.ram_bank - 8;
            return cartmod.rtcRead(self.cart, reg);
        },
        .oam => {
            if (off >= 0xA0) return 0xFF;
            return page.base[off];
        },
        .hram => {
            if (addr < 0xFF80) return ioRead(self, addr);
            return page.base[off];
        },
        .io => return ioRead(self, addr),
        else => unreachable,
    }
}

fn writeRaw(self: *Bus, addr: u16, value: u8) void {
    if (addr == 0xFFFF) {
        self.ie = value;
        return;
    }
    const page: Page = self.pages[@intCast(usize, addr >> 8)];
    const off: usize = @intCast(usize, addr & 0xFF);
    switch (page.kind) {
        .rom0, .romx => {
            cartmod.cartWrite(self.cart, addr, value);
            rebuildCartPages(self);
        },
        .cart_ram => {
            const stub_base: [*]u8 = stubBase(self);
            if (page.base != stub_base) page.base[off] = value;
        },
        .rtc => {
            if (!self.cart.ram_enable) return;
            const reg: u8 = self.cart.ram_bank - 8;
            cartmod.rtcWrite(self.cart, reg, value);
        },
        .wram, .vram, .echo => page.base[off] = value,
        .oam => {
            if (off < 0xA0) page.base[off] = value;
        },
        .hram => {
            if (addr >= 0xFF80) {
                page.base[off] = value;
            } else {
                ioWrite(self, addr, value);
            }
        },
        .io => ioWrite(self, addr, value),
        else => unreachable,
    }
}

pub fn read8(self: *Bus, addr: u16) u8 {
    if (self.dma.active) {
        if (addr >= 0xFF80 and addr <= 0xFFFE) {
            return self.pages[0xFF].base[@intCast(usize, addr & 0xFF)];
        }
        return 0xFF;
    }
    if (self.ppu_oam_blocked and addr >= 0xFE00 and addr <= 0xFE9F) return 0xFF;
    if (self.ppu_vram_blocked and addr >= 0x8000 and addr <= 0x9FFF) return 0xFF;
    return readRaw(self, addr);
}

pub fn write8(self: *Bus, addr: u16, value: u8) void {
    if (self.dma.active) {
        if (addr >= 0xFF80 and addr <= 0xFFFE) {
            self.pages[0xFF].base[@intCast(usize, addr & 0xFF)] = value;
        }
        return;
    }
    if (self.ppu_oam_blocked and addr >= 0xFE00 and addr <= 0xFE9F) return;
    if (self.ppu_vram_blocked and addr >= 0x8000 and addr <= 0x9FFF) return;
    writeRaw(self, addr, value);
}

pub fn busTick(self: *Bus, cycles: u32) void {
    timermod.timerTick(&self.timer, cycles, self);
    serialmod.serialTick(&self.serial, cycles, self);
    apumod.apuTick(&self.apu, cycles);
    if (!self.dma.active) return;
    self.dma.dots +%= cycles;
    while (self.dma.active and self.dma.dots >= 4) {
        self.dma.dots -= 4;
        const idx: usize = @intCast(usize, self.dma.index);
        const src_addr: u16 = self.dma.source +% @intCast(u16, idx);
        const value: u8 = readRaw(self, src_addr);
        self.oam[idx] = value;
        self.dma.index = @intCast(u16, idx + 1);
        if (self.dma.index >= 160) self.dma.active = false;
    }
}

pub fn read16(self: *Bus, addr: u16) u16 {
    const lo: u16 = @intCast(u16, read8(self, addr));
    const hi: u16 = @intCast(u16, read8(self, addr +% 1));
    return lo | (hi << 8);
}

pub fn write16(self: *Bus, addr: u16, value: u16) void {
    write8(self, addr, @intCast(u8, value & 0xFF));
    write8(self, addr +% 1, @intCast(u8, value >> 8));
}
