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

pub const Hdma = struct {
    source: u16,
    dest: u16,
    blocks: u16,
    active: bool,
    hblank: bool,
    vram_bank: u8,
    block_busy: bool,
    dots: u32,
    cpu_halt_cycles: u32,
};

pub const Bus = struct {
    pages: [256]Page,
    wram: [32768]u8,
    vram: [16384]u8,
    vram_bank: u8,
    wram_bank: u8,
    cgb_hw: bool,
    cgb_color: bool,
    cgb_compat: bool,
    double_speed: bool,
    bcps: u8,
    bcpd: [64]u8,
    ocps: u8,
    ocpd: [64]u8,
    cram_rgb: [64]u32,
    opri: u8,
    oam: [160]u8,
    hram: [127]u8,
    io: [128]u8,
    stub: [256]u8,
    cart: *cartmod.Cart,
    ie: u8,
    dma: Dma,
    hdma: Hdma,
    cpu_halted: bool,
    timer: timermod.Timer,
    serial: serialmod.Serial,
    apu: apumod.Apu,
    buttons: u8,
    lyc_dirty: bool,
    ppu_oam_blocked: bool,
    ppu_vram_blocked: bool,
    ppu_palette_blocked: bool,
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

fn rebuildVramPages(self: *Bus) void {
    const vram_base: [*]u8 = @ptrCast([*]u8, &self.vram[0]);
    const bank_base: [*]u8 = vram_base + @as(usize, self.vram_bank) * 0x2000;
    var i: usize = 0;
    while (i < 0x20) : (i += 1) {
        self.pages[0x80 + i] = Page{ .kind = .vram, .base = bank_base + i * 256 };
    }
}

fn rebuildWramPages(self: *Bus) void {
    const wram_base: [*]u8 = @ptrCast([*]u8, &self.wram[0]);
    const bank_base: [*]u8 = wram_base + @as(usize, self.wram_bank) * 0x1000;
    var i: usize = 0;
    while (i < 0x10) : (i += 1) {
        self.pages[0xC0 + i] = Page{ .kind = .wram, .base = wram_base + i * 256 };
        self.pages[0xE0 + i] = Page{ .kind = .echo, .base = wram_base + i * 256 };
    }
    i = 0;
    while (i < 0x10) : (i += 1) {
        self.pages[0xD0 + i] = Page{ .kind = .wram, .base = bank_base + i * 256 };
    }
    i = 0;
    while (i < 0x0E) : (i += 1) {
        self.pages[0xF0 + i] = Page{ .kind = .echo, .base = bank_base + i * 256 };
    }
}

pub fn mmuSetVramBank(b: *Bus, bank: u8) void {
    const value: u8 = bank & 0x01;
    if (b.vram_bank == value) return;
    b.vram_bank = value;
    rebuildVramPages(b);
}

pub fn mmuSetWramBank(b: *Bus, bank: u8) void {
    var value: u8 = bank & 0x07;
    if (value == 0) value = 1;
    if (b.wram_bank == value) return;
    b.wram_bank = value;
    rebuildWramPages(b);
}

pub fn mmuVramBank(b: *const Bus) u8 {
    return b.vram_bank;
}

pub fn mmuWramBank(b: *const Bus) u8 {
    return b.wram_bank;
}

fn cgbRgb(word: u16) u32 {
    const w: u32 = @intCast(u32, word);
    const r5: u32 = w & 0x1F;
    const g5: u32 = (w >> 5) & 0x1F;
    const b5: u32 = (w >> 10) & 0x1F;
    const r8: u32 = (r5 << 3) | (r5 >> 2);
    const g8: u32 = (g5 << 3) | (g5 >> 2);
    const b8: u32 = (b5 << 3) | (b5 >> 2);
    return (r8 << 16) | (g8 << 8) | b8;
}

fn updateBgRgb(b: *Bus, color_idx: u16) void {
    const ci: usize = @intCast(usize, color_idx);
    const a: usize = ci * 2;
    const word: u16 = @as(u16, b.bcpd[a]) | (@as(u16, b.bcpd[a + 1]) << 8);
    b.cram_rgb[ci] = cgbRgb(word);
}

fn updateObjRgb(b: *Bus, color_idx: u16) void {
    const ci: usize = @intCast(usize, color_idx);
    const a: usize = ci * 2;
    const word: u16 = @as(u16, b.ocpd[a]) | (@as(u16, b.ocpd[a + 1]) << 8);
    b.cram_rgb[32 + ci] = cgbRgb(word);
}

fn cgbIncrement(index: *u8) void {
    const low: u16 = (@as(u16, index.*) & 0x3F) + 1;
    index.* = (index.* & 0x80) | @intCast(u8, low & 0x3F);
}

pub fn cgbSpeedSwitch(b: *Bus) bool {
    if (!b.cgb_color) return false;
    if ((b.io[0x4D] & 0x01) == 0) return false;
    b.double_speed = !b.double_speed;
    b.io[0x4D] = 0;
    return true;
}

pub fn cgbIsDoubleSpeed(b: *const Bus) bool {
    return b.double_speed;
}

pub fn cgbPaletteReset(b: *Bus) void {
    b.bcps = 0;
    b.ocps = 0;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const byte: u8 = if ((i & 1) == 0) 0xFF else 0x7F;
        b.bcpd[i] = byte;
        b.ocpd[i] = byte;
        b.cram_rgb[i] = 0x00FFFFFF;
    }
}

