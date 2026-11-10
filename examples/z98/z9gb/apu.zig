// apu.zig — z9gb DMG APU: four channels, frame sequencer, mixer, and ring.
//
// Pure Z98 free functions only. All storage (channels, wave RAM, LUTs, and the
// 32,768-entry i16 stereo ring) is fixed/static; no heap and no large stack
// locals. The APU is ticked from `busTick`, so channel dividers and the frame
// sequencer consume the same T-cycles as the CPU.
//
// Output is stereo signed 16-bit PCM. Samples are emitted by a 16.16
// fixed-point cycle accumulator at the requested sample rate; there is no host
// time and no floating point.

const FS_PERIOD: u32 = 8192;
const RING_CAP: usize = 32768;
const RING_MASK: u32 = 32767;

const DUTY_LUT: [4][8]u8 = [4][8]u8{
    [8]u8{ 0, 0, 0, 0, 0, 0, 0, 1 },
    [8]u8{ 1, 0, 0, 0, 0, 0, 0, 1 },
    [8]u8{ 1, 0, 0, 0, 0, 1, 1, 1 },
    [8]u8{ 0, 1, 1, 1, 1, 1, 1, 0 },
};

// Centered digital levels: volume d maps to -15..15 (digital 0 is analog high,
// matching the DMG DAC inversion).
const VOL_LUT: [16][4]i32 = [16][4]i32{
    [4]i32{ -15, -15, -15, -15 },
    [4]i32{ -13, -13, -13, -13 },
    [4]i32{ -11, -11, -11, -11 },
    [4]i32{ -9, -9, -9, -9 },
    [4]i32{ -7, -7, -7, -7 },
    [4]i32{ -5, -5, -5, -5 },
    [4]i32{ -3, -3, -3, -3 },
    [4]i32{ -1, -1, -1, -1 },
    [4]i32{ 1, 1, 1, 1 },
    [4]i32{ 3, 3, 3, 3 },
    [4]i32{ 5, 5, 5, 5 },
    [4]i32{ 7, 7, 7, 7 },
    [4]i32{ 9, 9, 9, 9 },
    [4]i32{ 11, 11, 11, 11 },
    [4]i32{ 13, 13, 13, 13 },
    [4]i32{ 15, 15, 15, 15 },
};

const WAVE_LUT: [16]u8 = [16]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };

const POW2_LUT: [8]u32 = [8]u32{ 1, 2, 4, 8, 16, 32, 64, 128 };

pub const Square = struct {
    enabled: bool,
    dac: bool,
    length: u16,
    length_en: bool,
    freq: u16,
    timer: u32,
    duty_pos: u8,
    duty: u8,
    vol: u8,
    vol_init: u8,
    env_sub: bool,
    env_period: u8,
    env_timer: u8,
};

pub const Wave = struct {
    enabled: bool,
    dac: bool,
    length: u16,
    length_en: bool,
    freq: u16,
    timer: u32,
    sample_index: u8,
    sample_byte: u8,
    just_read: bool,
    vol_code: u8,
};

pub const Noise = struct {
    enabled: bool,
    dac: bool,
    length: u16,
    length_en: bool,
    timer: u32,
    lfsr: u16,
    width7: bool,
    shift: u8,
    divisor: u8,
    vol: u8,
    vol_init: u8,
    env_sub: bool,
    env_period: u8,
    env_timer: u8,
};

pub const Apu = struct {
    powered: bool,
    sample_rate: u32,
    sample_inc: u32,
    sample_acc: u64,
    fs_step: u8,
    fs_cycles: u32,
    regs: [23]u8,
    ch1: Square,
    ch2: Square,
    ch3: Wave,
    ch4: Noise,
    sweep_period: u8,
    sweep_sub: bool,
    sweep_shift: u8,
    sweep_shadow: u16,
    sweep_timer: u8,
    sweep_enabled: bool,
    sweep_negate_used: bool,
    nr50: u8,
    nr51: u8,
    wave_ram: [16]u8,
    ring: [RING_CAP]i16,
    ring_head: u32,
    ring_tail: u32,
    ring_count: u32,
    dc_l: i32,
    dc_r: i32,
};

