#include "test_framework.hpp"
#include "integration/test_compilation_unit.hpp"
#include "platform.hpp"

TEST_FUNC(MainFunction_ReturnInt_Validation) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "pub fn main() void {\n"
        "    return;\n"
        "}\n";

    unit.setCurrentModule("main");
    u32 file = unit.addSource("main.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file));

    // Verify emission
    // We expect: int main(int argc, char* argv[]) { ... return 0; }
    ASSERT_TRUE(unit.validateRealFunctionEmission("main",
        "int main(int argc, char* argv[]) {\n"
        "    return 0;\n"
        "}"));

    return true;
}

TEST_FUNC(MainFunction_ErrorUnion_Validation) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "pub fn main() !void {\n"
        "}\n";

    unit.setCurrentModule("main");
    u32 file = unit.addSource("main.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file));

    // Implicit return 0 for main even if it returns !void
    ASSERT_TRUE(unit.validateRealFunctionEmission("main",
        "int main(int argc, char* argv[]) {\n"
        "    return 0;\n"
        "}"));

    return true;
}

TEST_FUNC(RecursiveTaggedUnion_LayoutValidation) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    const char* source =
        "const JsonValue = union(enum) {\n"
        "    Null: void,\n"
        "    Number: f64,\n"
        "    Array: []JsonValue,\n"
        "};\n"
        "pub fn main() void {\n"
        "    var x: JsonValue = undefined;\n"
        "}\n";

    unit.setCurrentModule("main");
    u32 file = unit.addSource("main.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file));

    // Verify size of JsonValue
    Symbol* sym = unit.getSymbolTable().lookup("JsonValue");
    ASSERT_TRUE(sym != NULL);
    Type* json_type = sym->symbol_type;
    ASSERT_TRUE(json_type != NULL);

    // Tag (4) + Padding (4) + Union(max(void:0, f64:8, slice:8) = 8) = 16
    // Alignment should be 8 because of f64 and slice alignment
    ASSERT_EQ((long)json_type->size, 16L);
    ASSERT_EQ((long)json_type->alignment, 8L);

    return true;
}