pub fn cgbPaletteRead(b: *Bus, addr: u16) u8 {
    switch (addr) {
        0xFF68 => return b.bcps,
        0xFF69 => {
            if (b.ppu_palette_blocked) return 0xFF;
            return b.bcpd[@intCast(usize, b.bcps & 0x3F)];
        },
        0xFF6A => return b.ocps,
        0xFF6B => {
            if (b.ppu_palette_blocked) return 0xFF;
            return b.ocpd[@intCast(usize, b.ocps & 0x3F)];
        },
        else => return 0xFF,
    }
}

pub fn cgbPaletteWrite(b: *Bus, addr: u16, value: u8) void {
    switch (addr) {
        0xFF68 => b.bcps = value,
        0xFF69 => {
            if (b.ppu_palette_blocked) {
                if ((b.bcps & 0x80) != 0) cgbIncrement(&b.bcps);
                return;
            }
            const idx: u8 = b.bcps & 0x3F;
            b.bcpd[@intCast(usize, idx)] = value;
            updateBgRgb(b, @intCast(u16, idx) >> 1);
            if ((b.bcps & 0x80) != 0) cgbIncrement(&b.bcps);
        },
        0xFF6A => b.ocps = value,
        0xFF6B => {
            if (b.ppu_palette_blocked) {
                if ((b.ocps & 0x80) != 0) cgbIncrement(&b.ocps);
                return;
            }
            const idx: u8 = b.ocps & 0x3F;
            b.ocpd[@intCast(usize, idx)] = value;
            updateObjRgb(b, @intCast(u16, idx) >> 1);
            if ((b.ocps & 0x80) != 0) cgbIncrement(&b.ocps);
        },
        else => {},
    }
}

const HDMA_BLOCK_DOTS: u32 = 32;

fn hdmaSource(bus: *const Bus) u16 {
    const hi: u16 = @intCast(u16, bus.io[0x51]);
    const lo: u16 = @intCast(u16, bus.io[0x52]);
    return ((hi << 8) | lo) & 0xFFF0;
}

fn hdmaDest(bus: *const Bus) u16 {
    const hi: u16 = @intCast(u16, bus.io[0x53]);
    const lo: u16 = @intCast(u16, bus.io[0x54]);
    return 0x8000 | (((hi << 8) | lo) & 0x1FF0);
}

fn hdmaVramWrite(bus: *Bus, addr: u16, value: u8) void {
    const off: u16 = (addr -% 0x8000) & 0x1FFF;
    const base: usize = @as(usize, bus.hdma.vram_bank) * 0x2000;
    bus.vram[base + @intCast(usize, off)] = value;
}

fn hdmaCopyBlock(bus: *Bus) void {
    var i: u16 = 0;
    while (i < 16) : (i += 1) {
        const src: u16 = bus.hdma.source +% i;
        const value: u8 = readRaw(bus, src);
        hdmaVramWrite(bus, bus.hdma.dest +% i, value);
    }
    bus.hdma.source +%= 16;
    bus.hdma.dest +%= 16;
    if (bus.hdma.blocks > 0) bus.hdma.blocks -= 1;
}

fn hdmaStart(bus: *Bus, value: u8) void {
    const blocks: u16 = @intCast(u16, value & 0x7F) + 1;
    bus.hdma.source = hdmaSource(bus);
    bus.hdma.dest = hdmaDest(bus);
    bus.hdma.blocks = blocks;
    bus.hdma.vram_bank = bus.vram_bank;
    bus.hdma.block_busy = false;
    bus.hdma.dots = 0;
    if ((value & 0x80) == 0) {
        bus.hdma.active = false;
        bus.hdma.hblank = false;
        var n: u16 = 0;
        while (n < blocks) : (n += 1) hdmaCopyBlock(bus);
        const per_block: u32 = if (bus.double_speed) 64 else 32;
        bus.hdma.cpu_halt_cycles +%= @intCast(u32, blocks) * per_block;
    } else {
        bus.hdma.active = true;
        bus.hdma.hblank = true;
    }
}

