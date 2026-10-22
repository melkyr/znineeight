// stdlib_ecc_verify_xmod — STDLIB std_ecc P-256/P-384 GREEN fixture.
//
// std_ecc.zig is a PURE Z98 module (no heap, no libm, integer-only; the shared
// prime-curve engine is a port of BearSSL's portable i31 code). This fixture
// exercises:
//   - NIST CAVP KAS ECC CDH P-256 shared-secret vectors (2)
//   - NIST CAVP SigVer P-256/SHA-256 ECDSA verify (2 good, 2 bad)
//   - NIST CAVP SigVer P-384/SHA-384 ECDSA verify (2 good, 2 bad)
//   - p256Generate determinism + cross-ECDH with two seeded xoshiro256** runs
//
// The hash inputs below are SHA-256(Msg) / SHA-384(Msg) for the CAVP Msg field;
// std_ecc takes the caller-supplied hash exactly as specified in §5.3.
//
// GREEN (contract): deterministic byte-exact stdout `ecc verify ok\n`
// (RUNRC=0). Bad signatures MUST verify false; a silent accept calls @panic.
const std = @import("std");
const ecc = @import("std_ecc.zig");
const rand = @import("std_rand.zig");

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

fn ckEq(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) ck(got[i] == want[i], what);
}

fn ecdhP256(priv_hex: []const u8, peer_hex: []const u8, want_hex: []const u8, what: []const u8) void {
    var priv: [32]u8 = undefined;
    var peer: [65]u8 = undefined;
    var want: [32]u8 = undefined;
    var got: [32]u8 = undefined;
    fill(priv_hex, priv[0..]);
    fill(peer_hex, peer[0..]);
    fill(want_hex, want[0..]);
    ecc.p256Ecdh(&priv, &peer, &got) catch @panic(what);
    ckEq(got[0..], want[0..], what);
}

fn goodP256(pub_hex: []const u8, hash_hex: []const u8, r_hex: []const u8, s_hex: []const u8, what: []const u8) void {
    var pub_key: [65]u8 = undefined;
    var hash: [32]u8 = undefined;
    var r: [32]u8 = undefined;
    var s: [32]u8 = undefined;
    fill(pub_hex, pub_key[0..]);
    fill(hash_hex, hash[0..]);
    fill(r_hex, r[0..]);
    fill(s_hex, s[0..]);
    ck(ecc.p256EcdsaVerify(&pub_key, &hash, &r, &s), what);
}

fn badP256(pub_hex: []const u8, hash_hex: []const u8, r_hex: []const u8, s_hex: []const u8, what: []const u8) void {
    var pub_key: [65]u8 = undefined;
    var hash: [32]u8 = undefined;
    var r: [32]u8 = undefined;
    var s: [32]u8 = undefined;
    fill(pub_hex, pub_key[0..]);
    fill(hash_hex, hash[0..]);
    fill(r_hex, r[0..]);
    fill(s_hex, s[0..]);
    ck(!ecc.p256EcdsaVerify(&pub_key, &hash, &r, &s), what);
}

fn badP256Mut(pub_hex: []const u8, hash_hex: []const u8, r_hex: []const u8, s_hex: []const u8, mode: u32, what: []const u8) void {
    var pub_key: [65]u8 = undefined;
    var hash: [32]u8 = undefined;
    var r: [32]u8 = undefined;
    var s: [32]u8 = undefined;
    fill(pub_hex, pub_key[0..]);
    fill(hash_hex, hash[0..]);
    fill(r_hex, r[0..]);
    fill(s_hex, s[0..]);
    if (mode == 0) {
        pub_key[0] = 0x05;
    } else if (mode == 1) {
        pub_key[64] = pub_key[64] ^ 1;
    } else {
        var pbytes: [32]u8 = undefined;
        fill("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", pbytes[0..]);
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            if (mode == 2) {
                pub_key[1 + i] = pbytes[i];
            } else {
                pub_key[33 + i] = pbytes[i];
            }
        }
    }
    ck(!ecc.p256EcdsaVerify(&pub_key, &hash, &r, &s), what);
}

fn badPrivP256(priv_hex: []const u8, peer_hex: []const u8, what: []const u8) void {
    var priv: [32]u8 = undefined;
    var peer: [65]u8 = undefined;
    var out: [32]u8 = undefined;
    fill(priv_hex, priv[0..]);
    fill(peer_hex, peer[0..]);
    var saw: bool = false;
    ecc.p256Ecdh(&priv, &peer, &out) catch |err| {
        ck(err == error.InvalidPrivateKey, what);
        saw = true;
    };
    ck(saw, what);
}

