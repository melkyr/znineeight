#include "test_framework.hpp"
#include "test_debug_config.hpp"
#include "integration/test_compilation_unit.hpp"
#include "platform.hpp"

TEST_FUNC(MainFunction_ReturnInt_VoidReturn) {
    static ArenaAllocator arena(1024 * 1024);
    static StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "pub fn main() void {\n"
        "    return;\n"
        "}\n";

    unit.setCurrentModule("main");
    u32 file = unit.addSource("main.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file));

    // Verify emission
    // We expect: int main(int argc, char* argv[]) { ... return 0; }
    ASSERT_TRUE(unit.validateRealFunctionEmission("main",
        "int main(int argc, char* argv[]) {\n"
        "    return 0;\n"
        "}"));

    return true;
}

TEST_FUNC(MainFunction_ReturnInt_ErrorUnionReturn) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "pub fn main() !void {\n"
        "    return;\n"
        "}\n";

    unit.setCurrentModule("main");
    u32 file = unit.addSource("main.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file));

    // Verify emission
    // The patch forces current_fn_ret_type_ to void for main,
    // so it should NOT try to wrap the return value in an error union.
    ASSERT_TRUE(unit.validateRealFunctionEmission("main",
        "int main(int argc, char* argv[]) {\n"
        "    return 0;\n"
        "}"));

    return true;
}

TEST_FUNC(MainFunction_ImplicitReturn) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "pub fn main() void {\n"
        "}\n";

    unit.setCurrentModule("main");
    u32 file = unit.addSource("main.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file));

    // Verify emission
    ASSERT_TRUE(unit.validateRealFunctionEmission("main",
        "int main(int argc, char* argv[]) {\n"
        "    return 0;\n"
        "}"));

    return true;
}

TEST_FUNC(MainFunction_WithExpression) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "fn helper() void {}\n"
        "pub fn main() void {\n"
        "    helper();\n"
        "}\n";

    unit.setCurrentModule("main");
    u32 file = unit.addSource("main.zig", source);
    if (!unit.performTestPipeline(file)) {
        const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
        for (size_t i = 0; i < errors.length(); ++i) {
            printf("Error: %s\n", errors[i].message);
        }
        ASSERT_TRUE(false);
    }

    // Verify emission
    // It should have an implicit return 0
    // Note: Since module is "main", getC89GlobalName("helper") returns "helper" (special case for main module)
    ASSERT_TRUE(unit.validateRealFunctionEmission("main",
        "int main(int argc, char* argv[]) {\n"
        "    helper();\n"
        "    return 0;\n"
        "}"));

    return true;
}
