#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "double_free_analyzer.hpp"

TEST_FUNC(TypeChecker_CompoundAssignment_Valid) {
    const char* source =
        "fn main_func() void {"
        "  var x: i32 = 10;"
        "  x += 5;"
        "  x -= 2;"
        "  x *= 3;"
        "  x /= 4;"
        "  x %= 3;"
        "}";
    if (!run_type_checker_test_successfully(source)) {
        printf("TypeChecker_CompoundAssignment_Valid FAILED\n");
        return false;
    }
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_InvalidLValue) {
    const char* source =
        "fn main_func() void {"
        "  const x: i32 = 10;"
        "  x += 5;"
        "}";
    return expect_type_checker_abort(source);
}

TEST_FUNC(TypeChecker_CompoundAssignment_Bitwise) {
    const char* source =
        "fn main_func() void {"
        "  var x: u32 = 240;" // 0xF0
        "  x &= 15;"          // 0x0F
        "  x |= 255;"         // 0xFF
        "  x ^= 170;"         // 0xAA
        "  x <<= 2;"
        "  x >>= 1;"
        "}";
    if (!run_type_checker_test_successfully(source)) {
        printf("TypeChecker_CompoundAssignment_Bitwise FAILED\n");
        return false;
    }
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_PointerArithmetic) {
    const char* source =
        "fn main_func() void {"
        "  var p: [*]i32 = undefined;"
        "  p += 1u;"
        "  p -= 1u;"
        "}";
    if (!run_type_checker_test_successfully(source)) {
        printf("TypeChecker_CompoundAssignment_PointerArithmetic FAILED\n");
        return false;
    }
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_InvalidTypes) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    const char* source =
        "fn main_func() void {"
        "  var b: bool = true;"
        "  b += 1;"
        "}";
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker tc(unit);
    tc.check(root);

    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(DoubleFreeAnalyzer_CompoundAssignment) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    const char* source =
        "fn my_ptr_test() void {\n"
        "    var p: [*]u8 = @ptrCast([*]u8, arena_alloc_default(100u));\n"
        "    p += 10u;\n"
        "    arena_free(@ptrCast(*void, p));\n"
        "}\n";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker tc(unit);
    tc.check(root);

    DoubleFreeAnalyzer dfa(unit);
    dfa.analyze(root);

    // We no longer expect a memory leak warning (6005) because p is reassigned but then freed?
    // Actually p += 10u changes p, so original p is lost.
    // But since it's an arena, it's fine?
    // The DoubleFreeAnalyzer currently reports a leak if an AS_ALLOCATED pointer is reassigned.
    const DynamicArray<WarningReport>& warnings = unit.getErrorHandler().getWarnings();
    bool found_leak = false;
    for (size_t i = 0; i < warnings.length(); ++i) {
        if (warnings[i].code == 6005) {
            found_leak = true;
            break;
        }
    }
    ASSERT_TRUE(found_leak);

    return true;
}
