#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "type_checker.hpp"

TEST_FUNC(Task9_8_StringLiteralCoercion) {
    const char* source =
        "fn takesSlice(s: []const u8) usize {\n"
        "    return s.len;\n"
        "}\n"
        "pub fn main() void {\n"
        "    var slice: []const u8 = \"hello\";\n"
        "    _ = slice;\n"
        "    const len = takesSlice(\"world\");\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(Task9_8_ImplicitReturnErrorVoid) {
    const char* source =
        "fn foo() anyerror!void {\n"
        "    // no explicit return\n"
        "}\n"
        "pub fn main() void {\n"
        "    foo() catch unreachable;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(Task9_8_SlicePtrMember) {
    const char* source =
        "fn getPtr(s: []const u8) [*]const u8 {\n"
        "    return s.ptr;\n"
        "}\n"
        "pub fn main() void {\n"
        "    var slice: []const u8 = \"abc\";\n"
        "    const p = slice.ptr;\n"
        "    _ = p;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(Task9_8_WhileContinueExpr) {
    const char* source =
        "pub fn sum_up_to(n: u32) u32 {\n"
        "    var i: u32 = 0;\n"
        "    var total: u32 = 0;\n"
        "    while (i < n) : (i += 1) {\n"
        "        total += i;\n"
        "    }\n"
        "    return total;\n"
        "}\n"
        "pub fn main() void {\n"
        "    _ = sum_up_to(10);\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }
    return true;
}

TEST_FUNC(Task9_8_StringLiteralCoercion_MutableRejection) {
    const char* source =
        "pub fn main() void {\n"
        "    var slice: []u8 = \"hello\";\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
