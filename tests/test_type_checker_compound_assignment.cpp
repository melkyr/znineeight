#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "double_free_analyzer.hpp"

TEST_FUNC(TypeChecker_CompoundAssignment_Valid) {
    const char* source =
        "fn main() void {"
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
        "fn main() void {"
        "  const x: i32 = 10;"
        "  x += 5;"
        "}";
    return expect_type_checker_abort(source);
}

TEST_FUNC(TypeChecker_CompoundAssignment_Bitwise) {
    const char* source =
        "fn main() void {"
        "  var x: u32 = 240u;" // 0xF0u
        "  x &= 15u;"          // 0x0Fu
        "  x |= 255u;"         // 0xFFu
        "  x ^= 170u;"         // 0xAAu
        "  x <<= 2u;"
        "  x >>= 1u;"
        "}";
    if (!run_type_checker_test_successfully(source)) {
        printf("TypeChecker_CompoundAssignment_Bitwise FAILED\n");
        return false;
    }
    return true;
}

TEST_FUNC(TypeChecker_CompoundAssignment_PointerArithmetic) {
    const char* source =
        "fn main() void {"
        "  var x: i32 = 10;"
        "  var p: *i32 = &x;"
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
        "fn main() void {"
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
        "    var p: *u8 = arena_alloc_default(100u);\n"
        "    p += 10u;\n"
        "    arena_free(p);\n"
        "}\n";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker tc(unit);
    tc.check(root);

    DoubleFreeAnalyzer dfa(unit);
    dfa.analyze(root);

    // We expect a memory leak warning (6005) because p is reassigned.
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