pub fn hdmaWrite(bus: *Bus, addr: u16, value: u8) void {
    if (!bus.cgb_color) return;
    if (addr == 0xFF55) {
        if (bus.hdma.active and (value & 0x80) == 0) {
            bus.hdma.active = false;
            bus.hdma.hblank = false;
            bus.hdma.block_busy = false;
            bus.hdma.dots = 0;
            return;
        }
        bus.io[0x55] = value;
        hdmaStart(bus, value);
        return;
    }
    if (addr >= 0xFF51 and addr <= 0xFF54) {
        bus.io[@intCast(usize, addr & 0x7F)] = value;
    }
}

pub fn hdmaRead(bus: *const Bus, addr: u16) u8 {
    if (!bus.cgb_color) return 0xFF;
    if (addr == 0xFF55) {
        if (bus.hdma.active) {
            return @intCast(u8, (bus.hdma.blocks -% 1) & 0x7F);
        }
        if (bus.hdma.blocks == 0) return 0xFF;
        return @intCast(u8, 0x80 | ((bus.hdma.blocks -% 1) & 0x7F));
    }
    if (addr >= 0xFF51 and addr <= 0xFF54) return bus.io[@intCast(usize, addr & 0x7F)];
    return 0xFF;
}

pub fn hdmaHBlank(bus: *Bus) void {
    if (!bus.hdma.active or !bus.hdma.hblank) return;
    if (bus.cpu_halted) return;
    if (bus.hdma.block_busy) return;
    bus.hdma.block_busy = true;
    bus.hdma.dots = 0;
}

pub fn hdmaLineEnd(bus: *Bus) void {
    bus.hdma.block_busy = false;
    bus.hdma.dots = 0;
}

pub fn hdmaTick(bus: *Bus, dots: u32) void {
    if (!bus.hdma.active or !bus.hdma.hblank) return;
    if (bus.cpu_halted) return;
    if (!bus.hdma.block_busy) return;
    bus.hdma.dots +%= dots;
    if (bus.hdma.dots >= HDMA_BLOCK_DOTS) {
        bus.hdma.dots -= HDMA_BLOCK_DOTS;
        hdmaCopyBlock(bus);
        const per_block: u32 = if (bus.double_speed) 64 else 32;
        bus.hdma.cpu_halt_cycles +%= per_block;
        bus.hdma.block_busy = false;
        if (bus.hdma.blocks == 0) {
            bus.hdma.active = false;
            bus.hdma.hblank = false;
            bus.hdma.dots = 0;
        }
    }
}

