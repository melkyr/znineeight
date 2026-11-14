// stdlib_x25519_xmod — STDLIB std_ecc X25519 GREEN fixture.
//
// std_ecc.zig is a PURE Z98 module (no heap, no libm, integer-only). This
// fixture exercises:
//   - RFC 7748 §5.2 base-point vectors and the Alice/Bob shared secret
//   - RFC 7748 §5.2 one-iteration non-base scalar/u vector
//   - RFC 7748 all-zero output rejection (`error.WeakPublicKey`)
//
// GREEN (contract): deterministic byte-exact stdout `x25519 ok\n` (RUNRC=0).
// A mismatch increments g_fail and calls @panic.
const std = @import("std");
const ecc = @import("std_ecc.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn hexNib(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return c - 'A' + 10;
}

fn unhex(s: []const u8, out: []u8) usize {
    var i: usize = 0;
    while (i * 2 + 1 < s.len) : (i += 1) {
        out[i] = (hexNib(s[i * 2]) << 4) | hexNib(s[i * 2 + 1]);
    }
    return i;
}

fn fill(hex: []const u8, out: []u8) void {
    var i: usize = 0;
    while (i < out.len) : (i += 1) out[i] = 0;
    _ = unhex(hex, out);
}

fn ckHex(got: []const u8, hex: []const u8, what: []const u8) void {
    var want: [64]u8 = undefined;
    var n: usize = unhex(hex, want[0..]);
    ck(got.len == n, what);
    var i: usize = 0;
    while (i < n) : (i += 1) ck(got[i] == want[i], what);
}

pub fn main() void {
    var alice: [32]u8 = undefined;
    fill("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", alice[0..]);
    var alice_pub: [32]u8 = undefined;
    ecc.x25519Base(&alice, &alice_pub) catch @panic("alice base");
    ckHex(alice_pub[0..], "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", "alice pub");

    var bob: [32]u8 = undefined;
    fill("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb", bob[0..]);
    var bob_pub: [32]u8 = undefined;
    ecc.x25519Base(&bob, &bob_pub) catch @panic("bob base");
    ckHex(bob_pub[0..], "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", "bob pub");

    var shared: [32]u8 = undefined;
    ecc.x25519(&alice, &bob_pub, &shared) catch @panic("shared ab");
    ckHex(shared[0..], "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", "shared ab");
    ecc.x25519(&bob, &alice_pub, &shared) catch @panic("shared ba");
    ckHex(shared[0..], "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", "shared ba");

    // RFC 7748 §5.2: one iteration of the iterated test.
    var s9: [32]u8 = undefined;
    var u9: [32]u8 = undefined;
    fill("0900000000000000000000000000000000000000000000000000000000000000", s9[0..]);
    fill("0900000000000000000000000000000000000000000000000000000000000000", u9[0..]);
    ecc.x25519(&s9, &u9, &shared) catch @panic("iter1");
    ckHex(shared[0..], "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079", "iter1");

    // RFC 7748: all-zero output is a weak public key.
    var zero: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) zero[i] = 0;
    var saw_weak: bool = false;
    ecc.x25519(&alice, &zero, &shared) catch |err| {
        ck(err == error.WeakPublicKey, "weak key error");
        saw_weak = true;
    };
    ck(saw_weak, "weak key not rejected");

    if (g_fail == 0) {
        std.io.write("x25519 ok\n");
    } else {
        @panic("x25519 fixture failed");
    }
}