fn clearSquare(ch: *Square) void {
    ch.enabled = false;
    ch.dac = false;
    ch.length = 0;
    ch.length_en = false;
    ch.freq = 0;
    ch.timer = 0;
    ch.duty_pos = 0;
    ch.duty = 0;
    ch.vol = 0;
    ch.vol_init = 0;
    ch.env_sub = false;
    ch.env_period = 0;
    ch.env_timer = 0;
}

fn clearWave(ch: *Wave) void {
    ch.enabled = false;
    ch.dac = false;
    ch.length = 0;
    ch.length_en = false;
    ch.freq = 0;
    ch.timer = 0;
    ch.sample_index = 0;
    ch.sample_byte = 0;
    ch.just_read = false;
    ch.vol_code = 0;
}

fn clearNoise(ch: *Noise) void {
    ch.enabled = false;
    ch.dac = false;
    ch.length = 0;
    ch.length_en = false;
    ch.timer = 0;
    ch.lfsr = 0x7FFF;
    ch.width7 = false;
    ch.shift = 0;
    ch.divisor = 0;
    ch.vol = 0;
    ch.vol_init = 0;
    ch.env_sub = false;
    ch.env_period = 0;
    ch.env_timer = 0;
}

fn clearControl(a: *Apu) void {
    var i: usize = 0;
    while (i < 23) : (i += 1) a.regs[i] = 0;
    clearSquare(&a.ch1);
    clearSquare(&a.ch2);
    clearWave(&a.ch3);
    clearNoise(&a.ch4);
    a.sweep_period = 0;
    a.sweep_sub = false;
    a.sweep_shift = 0;
    a.sweep_shadow = 0;
    a.sweep_timer = 0;
    a.sweep_enabled = false;
    a.sweep_negate_used = false;
    a.nr50 = 0;
    a.nr51 = 0;
    a.ch3.sample_byte = 0;
}

pub fn apuReset(a: *Apu, sample_rate: u32) void {
    a.powered = true;
    a.sample_rate = sample_rate;
    a.sample_inc = 6233059;
    if (sample_rate != 0) {
        a.sample_inc = @intCast(u32, (@as(u64, 4194304) * 65536) / @as(u64, sample_rate));
    }
    a.sample_acc = 0;
    a.fs_step = 0;
    a.fs_cycles = 0;
    clearControl(a);
    var i: usize = 0;
    while (i < 16) : (i += 1) a.wave_ram[i] = 0;
    a.ring_head = 0;
    a.ring_tail = 0;
    a.ring_count = 0;
    a.dc_l = 0;
    a.dc_r = 0;
}

fn maskFor(addr: u16) u8 {
    const idx: u8 = @intCast(u8, addr - 0xFF10);
    switch (idx) {
        0 => return 0x80,
        1 => return 0x3F,
        2 => return 0x00,
        3 => return 0xFF,
        4 => return 0xBF,
        5 => return 0xFF,
        6 => return 0x3F,
        7 => return 0x00,
        8 => return 0xFF,
        9 => return 0xBF,
        10 => return 0x7F,
        11 => return 0xFF,
        12 => return 0x9F,
        13 => return 0xFF,
        14 => return 0xBF,
        15 => return 0xFF,
        16 => return 0xFF,
        17 => return 0x00,
        18 => return 0x00,
        19 => return 0xBF,
        20 => return 0x00,
        21 => return 0x00,
        22 => return 0x70,
        else => return 0xFF,
    }
}

