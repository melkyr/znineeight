pub const SERIAL_CAP: usize = 4096;

pub const Serial = struct {
    sb: u8,
    sc: u8,
    pending: u32,
    ifr: *u8,
    log: [SERIAL_CAP]u8,
    log_len: usize,
};

pub fn serialReset(s: *Serial) void {
    s.sb = 0;
    s.sc = 0;
    s.pending = 0;
    s.log_len = 0;
}

pub fn serialWrite(s: *Serial, addr: u16, value: u8) void {
    if (addr == 0xFF01) {
        s.sb = value;
        return;
    }
    if (addr == 0xFF02) {
        if ((value & 0x80) != 0) {
            if (s.log_len < SERIAL_CAP) {
                s.log[s.log_len] = s.sb;
                s.log_len += 1;
            }
            s.sc = value & 0x7F;
            s.pending = 8;
        } else {
            s.sc = value & 0x7F;
        }
    }
}

pub fn serialTick(s: *Serial, cycles: u32) void {
    if (s.pending == 0) return;
    if (cycles >= s.pending) {
        s.pending = 0;
        s.ifr.* |= 0x08;
        return;
    }
    s.pending -= cycles;
}

pub fn serialTake(s: *Serial, out: []u8) usize {
    var n: usize = s.log_len;
    if (n > out.len) n = out.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = s.log[i];
    }
    if (n < s.log_len) {
        var j: usize = 0;
        while (j < s.log_len - n) : (j += 1) {
            s.log[j] = s.log[n + j];
        }
    }
    s.log_len -= n;
    return n;
}
