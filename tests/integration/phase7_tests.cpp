#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"
#include "error_handler.hpp"
#include <cstdio>

TEST_FUNC(Phase7_ValidMutualRecursionPointers) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const A = struct {\n"
        "    b: *B,\n"
        "};\n"
        "const B = struct {\n"
        "    a: *A,\n"
        "};\n"
        "pub fn main() void {\n"
        "    var a: A = undefined;\n"
        "    var b: B = undefined;\n"
        "    a.b = &b;\n"
        "    b.a = &a;\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);

    if (!success) {
        printf("Pipeline failed unexpectedly\n");
    }
    return success && !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(Phase7_InvalidValueCycle) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "pub const A = struct {\n"
        "    b: B,\n"
        "};\n"
        "pub const B = struct {\n"
        "    a: A,\n"
        "};\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    if (unit.getErrorHandler().hasErrors()) {
        const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
        for (size_t i = 0; i < errors.length(); ++i) {
            printf("Error: %s\n", errors[i].message);
        }
    }

    // We expect a "cycle detected" or "incomplete type" error
    return unit.getErrorHandler().hasErrors();
}

TEST_FUNC(Phase7_DefinitionOrderValueDependency) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // A depends on B by value. B must be defined before A in C.
    const char* source =
        "pub const B = struct { x: i32 };\n"
        "pub const A = struct {\n"
        "    b: B,\n"
        "};\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);

    return success && !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(Phase7_PointerDependencyForwardDecl) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // A depends on B by pointer. B definition can follow A.
    const char* source =
        "pub const A = struct {\n"
        "    b: *B,\n"
        "};\n"
        "pub const B = struct { x: i32 };\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);

    return success && !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(Phase7_TaggedUnionStructOrdering) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const Payload = struct { data: i32 };\n"
        "const U = union(enum) {\n"
        "    a: Payload,\n"
        "    b: i32,\n"
        "};\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);

    return success && !unit.getErrorHandler().hasErrors();
}