pub fn apuRead(a: *Apu, addr: u16) u8 {
    if (addr >= 0xFF30 and addr <= 0xFF3F) {
        if (a.powered and a.ch3.enabled and a.ch3.dac) {
            if (!a.ch3.just_read) return 0xFF;
            const bi: usize = @intCast(usize, (a.ch3.sample_index >> 1) & 0x0F);
            return a.wave_ram[bi];
        }
        const wi: usize = @intCast(usize, (addr - 0xFF30) & 0x0F);
        return a.wave_ram[wi];
    }
    if (addr == 0xFF26) {
        var v: u8 = 0x70;
        if (a.powered) {
            v |= 0x80;
            if (a.ch1.enabled) v |= 0x01;
            if (a.ch2.enabled) v |= 0x02;
            if (a.ch3.enabled) v |= 0x04;
            if (a.ch4.enabled) v |= 0x08;
        }
        return v;
    }
    if (addr >= 0xFF10 and addr <= 0xFF25) {
        const idx: usize = @intCast(usize, addr - 0xFF10);
        const base: u8 = if (a.powered) a.regs[idx] else 0;
        return base | maskFor(addr);
    }
    return 0xFF;
}

fn clearControlKeepLengths(a: *Apu) void {
    const l1: u16 = a.ch1.length;
    const l2: u16 = a.ch2.length;
    const l3: u16 = a.ch3.length;
    const l4: u16 = a.ch4.length;
    clearControl(a);
    a.ch1.length = l1;
    a.ch2.length = l2;
    a.ch3.length = l3;
    a.ch4.length = l4;
}

fn writeNr52(a: *Apu, value: u8) void {
    const on: bool = (value & 0x80) != 0;
    if (!on) {
        a.powered = false;
        clearControlKeepLengths(a);
        a.fs_step = 0;
        a.fs_cycles = 0;
        return;
    }
    if (!a.powered) {
        a.powered = true;
        clearControlKeepLengths(a);
        a.fs_step = 0;
        a.fs_cycles = 0;
    }
}

fn squarePeriod(ch: *const Square) u32 {
    return (@as(u32, 2048) - (@as(u32, ch.freq) & 0x7FF)) * 32;
}

fn wavePeriod(freq: u16) u32 {
    return (@as(u32, 2048) - (@as(u32, freq) & 0x7FF)) * 2;
}

fn noisePeriod(ch: *const Noise) u32 {
    if (ch.shift >= 14) return 0xFFFFFFFF;
    var div: u32 = @as(u32, ch.divisor) * 16;
    if (ch.divisor == 0) div = 8;
    return div << @intCast(u5, ch.shift);
}

fn tickSquare(ch: *Square, cycles: u32) void {
    if (!ch.enabled or !ch.dac) return;
    var rem: u32 = cycles;
    var guard: u32 = 0;
    while (true) {
        if (ch.timer == 0) ch.timer = squarePeriod(ch);
        if (rem < ch.timer) {
            ch.timer -= rem;
            return;
        }
        rem -= ch.timer;
        ch.duty_pos = @intCast(u8, (@as(u16, ch.duty_pos) + 1) & 7);
        ch.timer = squarePeriod(ch);
        if (rem == 0) return;
        guard += 1;
        if (guard > 100000) return;
    }
}

fn tickWave(a: *Apu, cycles: u32) void {
    a.ch3.just_read = false;
    if (!a.ch3.enabled or !a.ch3.dac) return;
    var rem: u32 = cycles;
    var guard: u32 = 0;
    while (true) {
        if (a.ch3.timer == 0) a.ch3.timer = wavePeriod(a.ch3.freq);
        if (rem < a.ch3.timer) {
            a.ch3.timer -= rem;
            return;
        }
        rem -= a.ch3.timer;
        a.ch3.sample_index = @intCast(u8, (@as(u16, a.ch3.sample_index) + 1) & 0x1F);
        const bi: usize = @intCast(usize, a.ch3.sample_index >> 1);
        a.ch3.sample_byte = a.wave_ram[bi];
        a.ch3.timer = wavePeriod(a.ch3.freq);
        if (rem == 0) {
            a.ch3.just_read = true;
            return;
        }
        a.ch3.just_read = false;
        guard += 1;
        if (guard > 100000) return;
    }
}

