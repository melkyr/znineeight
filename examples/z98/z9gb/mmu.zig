// mmu.zig — z9gb Bus skeleton (Task 2).
//
// The 64 KiB address space is covered by a 256-entry page table of 256-byte
// pages. Every access is one table index plus a kind switch plus a direct
// `base[addr & 0xFF]`; there is no per-access mapping arithmetic. Task 5 fills
// the VRAM/OAM/IO/echo windows and adds busTick.

const cartmod = @import("cart.zig");

pub const PageKind = enum(u8) { rom0, romx, vram, cart_ram, wram, echo, oam, io, hram };

pub const Page = struct { kind: PageKind, base: [*]u8 };

pub const Bus = struct {
    pages: [256]Page,
    wram: [8192]u8,
    hram: [127]u8,
    cart: *cartmod.Cart,
    ie: u8,
};

pub fn busInit(bus: *Bus, cart: *cartmod.Cart) void {
    bus.cart = cart;
    bus.ie = 0;

    const wram_base: [*]u8 = @ptrCast([*]u8, &bus.wram[0]);
    const hram_base: [*]u8 = @ptrCast([*]u8, &bus.hram[0]);

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        bus.pages[i] = Page{ .kind = .io, .base = wram_base };
    }

    const have_rom: bool = cart.rom.len != 0;
    const rom_base: [*]u8 = if (have_rom) @ptrCast([*]u8, cart.rom.ptr) else wram_base;
    i = 0;
    while (i < 0x40) : (i += 1) {
        const base: [*]u8 = if (have_rom) rom_base + cart.rom0_off + i * 256 else wram_base;
        bus.pages[i] = Page{ .kind = .rom0, .base = base };
    }
    i = 0;
    while (i < 0x40) : (i += 1) {
        const base: [*]u8 = if (have_rom) rom_base + cart.romx_off + i * 256 else wram_base;
        bus.pages[0x40 + i] = Page{ .kind = .romx, .base = base };
    }

    const ram_base: [*]u8 = @ptrCast([*]u8, &cart.ram[0]);
    i = 0;
    while (i < 0x20) : (i += 1) {
        bus.pages[0xA0 + i] = Page{ .kind = .cart_ram, .base = ram_base + cart.ram_off + i * 256 };
    }

    i = 0;
    while (i < 0x20) : (i += 1) {
        bus.pages[0xC0 + i] = Page{ .kind = .wram, .base = wram_base + i * 256 };
    }

    bus.pages[0xFF] = Page{ .kind = .hram, .base = hram_base - 0x80 };
}

pub fn read8(self: *Bus, addr: u16) u8 {
    if (addr == 0xFFFF) return self.ie;
    const page: Page = self.pages[@intCast(usize, addr >> 8)];
    const off: usize = @intCast(usize, addr & 0xFF);
    switch (page.kind) {
        .rom0, .romx => return page.base[off],
        .cart_ram => return cartmod.cartRead(self.cart, addr),
        .wram, .vram, .echo, .oam => return page.base[off],
        .hram => {
            if (addr < 0xFF80) return 0xFF;
            return page.base[off];
        },
        .io => return 0xFF,
        else => unreachable,
    }
}

pub fn write8(self: *Bus, addr: u16, value: u8) void {
    if (addr == 0xFFFF) {
        self.ie = value;
        return;
    }
    const page: Page = self.pages[@intCast(usize, addr >> 8)];
    const off: usize = @intCast(usize, addr & 0xFF);
    switch (page.kind) {
        .rom0, .romx => cartmod.cartWrite(self.cart, addr, value),
        .cart_ram => cartmod.cartWrite(self.cart, addr, value),
        .wram, .vram, .echo, .oam => page.base[off] = value,
        .hram => {
            if (addr >= 0xFF80) page.base[off] = value;
        },
        .io => {},
        else => unreachable,
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
