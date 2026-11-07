const tls = @import("std_tls.zig");
const net = @import("std_net.zig");

pub const TlsIo = struct {
    sess: *tls.TlsSession,
    sock: net.Socket,
    out: [tls.TLS_MAX_WIRE_RECORD + 64]u8,
    out_len: usize,
    out_off: usize,
    in: [tls.TLS_MAX_WIRE_RECORD]u8,
    established: bool,
    closed: bool,
    sock_closed: bool,
};

pub const TlsIoError = error{
    BadAction,
    AppTooLarge,
    OutputTooSmall,
    BadConfig,
    HandshakeFailed,
    UnsupportedVersion,
    UnsupportedSuite,
    UnsupportedGroup,
    CertificateExpired,
    CertificateNotYetValid,
    UnknownIssuer,
    HostnameMismatch,
    BadSignature,
    ChainTooLong,
    UnsupportedAlgorithm,
    Corrupt,
    AuthenticationFailed,
    RecordTooLarge,
    Closed,
    WeakPublicKey,
    InvalidPrivateKey,
    InvalidPublicKey,
    WouldBlock,
    Timeout,
    ConnRefused,
    ConnReset,
    NotConnected,
    AddrInUse,
    InvalidAddr,
    ResolveFailed,
    Io,
};

pub fn tlsIoInit(io: *TlsIo, sess: *tls.TlsSession, sock: net.Socket) void {
    io.sess = sess;
    io.sock = sock;
    io.out_len = 0;
    io.out_off = 0;
    io.established = false;
    io.closed = false;
    io.sock_closed = false;
}

fn flushOut(io: *TlsIo) TlsIoError!void {
    while (io.out_off < io.out_len) {
        const n = try net.sendNonBlocking(&io.sock, io.out[io.out_off..io.out_len]);
        if (n == 0) return error.Io;
        io.out_off += n;
    }
    io.out_len = 0;
    io.out_off = 0;
}

pub fn tlsIoHandshakePump(io: *TlsIo) TlsIoError!bool {
    if (io.closed) return error.Closed;
    if (io.established) return true;

    var input: []const u8 = "";
    while (true) {
        try flushOut(io);
        const act = try tls.tlsStep(io.sess, input, io.out[0..]);
        input = "";
        switch (act) {
            .send => |bytes| {
                io.out_len = bytes.len;
                io.out_off = 0;
            },
            .recv => {
                const n = try net.recvNonBlocking(&io.sock, io.in[0..]);
                if (n == 0) {
                    io.closed = true;
                    return error.Closed;
                }
                input = io.in[0..n];
            },
            .wait => {
                const n = try net.recvNonBlocking(&io.sock, io.in[0..]);
                if (n == 0) {
                    io.closed = true;
                    return error.Closed;
                }
                input = io.in[0..n];
            },
            .established => {
                io.established = true;
                return true;
            },
            .closed => {
                io.closed = true;
                return error.Closed;
            },
            else => {},
        }
    }
    return error.HandshakeFailed;
}

pub fn tlsIoReadPump(io: *TlsIo, out: []u8) TlsIoError!usize {
    if (io.closed) return 0;
    if (!io.established) return error.HandshakeFailed;
    if (out.len == 0) return 0;

    const buffered = try tls.tlsRead(io.sess, out);
    if (buffered > 0) return buffered;

    while (true) {
        try flushOut(io);
        const rn = try net.recvNonBlocking(&io.sock, io.in[0..]);
        if (rn == 0) {
            io.closed = true;
            return 0;
        }
        const act = try tls.tlsStep(io.sess, io.in[0..rn], io.out[0..]);
        switch (act) {
            .send => |bytes| {
                io.out_len = bytes.len;
                io.out_off = 0;
                try flushOut(io);
            },
            .recv => {},
            .wait => {},
            .established => {},
            .closed => {
                io.closed = true;
                return 0;
            },
            else => {},
        }
        const n = try tls.tlsRead(io.sess, out);
        if (n > 0) return n;
    }
    return error.Closed;
}

pub fn tlsIoWritePump(io: *TlsIo, data: []const u8) TlsIoError!usize {
    if (io.closed) return error.Closed;
    if (!io.established) return error.HandshakeFailed;

    try flushOut(io);
    if (data.len == 0) return 0;

    var take: usize = data.len;
    if (take > tls.TLS_MAX_PLAINTEXT_RECORD) take = tls.TLS_MAX_PLAINTEXT_RECORD;

    const wire_len = try tls.tlsWrite(io.sess, data[0..take], io.out[0..]);
    io.out_len = wire_len;
    io.out_off = 0;
    flushOut(io) catch |e| {
        if (e != error.WouldBlock) return e;
    };
    return take;
}

pub fn tlsIoClose(io: *TlsIo) void {
    if (!io.sock_closed) {
        net.close(io.sock);
        io.sock_closed = true;
    }
    io.closed = true;
    io.established = false;
    io.out_len = 0;
    io.out_off = 0;
}