fn tickNoise(ch: *Noise, cycles: u32) void {
    if (!ch.enabled or !ch.dac) return;
    var rem: u32 = cycles;
    var guard: u32 = 0;
    while (true) {
        if (ch.timer == 0) ch.timer = noisePeriod(ch);
        if (rem < ch.timer) {
            ch.timer -= rem;
            return;
        }
        rem -= ch.timer;
        var xor_bit: u16 = (ch.lfsr ^ (ch.lfsr >> 1)) & 1;
        ch.lfsr = (ch.lfsr >> 1) | (xor_bit << 14);
        if (ch.width7) ch.lfsr = (ch.lfsr & 0xFFBF) | (xor_bit << 6);
        ch.lfsr &= 0x7FFF;
        ch.timer = noisePeriod(ch);
        if (rem == 0) return;
        guard += 1;
        if (guard > 100000) return;
    }
}

fn clockLengthSquare(ch: *Square) void {
    if (!ch.length_en or ch.length == 0) return;
    ch.length -= 1;
    if (ch.length == 0) ch.enabled = false;
}

fn clockLengthWave(ch: *Wave) void {
    if (!ch.length_en or ch.length == 0) return;
    ch.length -= 1;
    if (ch.length == 0) ch.enabled = false;
}

fn clockLengthNoise(ch: *Noise) void {
    if (!ch.length_en or ch.length == 0) return;
    ch.length -= 1;
    if (ch.length == 0) ch.enabled = false;
}

fn clockEnvelopeSquare(ch: *Square) void {
    if (ch.env_timer > 0) ch.env_timer -= 1;
    if (ch.env_timer != 0) return;
    ch.env_timer = if (ch.env_period == 0) 8 else ch.env_period;
    if (ch.env_sub) {
        if (ch.vol > 0) ch.vol -= 1;
    } else {
        if (ch.vol < 15) ch.vol += 1;
    }
}

fn clockEnvelopeNoise(ch: *Noise) void {
    if (ch.env_timer > 0) ch.env_timer -= 1;
    if (ch.env_timer != 0) return;
    ch.env_timer = if (ch.env_period == 0) 8 else ch.env_period;
    if (ch.env_sub) {
        if (ch.vol > 0) ch.vol -= 1;
    } else {
        if (ch.vol < 15) ch.vol += 1;
    }
}

fn sweepCalcOverflow(a: *Apu) bool {
    const sh: usize = @intCast(usize, a.sweep_shift & 7);
    const delta: u32 = @as(u32, a.sweep_shadow) / POW2_LUT[sh];
    var nv: u32 = 0;
    if (a.sweep_sub) {
        a.sweep_negate_used = true;
        if (delta > @as(u32, a.sweep_shadow)) return true;
        nv = @as(u32, a.sweep_shadow) - delta;
    } else {
        nv = @as(u32, a.sweep_shadow) + delta;
    }
    return nv > 0x7FF;
}

fn sweepUpdate(a: *Apu) void {
    if (sweepCalcOverflow(a)) {
        a.ch1.enabled = false;
        return;
    }
    if (a.sweep_shift == 0) return;
    const sh: usize = @intCast(usize, a.sweep_shift & 7);
    const delta: u32 = @as(u32, a.sweep_shadow) / POW2_LUT[sh];
    var nv: u32 = 0;
    if (a.sweep_sub) {
        if (delta > @as(u32, a.sweep_shadow)) {
            a.ch1.enabled = false;
            return;
        }
        nv = @as(u32, a.sweep_shadow) - delta;
    } else {
        nv = @as(u32, a.sweep_shadow) + delta;
    }
    a.sweep_shadow = @intCast(u16, nv & 0x7FF);
    a.ch1.freq = @intCast(u16, nv & 0x7FF);
    if (sweepCalcOverflow(a)) a.ch1.enabled = false;
}

