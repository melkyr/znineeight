// stdlib_const_rodata_xmod — M2 T1C-F const-rodata value fixture.
//
// File-scope `const` values must be emitted as C89 `static const`/`const`
// rodata initializers (no `__module_init` stores) and stay runtime-correct:
//   S3  scalar constant-expressions (`3+4`, `-10`, `64*1024`, `@intCast`)
//   S2  bool literal
//   S1  float literal
//   S4  256-entry u32 table (T-table shape)
//   S5  multi-D array
//   S6  struct init     S7 tuple/anon agg
//   S8  struct-of-slice + many-ptr (decay/address)
//   S9  slice/many from a const array
//   S10 string slice    S11 string many-ptr    S12 `[N]u8 = "..."`
//   S18 const-to-const ref chains (scalar + aggregate)
//   S19 non-constant const (`.bss` + `__module_init`, values correct)
//   STOP-1 negative: non-first-member union const falls back to `.bss`
//     (C89 union static init targets the first member only) — values kept.
//
// Contract: stdout one line (see expected.txt), rc 0, byte-exact 3x; every
// observation `@panic`-guarded.
const std = @import("std");

const SUM: u32 = 3 + 4;
const NEG: i32 = -10;
const ARENA: usize = 64 * 1024;
const CASTED: u8 = @intCast(u8, 65);
const FLAG: bool = true;
const RATIO: f64 = 1.5;

const BASE: u32 = 5;
const CHAIN1: u32 = BASE + 1;
const CHAIN2: u32 = CHAIN1 * 2;

// S4: 256-entry u32 table, TE0[i] = i*7+1 (generated).
const TE0 = [256]u32{
    1,
    8,
    15,
    22,
    29,
    36,
    43,
    50,
    57,
    64,
    71,
    78,
    85,
    92,
    99,
    106,
    113,
    120,
    127,
    134,
    141,
    148,
    155,
    162,
    169,
    176,
    183,
    190,
    197,
    204,
    211,
    218,
    225,
    232,
    239,
    246,
    253,
    260,
    267,
    274,
    281,
    288,
    295,
    302,
    309,
    316,
    323,
    330,
    337,
    344,
    351,
    358,
    365,
    372,
    379,
    386,
    393,
    400,
    407,
    414,
    421,
    428,
    435,
    442,
    449,
    456,
    463,
    470,
    477,
    484,
    491,
    498,
    505,
    512,
    519,
    526,
    533,
    540,
    547,
    554,
    561,
    568,
    575,
    582,
    589,
    596,
    603,
    610,
    617,
    624,
    631,
    638,
    645,
    652,
    659,
    666,
    673,
    680,
    687,
    694,
    701,
    708,
    715,
    722,
    729,
    736,
    743,
    750,
    757,
    764,
    771,
    778,
    785,
    792,
    799,
    806,
    813,
    820,
    827,
    834,
    841,
    848,
    855,
    862,
    869,
    876,
    883,
    890,
    897,
    904,
    911,
    918,
    925,
    932,
    939,
    946,
    953,
    960,
    967,
    974,
    981,
    988,
    995,
    1002,
    1009,
    1016,
    1023,
    1030,
    1037,
    1044,
    1051,
    1058,
    1065,
    1072,
    1079,
    1086,
    1093,
    1100,
    1107,
    1114,
    1121,
    1128,
    1135,
    1142,
    1149,
    1156,
    1163,
    1170,
    1177,
    1184,
    1191,
    1198,
    1205,
    1212,
    1219,
    1226,
    1233,
    1240,
    1247,
    1254,
    1261,
    1268,
    1275,
    1282,
    1289,
    1296,
    1303,
    1310,
    1317,
    1324,
    1331,
    1338,
    1345,
    1352,
    1359,
    1366,
    1373,
    1380,
    1387,
    1394,
    1401,
    1408,
    1415,
    1422,
    1429,
    1436,
    1443,
    1450,
    1457,
    1464,
    1471,
    1478,
    1485,
    1492,
    1499,
    1506,
    1513,
    1520,
    1527,
    1534,
    1541,
    1548,
    1555,
    1562,
    1569,
    1576,
    1583,
    1590,
    1597,
    1604,
    1611,
    1618,
    1625,
    1632,
    1639,
    1646,
    1653,
    1660,
    1667,
    1674,
    1681,
    1688,
    1695,
    1702,
    1709,
    1716,
    1723,
    1730,
    1737,
    1744,
    1751,
    1758,
    1765,
    1772,
    1779,
    1786,
};

// S5 multi-D
const GRID = [2][3]u32{ [3]u32{ 1, 2, 3 }, [3]u32{ 4, 5, 6 } };

// S6 struct
const Pair = struct { a: i32, b: i32 };
const P1 = Pair{ .a = 1, .b = 2 };

// S7 tuple
const TUP: struct { u32, u32 } = .{ 33, 44 };

// S8/S9 decay + address
const Holder = struct { m: []const i32 };
const ManyHolder = struct { mp: [*]const i32 };
const garr = [3]i32{ 1, 2, 3 };
const gh: Holder = .{ .m = garr };
const gmh: ManyHolder = .{ .mp = &garr };
const gc: []const i32 = garr;
const gcm: [*]const i32 = garr;

// S10/S11/S12 strings
const gstr: []const u8 = "abc";
const gstrp: [*]const u8 = "abc";
const sarr: [5]u8 = "hello";

// S18 aggregate ref chain
const THolder = struct { t: []const u32 };
const gth: THolder = .{ .t = TE0 };

// S19 non-constant const
var runtime_x: u32 = 3;
const nonconst: u32 = runtime_x + 1;

// STOP-1 negative: non-first-member union const -> .bss fallback
const U1 = union { a: u32, b: u8 };
const ub = U1{ .b = 5 };

pub fn main() void {
    if (SUM != 7) @panic("S3 SUM");
    if (NEG != -10) @panic("S3 NEG");
    if (ARENA != 65536) @panic("S3 ARENA");
    if (CASTED != 65) @panic("S3 CASTED");
    if (!FLAG) @panic("S2 FLAG");
    if (CHAIN2 != 12) @panic("S18 CHAIN2");
    if (RATIO != 1.5) @panic("S1 RATIO");
    if (TE0[0] != 1) @panic("S4 TE0[0]");
    if (TE0[255] != 1786) @panic("S4 TE0[255]");
    if (GRID[0][0] != 1 or GRID[1][2] != 6) @panic("S5 GRID");
    if (P1.a != 1 or P1.b != 2) @panic("S6 P1");
    if (TUP.0 != 33 or TUP.1 != 44) @panic("S7 TUP");
    if (gh.m[2] != 3) @panic("S8 gh");
    if (gmh.mp[0] != 1) @panic("S8 gmh");
    if (gc.len != 3 or gc[1] != 2) @panic("S9 gc");
    if (gcm[2] != 3) @panic("S9 gcm");
    if (gstr.len != 3 or gstr[0] != 97) @panic("S10 gstr");
    if (gstrp[2] != 99) @panic("S11 gstrp");
    if (sarr[4] != 111) @panic("S12 sarr");
    if (gth.t[10] != 71) @panic("S18 gth");
    if (nonconst != 4) @panic("S19 nonconst");
    if (ub.b != 5) @panic("STOP-1 ub");
    runtime_x = 9;
    std.io.print("{d} {d} {d} {d} {d} {d} {d}\n", .{ SUM, CHAIN2, TE0[1], TE0[255], nonconst, @intCast(u32, ub.b), gth.t[3] });
}
