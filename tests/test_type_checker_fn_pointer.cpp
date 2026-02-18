#include "test_framework.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"

TEST_FUNC(TypeChecker_FunctionPointer_Coercion) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo(x: i32) void {}\n"
        "const fp: fn(i32) void = foo;";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_Mismatch) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo(x: i32) void {}\n"
        "const fp: fn(bool) void = foo;";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    // Should fail due to signature mismatch
    ASSERT_FALSE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_Null) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "var fp: fn(i32) void = null;";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_Parameter) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn call_it(fp: fn(i32) void, val: i32) void {\n"
        "    // fp(val); // Not testing calling yet in this phase\n"
        "}\n"
        "fn foo(x: i32) void {}\n"
        "fn bar() void {\n"
        "    call_it(foo, 42);\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}
