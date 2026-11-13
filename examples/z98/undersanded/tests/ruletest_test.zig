// ruletest_test.zig — native Linux driver for the M3 `--test-rules` matrix
// (spec §34 T5). Asserts the real run passes all 100 combinations and that the
// count helper agrees; non-zero exit on any failure.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/ruletest_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/ruletest_test"
//   "$OUT/ruletest_test"

const io = @import("std_io");
const os = @import("std_os");
const ruletest = @import("../ruletest.zig");

pub fn main() void {
    const rc = ruletest.testRules();
    if (rc != 0) {
        io.write("ruletest_test FAIL\n");
        os.exit(1);
    }

    if (ruletest.rulePassCount() != 100) {
        io.write("ruletest_test FAIL (count)\n");
        os.exit(1);
    }

    io.write("ruletest_test PASS\n");
}
