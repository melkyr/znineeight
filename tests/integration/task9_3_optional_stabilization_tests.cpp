#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "type_system.hpp"
#include "type_checker.hpp"

TEST_FUNC(OptionalStabilization_UndefinedPayload) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    // Undefined type 'Unknown' - should not crash
    const char* source =
        "pub fn main() void {\n"
        "    var x: ?Unknown = null;\n"
        "}\n";
    u32 main_id = unit.addSource("main.zig", source);

    // We expect this NOT to crash, even though it will have a type error
    unit.performTestPipeline(main_id);

    return true;
}

TEST_FUNC(OptionalStabilization_RecursiveOptional) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    // Recursive optional - should not crash
    const char* source =
        "const Node = struct {\n"
        "    data: i32,\n"
        "    next: ?Node,\n"
        "};\n"
        "pub fn main() void {\n"
        "    var x: Node = undefined;\n"
        "}\n";
    u32 main_id = unit.addSource("main.zig", source);

    unit.performTestPipeline(main_id);

    return true;
}

TEST_FUNC(OptionalStabilization_AlignedLayout) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    // Check size of ?f64
    // f64 size 8, align 8.
    // ?f64 should be size 16, align 8.
    const char* source =
        "var x: ?f64 = null;\n"
        "pub fn main() void {\n"
        "}\n";
    u32 main_id = unit.addSource("main.zig", source);

    unit.performTestPipeline(main_id);

    Symbol* sym = unit.getSymbolTable().lookup("x");
    ASSERT_TRUE(sym != NULL);
    Type* type = sym->symbol_type;
    ASSERT_EQ(TYPE_OPTIONAL, type->kind);

    // Size should be 16, Alignment 8
    ASSERT_EQ(16, type->size);
    ASSERT_EQ(8, type->alignment);

    return true;
}