fn clockSweep(a: *Apu) void {
    if (a.sweep_timer > 0) a.sweep_timer -= 1;
    if (a.sweep_timer != 0) return;
    a.sweep_timer = if (a.sweep_period == 0) 8 else a.sweep_period;
    if (!a.sweep_enabled or a.sweep_period == 0) return;
    sweepUpdate(a);
}

fn runFsStep(a: *Apu, step: u8) void {
    if ((step & 1) == 0) {
        clockLengthSquare(&a.ch1);
        clockLengthSquare(&a.ch2);
        clockLengthWave(&a.ch3);
        clockLengthNoise(&a.ch4);
    }
    if (step == 2 or step == 6) clockSweep(a);
    if (step == 7) {
        clockEnvelopeSquare(&a.ch1);
        clockEnvelopeSquare(&a.ch2);
        clockEnvelopeNoise(&a.ch4);
    }
}

fn tickFs(a: *Apu, cycles: u32) void {
    a.fs_cycles += cycles;
    while (a.fs_cycles >= FS_PERIOD) {
        a.fs_cycles -= FS_PERIOD;
        const step: u8 = a.fs_step & 7;
        a.fs_step = @intCast(u8, (@as(u16, step) + 1) & 7);
        runFsStep(a, step);
    }
}

fn triggerSweep(a: *Apu) void {
    a.sweep_shadow = @intCast(u16, a.ch1.freq & 0x7FF);
    a.sweep_timer = if (a.sweep_period == 0) 8 else a.sweep_period;
    a.sweep_enabled = (a.sweep_period != 0) or (a.sweep_shift != 0);
    a.sweep_negate_used = false;
    if (a.sweep_shift != 0) {
        if (sweepCalcOverflow(a)) a.ch1.enabled = false;
    }
}

fn triggerSquare(a: *Apu, ch: *Square, is_ch1: bool, value: u8) void {
    const old_en: bool = ch.length_en;
    const new_en: bool = (value & 0x40) != 0;
    const trigger: bool = (value & 0x80) != 0;
    const quirk: bool = (a.fs_step & 1) != 0;
    if (new_en and !old_en and quirk and ch.length != 0) {
        ch.length -= 1;
        if (ch.length == 0 and !trigger) ch.enabled = false;
    }
    if (trigger) {
        if (ch.length == 0) {
            ch.length = 64;
            if (new_en and quirk) ch.length -= 1;
        }
        ch.enabled = ch.dac;
        ch.timer = squarePeriod(ch);
        ch.duty_pos = 0;
        ch.vol = ch.vol_init;
        ch.env_timer = if (ch.env_period == 0) 8 else ch.env_period;
        if (is_ch1) triggerSweep(a);
    }
    ch.length_en = new_en;
}

fn corruptWave(a: *Apu) void {
    const off: usize = @intCast(usize, ((@as(u16, a.ch3.sample_index) + 1) >> 1) & 0x0F);
    if (off < 4) {
        a.wave_ram[0] = a.wave_ram[off];
        return;
    }
    const src: usize = off & 0x0C;
    var i: usize = 0;
    while (i < 4) : (i += 1) a.wave_ram[i] = a.wave_ram[src + i];
}

fn triggerWave(a: *Apu, value: u8) void {
    const old_en: bool = a.ch3.length_en;
    const new_en: bool = (value & 0x40) != 0;
    const trigger: bool = (value & 0x80) != 0;
    const quirk: bool = (a.fs_step & 1) != 0;
    if (new_en and !old_en and quirk and a.ch3.length != 0) {
        a.ch3.length -= 1;
        if (a.ch3.length == 0 and !trigger) a.ch3.enabled = false;
    }
    if (trigger) {
        // DMG corrupts wave RAM when a retrigger lands on the sample fetch.
        if (a.ch3.enabled and a.ch3.dac and a.ch3.timer == 2) corruptWave(a);
        if (a.ch3.length == 0) {
            a.ch3.length = 256;
            if (new_en and quirk) a.ch3.length -= 1;
        }
        a.ch3.sample_index = 0;
        // The first DMG wave fetch is 6 T-cycles later than the steady period.
        a.ch3.timer = wavePeriod(a.ch3.freq) + 6;
        a.ch3.just_read = false;
        a.ch3.enabled = a.ch3.dac;
    }
    a.ch3.length_en = new_en;
}