fn badPeerP256(priv_hex: []const u8, peer_hex: []const u8, mode: u32, what: []const u8) void {
    var priv: [32]u8 = undefined;
    var peer: [65]u8 = undefined;
    var out: [32]u8 = undefined;
    fill(priv_hex, priv[0..]);
    fill(peer_hex, peer[0..]);
    if (mode == 0) {
        peer[0] = 0x05;
    } else if (mode == 1) {
        peer[64] = peer[64] ^ 1;
    } else {
        var pbytes: [32]u8 = undefined;
        fill("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", pbytes[0..]);
        var i: usize = 0;
        while (i < 32) : (i += 1) peer[1 + i] = pbytes[i];
    }
    var saw: bool = false;
    ecc.p256Ecdh(&priv, &peer, &out) catch |err| {
        ck(err == error.InvalidPublicKey, what);
        saw = true;
    };
    ck(saw, what);
}

fn goodP384(pub_hex: []const u8, hash_hex: []const u8, r_hex: []const u8, s_hex: []const u8, what: []const u8) void {
    var pub_key: [97]u8 = undefined;
    var hash: [48]u8 = undefined;
    var r: [48]u8 = undefined;
    var s: [48]u8 = undefined;
    fill(pub_hex, pub_key[0..]);
    fill(hash_hex, hash[0..]);
    fill(r_hex, r[0..]);
    fill(s_hex, s[0..]);
    ck(ecc.p384EcdsaVerify(&pub_key, &hash, &r, &s), what);
}

fn badP384(pub_hex: []const u8, hash_hex: []const u8, r_hex: []const u8, s_hex: []const u8, what: []const u8) void {
    var pub_key: [97]u8 = undefined;
    var hash: [48]u8 = undefined;
    var r: [48]u8 = undefined;
    var s: [48]u8 = undefined;
    fill(pub_hex, pub_key[0..]);
    fill(hash_hex, hash[0..]);
    fill(r_hex, r[0..]);
    fill(s_hex, s[0..]);
    ck(!ecc.p384EcdsaVerify(&pub_key, &hash, &r, &s), what);
}

fn badP384Mut(pub_hex: []const u8, hash_hex: []const u8, r_hex: []const u8, s_hex: []const u8, mode: u32, what: []const u8) void {
    var pub_key: [97]u8 = undefined;
    var hash: [48]u8 = undefined;
    var r: [48]u8 = undefined;
    var s: [48]u8 = undefined;
    fill(pub_hex, pub_key[0..]);
    fill(hash_hex, hash[0..]);
    fill(r_hex, r[0..]);
    fill(s_hex, s[0..]);
    if (mode == 0) {
        pub_key[0] = 0x05;
    } else if (mode == 1) {
        pub_key[96] = pub_key[96] ^ 1;
    } else {
        var pbytes: [48]u8 = undefined;
        fill("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff", pbytes[0..]);
        var i: usize = 0;
        while (i < 48) : (i += 1) pub_key[1 + i] = pbytes[i];
    }
    ck(!ecc.p384EcdsaVerify(&pub_key, &hash, &r, &s), what);
}

