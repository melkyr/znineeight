#include "test_framework.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"

TEST_FUNC(Integration_ManyItemFunctionPointer) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var fps: [*]fn() void = undefined;\n"
        "    _ = fps[0]();\n"
        "}";

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(Integration_FunctionPointerPtrCast) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var p: *void = @ptrCast(*void, foo);\n"
        "    var fp: fn() void = @ptrCast(fn() void, p);\n"
        "    fp();\n"
        "}";

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(Integration_MultiLevelFunctionPointer) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var fp: fn() void = foo;\n"
        "    var pfp: *fn() void = &fp;\n"
        "    var ppfp: **fn() void = &pfp;\n"
        "    ppfp.*.*();\n"
        "}";

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}