fn triggerNoise(a: *Apu, value: u8) void {
    const old_en: bool = a.ch4.length_en;
    const new_en: bool = (value & 0x40) != 0;
    const trigger: bool = (value & 0x80) != 0;
    const quirk: bool = (a.fs_step & 1) != 0;
    if (new_en and !old_en and quirk and a.ch4.length != 0) {
        a.ch4.length -= 1;
        if (a.ch4.length == 0 and !trigger) a.ch4.enabled = false;
    }
    if (trigger) {
        if (a.ch4.length == 0) {
            a.ch4.length = 64;
            if (new_en and quirk) a.ch4.length -= 1;
        }
        a.ch4.enabled = a.ch4.dac;
        a.ch4.timer = noisePeriod(&a.ch4);
        a.ch4.lfsr = 0x7FFF;
        a.ch4.vol = a.ch4.vol_init;
        a.ch4.env_timer = if (a.ch4.env_period == 0) 8 else a.ch4.env_period;
    }
    a.ch4.length_en = new_en;
}

fn writeSquareEnv(ch: *Square, value: u8) void {
    ch.vol_init = @intCast(u8, (value >> 4) & 0x0F);
    ch.env_sub = (value & 0x08) != 0;
    ch.env_period = value & 0x07;
    ch.dac = (value & 0xF8) != 0;
    if (!ch.dac) ch.enabled = false;
}

fn writeNoiseEnv(ch: *Noise, value: u8) void {
    ch.vol_init = @intCast(u8, (value >> 4) & 0x0F);
    ch.env_sub = (value & 0x08) != 0;
    ch.env_period = value & 0x07;
    ch.dac = (value & 0xF8) != 0;
    if (!ch.dac) ch.enabled = false;
}