pub fn main() void {
    // NIST CAVP KAS ECC CDH, P-256, Ephemeral Unified initiator ZZOnly.
    ecdhP256(
        "c6b264fba4e5d214890c4e7659a40b5ac572fdb72e53620da5f6f3453573c07a",
        "040d06ca6810483c3dba71e5bc029dff58196bf1a1edd72815f968d0af5ec018534cfd7100a03af94db0c77341f3bd7cb8736ffd8aab361129dd4e3db0f3b17ba6",
        "19d7a760a65503b695ddc78d585be618249ae8527ebc0256f646ecd1a8aecbc2",
        "cavp ecdh p256 #0");
    ecdhP256(
        "05c1bcbf98d290df6b814143d4df26ab687560a3a3353aa961ff6a7ac941ca9b",
        "04372bc6bb304a3dd8528cdf8b2e9236085f0aeac5d1d993e6ed5a6e3506c3a442982a0fee728d4420b5609b36a20be88f3ee805285cdecb67726451ea04a68786",
        "1a24de7fa3633ccc758f168681cdfcf788099e42c433ba837cb094ac44dbd203",
        "cavp ecdh p256 #1");

    // NIST CAVP SigVer P-256/SHA-256: two accepts, two rejects.
    goodP256(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f",
        "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c",
        "cavp p256 good #0");
    goodP256(
        "04e0fc6a6f50e1c57475673ee54e3a57f9a49f3328e743bf52f335e3eeaa3d28647f59d689c91e463607d9194d99faf316e25432870816dde63f5d4b373f12f22a",
        "b9336a8d1f3e8ede001d19f41320bc7672d772a3d2cb0e435fff3c27d6804a2c",
        "1d75830cd36f4c9aa181b2c4221e87f176b7f05b7c87824e82e396c88315c407",
        "cb2acb01dac96efc53a32d4a0d85d0c2e48955214783ecf50a4f0414a319c05a",
        "cavp p256 good #1");
    badP256(
        "0487f8f2b218f49845f6f10eec3877136269f5c1a54736dbdf69f89940cad41555e15f369036f49842fac7a86c8a2b0557609776814448b8f5e84aa9f4395205e9",
        "a82c31412f537135d1c418bd7136fb5fde9426e70c70e7c2fb11f02f30fdeae2",
        "d19ff48b324915576416097d2544f7cbdf8768b1454ad20e0baac50e211f23b0",
        "a3e81e59311cdfff2d4784949f7a2cb50ba6c3a91fa54710568e61aca3e847c6",
        "cavp p256 bad S #0");
    badP256(
        "045cf02a00d205bdfee2016f7421807fc38ae69e6b7ccd064ee689fc1a94a9f7d2ec530ce3cc5c9d1af463f264d685afe2b4db4b5828d7e61b748930f3ce622a85",
        "5984eab8854d0a9aa5f0c70f96deeb510e5f9ff8c51befcdc3c41bac53577f22",
        "dc23d130c6117fb5751201455e99f36f59aba1a6a21cf2d0e7481a97451d6693",
        "d6ce7708c18dbf35d4f8aa7240922dc6823f2e7058cbc1484fcad1599db5018c",
        "cavp p256 bad R #1");

    // NIST CAVP SigVer P-384/SHA-384: two accepts, two rejects.
    goodP384(
        "04cb908b1fd516a57b8ee1e14383579b33cb154fece20c5035e2b3765195d1951d75bd78fb23e00fef37d7d064fd9af144cd99c46b5857401ddcff2cf7cf822121faf1cbad9a011bed8c551f6f59b2c360f79bfbe32adbcaa09583bdfdf7c374bb",
        "965b83f5d34f7443eb88e78fcc23479156c9cb0080dd68334dac0ad33ba8c774100e440063db28b40b51ac37705d4d70",
        "33f64fb65cd6a8918523f23aea0bbcf56bba1daca7aff817c8791dc92428d605ac629de2e847d43cee55ba9e4a0e83ba",
        "4428bb478a43ac73ecd6de51ddf7c28ff3c2441625a081714337dd44fea8011bae71959a10947b6ea33f77e128d3c6ae",
        "cavp p384 good #0");
    goodP384(
        "04a370cdbef95d1df5bf68ec487122514a107db87df3f8852068fd4694abcadb9b14302c72491a76a64442fc07bd99f02cd397c25dc1a5781573d039f2520cf329bf65120fdbe964b6b80101160e533d5570e62125b9f3276c49244b8d0f3e44ec",
        "709d1bf45b5817f5a67b859651eb47133ebed2622fda09ab66d3467b5e95da50ecc2c74d8f4d289feebec29729a4bfa3",
        "c6c7bb516cc3f37a304328d136b2f44bb89d3dac78f1f5bcd36b412a8b4d879f6cdb75175292c696b58bfa9c91fe6391",
        "6b711425e1b14f7224cd4b96717a84d65a60ec9951a30152ea1dd3b6ea66a0088d1fd3e9a1ef069804b7d969148c37a0",
        "cavp p384 good #1");
    badP384(
        "041f94eb6f439a3806f8054dd79124847d138d14d4f52bac93b042f2ee3cdb7dc9e09925c2a5fee70d4ce08c61e3b191601c4fd111f6e33303069421deb31e873126be35eeb436fe2034856a3ed1e897f26c846ee3233cd16240989a7990c19d8c",
        "8cf5e81c6858b8395421d8c913f1ac887e282b5818eab525fb79feb9bc64bca7eb98f94b9e48b705e6c28311bb0ca672",
        "3c15c3cedf2a6fbff2f906e661f5932f2542f0ce68e2a8182e5ed3858f33bd3c5666f17ac39e52cb004b80a0d4ba73cd",
        "9de879083cbb0a97973c94f1963d84f581e4c6541b7d000f9850deb25154b23a37dd72267bdd72665cc7027f88164fab",
        "cavp p384 bad R #0");
    badP384(
        "049b3c48d924194146eca4172b6d7d618423682686f43e1dbc54ed909053d075ca53b68ae12f0f16a1633d5d9cb17011ec695039f837b68e59330ee95d11d5315a8fb5602a7b60c15142dbba6e93b5e4aba8ae4469eac39fa6436323eccc60dcb6",
        "c68382d0641ffad850c41365a8ec68e3d55acba376d1bb941e7dcdf7b71f37b8288b023b942373a40be1dfaaf4aea633",
        "202da4e4e9632bcb6bf0f6dafb7e348528d0b469d77e46b9f939e2fa946a608dd1f166bcbcde96cfad551701da69f6c2",
        "db595b49983882c48df8a396884cd98893a469c4d590e56c6a59b6150d9a0acdf142cf92151052644702ed857a5b7981",
        "cavp p384 bad S #1");

    // FIPS/SEC1 range gate: r and s must both be in [1, n-1].
    badP256(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "0000000000000000000000000000000000000000000000000000000000000000",
        "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c",
        "range p256 r=0");
    badP256(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f",
        "0000000000000000000000000000000000000000000000000000000000000000",
        "range p256 s=0");
    badP256(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f",
        "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        "range p256 s=n");
    badP256(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c",
        "range p256 r=n");

    // Invalid public keys: wrong tag, off curve, coordinates >= p.
    badP256Mut(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f",
        "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c",
        0, "p256 pub bad tag");
    badP256Mut(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f",
        "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c",
        1, "p256 pub off curve");
    badP256Mut(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f",
        "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c",
        2, "p256 pub x>=p");
    badP256Mut(
        "04e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927",
        "d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94",
        "bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f",
        "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c",
        3, "p256 pub y>=p");

    // P-384 range/public-key negatives use the same generic engine.
    badP384(
        "04cb908b1fd516a57b8ee1e14383579b33cb154fece20c5035e2b3765195d1951d75bd78fb23e00fef37d7d064fd9af144cd99c46b5857401ddcff2cf7cf822121faf1cbad9a011bed8c551f6f59b2c360f79bfbe32adbcaa09583bdfdf7c374bb",
        "965b83f5d34f7443eb88e78fcc23479156c9cb0080dd68334dac0ad33ba8c774100e440063db28b40b51ac37705d4d70",
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "4428bb478a43ac73ecd6de51ddf7c28ff3c2441625a081714337dd44fea8011bae71959a10947b6ea33f77e128d3c6ae",
        "range p384 r=0");
    badP384Mut(
        "04cb908b1fd516a57b8ee1e14383579b33cb154fece20c5035e2b3765195d1951d75bd78fb23e00fef37d7d064fd9af144cd99c46b5857401ddcff2cf7cf822121faf1cbad9a011bed8c551f6f59b2c360f79bfbe32adbcaa09583bdfdf7c374bb",
        "965b83f5d34f7443eb88e78fcc23479156c9cb0080dd68334dac0ad33ba8c774100e440063db28b40b51ac37705d4d70",
        "33f64fb65cd6a8918523f23aea0bbcf56bba1daca7aff817c8791dc92428d605ac629de2e847d43cee55ba9e4a0e83ba",
        "4428bb478a43ac73ecd6de51ddf7c28ff3c2441625a081714337dd44fea8011bae71959a10947b6ea33f77e128d3c6ae",
        0, "p384 pub bad tag");
    badP384Mut(
        "04cb908b1fd516a57b8ee1e14383579b33cb154fece20c5035e2b3765195d1951d75bd78fb23e00fef37d7d064fd9af144cd99c46b5857401ddcff2cf7cf822121faf1cbad9a011bed8c551f6f59b2c360f79bfbe32adbcaa09583bdfdf7c374bb",
        "965b83f5d34f7443eb88e78fcc23479156c9cb0080dd68334dac0ad33ba8c774100e440063db28b40b51ac37705d4d70",
        "33f64fb65cd6a8918523f23aea0bbcf56bba1daca7aff817c8791dc92428d605ac629de2e847d43cee55ba9e4a0e83ba",
        "4428bb478a43ac73ecd6de51ddf7c28ff3c2441625a081714337dd44fea8011bae71959a10947b6ea33f77e128d3c6ae",
        1, "p384 pub off curve");
    badP384Mut(
        "04cb908b1fd516a57b8ee1e14383579b33cb154fece20c5035e2b3765195d1951d75bd78fb23e00fef37d7d064fd9af144cd99c46b5857401ddcff2cf7cf822121faf1cbad9a011bed8c551f6f59b2c360f79bfbe32adbcaa09583bdfdf7c374bb",
        "965b83f5d34f7443eb88e78fcc23479156c9cb0080dd68334dac0ad33ba8c774100e440063db28b40b51ac37705d4d70",
        "33f64fb65cd6a8918523f23aea0bbcf56bba1daca7aff817c8791dc92428d605ac629de2e847d43cee55ba9e4a0e83ba",
        "4428bb478a43ac73ecd6de51ddf7c28ff3c2441625a081714337dd44fea8011bae71959a10947b6ea33f77e128d3c6ae",
        2, "p384 pub x>=p");

    // ECDH private-key range and peer-point validation negatives.
    badPrivP256(
        "0000000000000000000000000000000000000000000000000000000000000000",
        "040d06ca6810483c3dba71e5bc029dff58196bf1a1edd72815f968d0af5ec018534cfd7100a03af94db0c77341f3bd7cb8736ffd8aab361129dd4e3db0f3b17ba6",
        "ecdh p256 zero priv");
    badPrivP256(
        "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        "040d06ca6810483c3dba71e5bc029dff58196bf1a1edd72815f968d0af5ec018534cfd7100a03af94db0c77341f3bd7cb8736ffd8aab361129dd4e3db0f3b17ba6",
        "ecdh p256 priv=n");
    badPeerP256(
        "c6b264fba4e5d214890c4e7659a40b5ac572fdb72e53620da5f6f3453573c07a",
        "040d06ca6810483c3dba71e5bc029dff58196bf1a1edd72815f968d0af5ec018534cfd7100a03af94db0c77341f3bd7cb8736ffd8aab361129dd4e3db0f3b17ba6",
        0, "ecdh p256 peer bad tag");
    badPeerP256(
        "c6b264fba4e5d214890c4e7659a40b5ac572fdb72e53620da5f6f3453573c07a",
        "040d06ca6810483c3dba71e5bc029dff58196bf1a1edd72815f968d0af5ec018534cfd7100a03af94db0c77341f3bd7cb8736ffd8aab361129dd4e3db0f3b17ba6",
        1, "ecdh p256 peer off curve");
    badPeerP256(
        "c6b264fba4e5d214890c4e7659a40b5ac572fdb72e53620da5f6f3453573c07a",
        "040d06ca6810483c3dba71e5bc029dff58196bf1a1edd72815f968d0af5ec018534cfd7100a03af94db0c77341f3bd7cb8736ffd8aab361129dd4e3db0f3b17ba6",
        2, "ecdh p256 peer x>=p");

    // p256Generate: deterministic for a fixed seed, and two independent key
    // pairs agree on the shared secret. The ECDH calls also validate the
    // generated public keys (point decode rejects off-curve input).
    var rng_a = rand.xoshiroInit(0x5eed000000000001);
    var rng_b = rand.xoshiroInit(0x5eed000000000002);
    var rng_a2 = rand.xoshiroInit(0x5eed000000000001);
    var priv_a: [32]u8 = undefined;
    var pub_a: [65]u8 = undefined;
    var priv_b: [32]u8 = undefined;
    var pub_b: [65]u8 = undefined;
    var priv_a2: [32]u8 = undefined;
    var pub_a2: [65]u8 = undefined;
    ecc.p256Generate(&rng_a, &priv_a, &pub_a);
    ecc.p256Generate(&rng_b, &priv_b, &pub_b);
    ecc.p256Generate(&rng_a2, &priv_a2, &pub_a2);
    ckEq(priv_a[0..], priv_a2[0..], "p256Generate priv deterministic");
    ckEq(pub_a[0..], pub_a2[0..], "p256Generate pub deterministic");

    var z1: [32]u8 = undefined;
    var z2: [32]u8 = undefined;
    ecc.p256Ecdh(&priv_a, &pub_b, &z1) catch @panic("keygen ecdh ab");
    ecc.p256Ecdh(&priv_b, &pub_a, &z2) catch @panic("keygen ecdh ba");
    ckEq(z1[0..], z2[0..], "keygen shared secret");

    if (g_fail == 0) {
        std.io.write("ecc verify ok\n");
    } else {
        @panic("ecc verify fixture failed");
    }
}
