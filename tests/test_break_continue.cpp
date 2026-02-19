#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"

TEST_FUNC(TypeChecker_BreakContinue_InLoop) {
    const char* source =
        "fn test_func() void {\n"
        "    while (true) {\n"
        "        break;\n"
        "        continue;\n"
        "    }\n"
        "    var arr: [5]i32 = undefined;\n"
        "    for (arr) |item| {\n"
        "        break;\n"
        "        continue;\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));
    return true;
}

TEST_FUNC(TypeChecker_BreakOutsideLoop_Error) {
    const char* source =
        "fn test_func() void {\n"
        "    break;\n"
        "}\n";

    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_FALSE(unit.performFullPipeline(file_id));

    bool found_error = false;
    for (size_t i = 0; i < unit.getErrorHandler().getErrors().length(); ++i) {
        if (unit.getErrorHandler().getErrors()[i].code == ERR_BREAK_OUTSIDE_LOOP) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);
    return true;
}

TEST_FUNC(TypeChecker_ContinueOutsideLoop_Error) {
    const char* source =
        "fn test_func() void {\n"
        "    continue;\n"
        "}\n";

    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_FALSE(unit.performFullPipeline(file_id));

    bool found_error = false;
    for (size_t i = 0; i < unit.getErrorHandler().getErrors().length(); ++i) {
        if (unit.getErrorHandler().getErrors()[i].code == ERR_CONTINUE_OUTSIDE_LOOP) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);
    return true;
}

TEST_FUNC(TypeChecker_BreakInDefer_Error) {
    const char* source =
        "fn test_func() void {\n"
        "    while (true) {\n"
        "        defer { break; }\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_FALSE(unit.performFullPipeline(file_id));

    bool found_error = false;
    for (size_t i = 0; i < unit.getErrorHandler().getErrors().length(); ++i) {
        if (unit.getErrorHandler().getErrors()[i].code == ERR_BREAK_OUTSIDE_LOOP) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);
    return true;
}

TEST_FUNC(TypeChecker_BreakInSwitchInLoop) {
    const char* source =
        "fn test_func(x: i32) void {\n"
        "    while (true) {\n"
        "        switch (x) {\n"
        "            1 => { break; },\n"
        "            else => {},\n"
        "        };\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));
    return true;
}