pub fn apuWrite(a: *Apu, addr: u16, value: u8) void {
    if (addr == 0xFF26) {
        writeNr52(a, value);
        return;
    }
    if (addr >= 0xFF30 and addr <= 0xFF3F) {
        if (a.powered and a.ch3.enabled and a.ch3.dac) {
            if (!a.ch3.just_read) return;
            const bi: usize = @intCast(usize, (a.ch3.sample_index >> 1) & 0x0F);
            a.wave_ram[bi] = value;
            return;
        }
        const wi: usize = @intCast(usize, (addr - 0xFF30) & 0x0F);
        a.wave_ram[wi] = value;
        return;
    }
    if (addr < 0xFF10 or addr > 0xFF25) return;
    const idx: usize = @intCast(usize, addr - 0xFF10);
    if (!a.powered) {
        if (addr == 0xFF11) {
            a.ch1.length = @intCast(u16, 64 - @as(u16, value & 0x3F));
        } else if (addr == 0xFF16) {
            a.ch2.length = @intCast(u16, 64 - @as(u16, value & 0x3F));
        } else if (addr == 0xFF1B) {
            a.ch3.length = @intCast(u16, 256 - @as(u16, value));
        } else if (addr == 0xFF20) {
            a.ch4.length = @intCast(u16, 64 - @as(u16, value & 0x3F));
        }
        return;
    }

    switch (addr) {
        0xFF10 => {
            const old_sub: bool = (a.regs[0] & 0x08) != 0;
            const new_sub: bool = (value & 0x08) != 0;
            a.regs[0] = value & 0x7F;
            a.sweep_period = @intCast(u8, (value >> 4) & 0x07);
            a.sweep_sub = new_sub;
            a.sweep_shift = value & 0x07;
            if (old_sub and !new_sub and a.sweep_negate_used) a.ch1.enabled = false;
        },
        0xFF11 => {
            a.regs[1] = value;
            a.ch1.duty = @intCast(u8, (value >> 6) & 0x03);
            a.ch1.length = @intCast(u16, 64 - @as(u16, value & 0x3F));
        },
        0xFF12 => {
            a.regs[2] = value;
            writeSquareEnv(&a.ch1, value);
        },
        0xFF13 => {
            a.regs[3] = value;
            a.ch1.freq = @intCast(u16, (a.ch1.freq & 0x700) | @as(u16, value));
        },
        0xFF14 => {
            a.regs[4] = value;
            a.ch1.freq = @intCast(u16, (a.ch1.freq & 0xFF) | (@as(u16, value & 0x07) << 8));
            triggerSquare(a, &a.ch1, true, value);
        },
        0xFF16 => {
            a.regs[6] = value;
            a.ch2.duty = @intCast(u8, (value >> 6) & 0x03);
            a.ch2.length = @intCast(u16, 64 - @as(u16, value & 0x3F));
        },
        0xFF17 => {
            a.regs[7] = value;
            writeSquareEnv(&a.ch2, value);
        },
        0xFF18 => {
            a.regs[8] = value;
            a.ch2.freq = @intCast(u16, (a.ch2.freq & 0x700) | @as(u16, value));
        },
        0xFF19 => {
            a.regs[9] = value;
            a.ch2.freq = @intCast(u16, (a.ch2.freq & 0xFF) | (@as(u16, value & 0x07) << 8));
            triggerSquare(a, &a.ch2, false, value);
        },
        0xFF1A => {
            a.regs[10] = value;
            a.ch3.dac = (value & 0x80) != 0;
            if (!a.ch3.dac) a.ch3.enabled = false;
        },
        0xFF1B => {
            a.regs[11] = value;
            a.ch3.length = @intCast(u16, 256 - @as(u16, value));
        },
        0xFF1C => {
            a.regs[12] = value;
            a.ch3.vol_code = @intCast(u8, (value >> 5) & 0x03);
        },
        0xFF1D => {
            a.regs[13] = value;
            a.ch3.freq = @intCast(u16, (a.ch3.freq & 0x700) | @as(u16, value));
        },
        0xFF1E => {
            a.regs[14] = value;
            a.ch3.freq = @intCast(u16, (a.ch3.freq & 0xFF) | (@as(u16, value & 0x07) << 8));
            triggerWave(a, value);
        },
        0xFF20 => {
            a.regs[16] = value;
            a.ch4.length = @intCast(u16, 64 - @as(u16, value & 0x3F));
        },
        0xFF21 => {
            a.regs[17] = value;
            writeNoiseEnv(&a.ch4, value);
        },
        0xFF22 => {
            a.regs[18] = value;
            a.ch4.shift = @intCast(u8, (value >> 4) & 0x0F);
            a.ch4.width7 = (value & 0x08) != 0;
            a.ch4.divisor = value & 0x07;
        },
        0xFF23 => {
            a.regs[19] = value;
            triggerNoise(a, value);
        },
        0xFF24 => {
            a.regs[20] = value;
            a.nr50 = value;
        },
        0xFF25 => {
            a.regs[21] = value;
            a.nr51 = value;
        },
        else => {
            a.regs[idx] = value;
        },
    }
}

fn squareDigital(ch: *const Square) i32 {
    if (!ch.enabled or !ch.dac) return 0;
    const bit: u8 = DUTY_LUT[@intCast(usize, ch.duty & 3)][@intCast(usize, ch.duty_pos & 7)];
    if (bit == 0) return 0;
    return @intCast(i32, ch.vol & 0x0F);
}

fn waveDigital(ch: *const Wave) i32 {
    if (!ch.enabled or !ch.dac or ch.vol_code == 0) return 0;
    var nib: u8 = 0;
    if ((ch.sample_index & 1) == 0) {
        nib = @intCast(u8, (ch.sample_byte >> 4) & 0x0F);
    } else {
        nib = ch.sample_byte & 0x0F;
    }
    const val: u8 = WAVE_LUT[@intCast(usize, nib)];
    const sh: u5 = @intCast(u5, ch.vol_code - 1);
    return @intCast(i32, val >> sh);
}

