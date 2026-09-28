// sig_unknown_type_reject_xmod — FX13-F (Volume II ch12) reject fixture.
//
// Before FX13-F an unresolvable type name in a function signature degraded
// silently: a parameter became C `int`, a return became `void`, and the
// program compiled rc 0 with zero diagnostics. The ruled diagnostic is the
// existing level-0 `error[20]` (`ERR_3001_UNDEFINED_SYMBOL`, exact text
// `identifier '<x>' is not declared or imported in this module`), one per
// unresolved leaf node, deduped via `diagnosticCollectorMarkNodeOnce`.
//
// Census (10 sites, one diagnostic each; every function is unreferenced so
// the new diagnostic is the only rejection):
//   pBare   bare parameter name        span: the ident
//   rBare   bare return name           span: the ident
//   wPtr    `*bogusptr` parameter      span: the inner ident
//   wArr    `[3]bogusarr` parameter    span: the inner ident
//   wOpt    `?bogusopt` parameter      span: the inner ident
//   wSlc    `[]bogusslc` parameter     span: the inner ident
//   xMod    `helper.Missing` param     span: the `helper.Missing` node
//   fpInner fn-pointer inner unknown   span: the inner ident
//   eParam  `extern fn` unknown param  span: the ident
//   eRet    `extern fn` unknown return span: the ident
//
// Contract: dump rc 2, 0 `.c`, exactly 10 x `error[20]`, no other codes, no
// signals. Known forms (`helper.Good`) are covered by the positive control
// `sig_known_type_ok_xmod`.
const std = @import("std");
const helper = @import("helper.zig");

fn pBare(x: bogustype) void {}

fn rBare() bogusret {}

fn wPtr(x: *bogusptr) void {}

fn wArr(x: [3]bogusarr) void {}

fn wOpt(x: ?bogusopt) void {}

fn wSlc(x: []bogusslc) void {}

fn xMod(h: helper.Missing) void {}

fn fpInner(cb: fn (bogusfp) void) void {}

extern fn eParam(x: bogusxp) void;

extern fn eRet() bogusxr;

pub fn main() void {
    std.io.printInt(9);
}