pub fn busInit(bus: *Bus, cart: *cartmod.Cart) void {
    bus.cart = cart;
    bus.ie = 0;
    bus.buttons = 0;
    bus.vram_bank = 0;
    bus.wram_bank = 1;
    bus.cgb_hw = false;
    bus.cgb_color = false;
    bus.cgb_compat = false;
    bus.double_speed = false;
    bus.bcps = 0;
    bus.ocps = 0;
    bus.opri = 0;
    bus.lyc_dirty = false;
    bus.ppu_oam_blocked = false;
    bus.ppu_vram_blocked = false;
    bus.ppu_palette_blocked = false;
    bus.dma.active = false;
    bus.dma.source = 0;
    bus.dma.index = 0;
    bus.dma.dots = 0;
    bus.hdma.source = 0;
    bus.hdma.dest = 0;
    bus.hdma.blocks = 0;
    bus.hdma.active = false;
    bus.hdma.hblank = false;
    bus.hdma.vram_bank = 0;
    bus.hdma.block_busy = false;
    bus.hdma.dots = 0;
    bus.hdma.cpu_halt_cycles = 0;
    bus.cpu_halted = false;

    var i: usize = 0;
    while (i < 32768) : (i += 1) {
        bus.wram[i] = 0;
    }
    i = 0;
    while (i < 16384) : (i += 1) {
        bus.vram[i] = 0;
    }
    i = 0;
    while (i < 64) : (i += 1) {
        const byte: u8 = if ((i & 1) == 0) 0xFF else 0x7F;
        bus.bcpd[i] = byte;
        bus.ocpd[i] = byte;
        bus.cram_rgb[i] = 0x00FFFFFF;
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
    const oam_base: [*]u8 = @ptrCast([*]u8, &bus.oam[0]);
    const hram_base: [*]u8 = @ptrCast([*]u8, &bus.hram[0]);

    i = 0;
    while (i < 256) : (i += 1) {
        bus.pages[i] = Page{ .kind = .io, .base = wram_base };
    }

    rebuildVramPages(bus);
    rebuildWramPages(bus);
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
    if (addr == 0xFF00) {
        var low: u8 = 0x0F;
        const sel: u8 = self.io[0];
        if ((sel & 0x20) == 0) {
            if ((self.buttons & 0x01) != 0) low &= 0xFE;
            if ((self.buttons & 0x02) != 0) low &= 0xFD;
            if ((self.buttons & 0x04) != 0) low &= 0xFB;
            if ((self.buttons & 0x08) != 0) low &= 0xF7;
        }
        if ((sel & 0x10) == 0) {
            if ((self.buttons & 0x10) != 0) low &= 0xFE;
            if ((self.buttons & 0x20) != 0) low &= 0xFD;
            if ((self.buttons & 0x40) != 0) low &= 0xFB;
            if ((self.buttons & 0x80) != 0) low &= 0xF7;
        }
        return 0xC0 | (sel & 0x30) | low;
    }
    if (addr == 0xFF01) return self.serial.sb;
    if (addr == 0xFF02) return self.serial.sc;
    if (addr >= 0xFF04 and addr <= 0xFF07) return timermod.timerRead(&self.timer, addr);
    if (addr >= 0xFF10 and addr <= 0xFF3F) return apumod.apuRead(&self.apu, addr);
    if (addr == 0xFF4F and self.cgb_color) return 0xFE | (self.vram_bank & 0x01);
    if (addr == 0xFF70 and self.cgb_color) return 0xF8 | (self.wram_bank & 0x07);
    if (addr >= 0xFF68 and addr <= 0xFF6B) {
        if (self.cgb_color) return cgbPaletteRead(self, addr);
        return 0xFF;
    }
    if (addr == 0xFF6C) {
        if (!self.cgb_hw) return 0xFF;
        if (self.cgb_compat) return 0x01;
        return 0xFE | (self.opri & 0x01);
    }
    if (addr >= 0xFF51 and addr <= 0xFF55) return hdmaRead(self, addr);
    if (addr == 0xFF4D) {
        if (!self.cgb_color) return 0xFF;
        var v: u8 = 0x7E;
        if (self.double_speed) v |= 0x80;
        if ((self.io[0x4D] & 0x01) != 0) v |= 0x01;
        return v;
    }
    return self.io[@intCast(usize, addr & 0x7F)];
}

pub fn ioWrite(self: *Bus, addr: u16, value: u8) void {
    if (addr == 0xFF00) {
        self.io[0] = (self.io[0] & 0xCF) | (value & 0x30);
        return;
    }
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
    if (addr == 0xFF4F) {
        if (self.cgb_color) mmuSetVramBank(self, value);
        self.io[0x4F] = value & 0x01;
        return;
    }
    if (addr == 0xFF70) {
        if (self.cgb_color) mmuSetWramBank(self, value);
        self.io[0x70] = value & 0x07;
        return;
    }
    if (addr >= 0xFF68 and addr <= 0xFF6B) {
        if (self.cgb_color) cgbPaletteWrite(self, addr, value);
        return;
    }
    if (addr == 0xFF6C) {
        if (self.cgb_color) self.opri = value & 0x01;
        return;
    }
    if (addr == 0xFF4D) {
        if (self.cgb_color) self.io[0x4D] = value & 0x01;
        return;
    }
    if (addr >= 0xFF51 and addr <= 0xFF55) {
        hdmaWrite(self, addr, value);
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

fn busTickDma(self: *Bus, cycles: u32) void {
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

pub fn busTick(self: *Bus, cycles: u32) void {
    const real_cycles: u32 = if (self.double_speed) cycles / 2 else cycles;
    timermod.timerTick(&self.timer, cycles, self);
    serialmod.serialTick(&self.serial, cycles, self);
    apumod.apuTick(&self.apu, real_cycles);
    busTickDma(self, cycles);
    hdmaTick(self, real_cycles);
}

pub fn busTickStall(self: *Bus, cycles: u32) void {
    const real_cycles: u32 = if (self.double_speed) cycles / 2 else cycles;
    serialmod.serialTick(&self.serial, cycles, self);
    apumod.apuTick(&self.apu, real_cycles);
    busTickDma(self, cycles);
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
