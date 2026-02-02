#include "test_declarations.hpp"
#include "compilation_unit.hpp"
#include "test_framework.hpp"
#include "test_utils.hpp"
#include <cstring>

TEST_FUNC(C89Rejection_GenericFnDecl_ShouldBeRejected) {
    const char* source = "fn foo(comptime T: i32) void {}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    u32 file_id = unit.addSource("test.zig", source);

    // Pass 0 & 1
    unit.performFullPipeline(file_id);

    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    bool found_msg = false;
    for (size_t i = 0; i < unit.getErrorHandler().getErrors().length(); ++i) {
        if (strstr(unit.getErrorHandler().getErrors()[i].message, "comptime parameters")) {
            found_msg = true;
            break;
        }
    }
    ASSERT_TRUE(found_msg);
    return true;
}

TEST_FUNC(C89Rejection_DeferAndErrDefer) {
    const char* source =
        "fn main() void {\n"
        "    defer { var x: i32 = 1; }\n"
        "    errdefer { var y: i32 = 2; }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    bool found_errdefer = false;
    bool found_defer_error = false;

    for (size_t i = 0; i < unit.getErrorHandler().getErrors().length(); ++i) {
        const char* msg = unit.getErrorHandler().getErrors()[i].message;
        if (strstr(msg, "errdefer statements are not supported")) {
            found_errdefer = true;
        } else if (strstr(msg, "defer statements are not supported")) {
            // This should only match if "errdefer" is NOT present in this specific string
            // but since we are in else if, it already ensures it didn't match the first one.
            found_defer_error = true;
        }
    }

    ASSERT_TRUE(found_errdefer);
    ASSERT_FALSE(found_defer_error);

    return true;
}

TEST_FUNC(C89Rejection_ErrorTypeInParam_ShouldBeRejected) {
    const char* source = "fn foo(x: !i32) void {}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    ASSERT_TRUE(unit.getErrorHandler().getErrors().length() > 0);
    return true;
}

TEST_FUNC(Task150_MoreComprehensiveElimination) {
    // A complex case with multiple error handling features
    const char* source =
        "fn foo(x: i32) !i32 { if (x > 0) { return x; } return 0; }\n"
        "fn main() void {\n"
        "    var res: i32 = foo(1) catch 0;\n"
        "    var res2: i32 = 0;\n"
        "    if (res > 0) { res2 = try foo(res); }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    // Should have multiple errors
    ASSERT_TRUE(unit.getErrorHandler().getErrors().length() > 0);
    // But they should all be conceptually eliminated
    ASSERT_TRUE(unit.areErrorTypesEliminated());

    return true;
}

TEST_FUNC(C89Rejection_ArraySliceExpression) {
    const char* source = "fn main() void { var a: [10]i32 = undefined; var b = a[0..5]; }";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    bool found_msg = false;
    for (size_t i = 0; i < unit.getErrorHandler().getErrors().length(); ++i) {
        if (strstr(unit.getErrorHandler().getErrors()[i].message, "Array slices are not supported")) {
            found_msg = true;
            break;
        }
    }
    ASSERT_TRUE(found_msg);
    return true;
}
