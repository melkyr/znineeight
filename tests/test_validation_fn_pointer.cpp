#include "test_framework.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"

TEST_FUNC(Validation_FunctionPointer_Arithmetic) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var fp: fn() void = foo;\n"
        "    _ = fp + 1;\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_FALSE(unit.performFullPipeline(file_id));

    bool has_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_INVALID_OP_FUNCTION_POINTER) has_error = true;
    }
    ASSERT_TRUE(has_error);

    return true;
}

TEST_FUNC(Validation_FunctionPointer_Relational) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var fp1: fn() void = foo;\n"
        "    var fp2: fn() void = foo;\n"
        "    _ = fp1 < fp2;\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_FALSE(unit.performFullPipeline(file_id));

    bool has_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_INVALID_OP_FUNCTION_POINTER) has_error = true;
    }
    ASSERT_TRUE(has_error);

    return true;
}

TEST_FUNC(Validation_FunctionPointer_Deref) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var fp: fn() void = foo;\n"
        "    _ = fp.*;\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_FALSE(unit.performFullPipeline(file_id));

    bool has_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_DEREF_FUNCTION_POINTER) has_error = true;
    }
    ASSERT_TRUE(has_error);

    return true;
}

TEST_FUNC(Validation_FunctionPointer_Index) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var fp: fn() void = foo;\n"
        "    _ = fp[0];\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_FALSE(unit.performFullPipeline(file_id));

    bool has_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_INDEX_FUNCTION_POINTER) has_error = true;
    }
    ASSERT_TRUE(has_error);

    return true;
}

TEST_FUNC(Validation_FunctionPointer_Equality) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    var fp1: fn() void = foo;\n"
        "    var fp2: fn() void = foo;\n"
        "    var b1: bool = (fp1 == fp2);\n"
        "    var b2: bool = (fp1 != fp2);\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}