fn noiseDigital(ch: *const Noise) i32 {
    if (!ch.enabled or !ch.dac) return 0;
    if ((ch.lfsr & 1) != 0) return 0;
    return @intCast(i32, ch.vol & 0x0F);
}

fn writeRing(a: *Apu, left: i16, right: i16) void {
    if (a.ring_count >= @intCast(u32, RING_CAP)) {
        a.ring_tail = (a.ring_tail + 2) & RING_MASK;
        a.ring_count -= 2;
    }
    const hi: usize = @intCast(usize, a.ring_head);
    a.ring[hi] = left;
    a.ring[(hi + 1) & (RING_CAP - 1)] = right;
    a.ring_head = (a.ring_head + 2) & RING_MASK;
    a.ring_count += 2;
}

fn emitSample(a: *Apu) void {
    var left: i32 = 0;
    var right: i32 = 0;
    const d1: i32 = squareDigital(&a.ch1);
    const d2: i32 = squareDigital(&a.ch2);
    const d3: i32 = waveDigital(&a.ch3);
    const d4: i32 = noiseDigital(&a.ch4);
    const v1: i32 = VOL_LUT[@intCast(usize, d1 & 0x0F)][0];
    const v2: i32 = VOL_LUT[@intCast(usize, d2 & 0x0F)][1];
    const v3: i32 = VOL_LUT[@intCast(usize, d3 & 0x0F)][2];
    const v4: i32 = VOL_LUT[@intCast(usize, d4 & 0x0F)][3];
    if ((a.nr51 & 0x10) != 0) left += v1;
    if ((a.nr51 & 0x20) != 0) left += v2;
    if ((a.nr51 & 0x40) != 0) left += v3;
    if ((a.nr51 & 0x80) != 0) left += v4;
    if ((a.nr51 & 0x01) != 0) right += v1;
    if ((a.nr51 & 0x02) != 0) right += v2;
    if ((a.nr51 & 0x04) != 0) right += v3;
    if ((a.nr51 & 0x08) != 0) right += v4;
    const lv: i32 = @intCast(i32, (@as(u16, a.nr50) >> 4) & 7);
    const rv: i32 = @intCast(i32, @as(u16, a.nr50) & 7);
    left = (left * lv) / 7;
    right = (right * rv) / 7;
    left *= 256;
    right *= 256;
    a.dc_l += (left - a.dc_l) / 64;
    a.dc_r += (right - a.dc_r) / 64;
    const out_l: i32 = left - a.dc_l;
    const out_r: i32 = right - a.dc_r;
    writeRing(a, @intCast(i16, out_l), @intCast(i16, out_r));
}

fn tickSamples(a: *Apu, cycles: u32) void {
    const inc: u64 = @intCast(u64, a.sample_inc);
    if (inc == 0) return;
    a.sample_acc += @intCast(u64, cycles) << 16;
    while (a.sample_acc >= inc) {
        a.sample_acc -= inc;
        emitSample(a);
    }
}

pub fn apuTick(a: *Apu, cycles: u32) void {
    if (cycles == 0) return;
    if (a.powered) {
        tickSquare(&a.ch1, cycles);
        tickSquare(&a.ch2, cycles);
        tickWave(a, cycles);
        tickNoise(&a.ch4, cycles);
        tickFs(a, cycles);
    }
    tickSamples(a, cycles);
}

pub fn apuSamples(a: *Apu, out: []i16) usize {
    var n: usize = out.len;
    const cnt: usize = @intCast(usize, a.ring_count);
    if (n > cnt) n = cnt;
    if ((n & 1) != 0) n -= 1;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const idx: usize = @intCast(usize, (a.ring_tail + @intCast(u32, i)) & RING_MASK);
        out[i] = a.ring[idx];
    }
    a.ring_tail = (a.ring_tail + @intCast(u32, n)) & RING_MASK;
    a.ring_count -= @intCast(u32, n);
    return n;
}
