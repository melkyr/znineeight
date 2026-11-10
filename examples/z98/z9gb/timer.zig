pub const Timer = struct {
    divider: u16,
    tima: u8,
    tma: u8,
    tac: u8,
    reload: u8,
    ifr: *u8,
};

fn selectedMask(tac: u8) u16 {
    const sel: u8 = tac & 0x03;
    if (sel == 0) return 0x0200;
    if (sel == 1) return 0x0008;
    if (sel == 2) return 0x0020;
    return 0x0080;
}

fn bumpTima(t: *Timer) void {
    if (t.reload != 0) return;
    if (t.tima == 0xFF) {
        t.tima = 0;
        t.reload = 16;
        return;
    }
    t.tima = @intCast(u8, (@as(u16, t.tima) + 1) & 0xFF);
}

pub fn timerTick(t: *Timer, cycles: u32) void {
    const mask: u16 = selectedMask(t.tac);
    var i: u32 = 0;
    while (i < cycles) : (i += 1) {
        t.divider = @intCast(u16, (@as(u32, t.divider) + 1) & 0xFFFF);
        if (t.reload != 0) {
            t.reload -= 1;
            if (t.reload == 0) {
                t.tima = t.tma;
                t.ifr.* |= 0x04;
            }
        } else {
            const selected: bool = (t.divider & mask) != 0;
            const previous: bool = ((t.divider -% 1) & mask) != 0;
            if ((t.tac & 0x04) != 0 and previous and !selected) {
                bumpTima(t);
            }
        }
    }
}

pub fn timerRead(t: *Timer, addr: u16) u8 {
    if (addr == 0xFF04) return @intCast(u8, t.divider >> 8);
    if (addr == 0xFF05) return t.tima;
    if (addr == 0xFF06) return t.tma;
    if (addr == 0xFF07) return @intCast(u8, (t.tac & 0x07) | 0xF8);
    return 0xFF;
}

pub fn timerWrite(t: *Timer, addr: u16, value: u8) void {
    if (addr == 0xFF04) {
        const mask: u16 = selectedMask(t.tac);
        const old: bool = (t.divider & mask) != 0;
        t.divider = 0;
        if ((t.tac & 0x04) != 0 and old) bumpTima(t);
        return;
    }
    if (addr == 0xFF05) {
        if (t.reload == 0) t.tima = value;
        return;
    }
    if (addr == 0xFF06) {
        t.tma = value;
        return;
    }
    if (addr == 0xFF07) {
        const old_mask: u16 = selectedMask(t.tac);
        const new_tac: u8 = value & 0x07;
        const new_mask: u16 = selectedMask(new_tac);
        var old_sig: bool = false;
        var new_sig: bool = false;
        if ((t.tac & 0x04) != 0) old_sig = (t.divider & old_mask) != 0;
        if ((new_tac & 0x04) != 0) new_sig = (t.divider & new_mask) != 0;
        t.tac = new_tac;
        if (old_sig and !new_sig) bumpTima(t);
    }
}
