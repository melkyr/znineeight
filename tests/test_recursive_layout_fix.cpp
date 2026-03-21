#include "test_framework.hpp"
#include "type_system.hpp"
#include "compilation_unit.hpp"
#include "platform.hpp"
#include "integration/test_compilation_unit.hpp"

TEST_FUNC(RecursiveTaggedUnionSize) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    unit.addSource("test.zig", "");
    Module* mod = unit.getModuleByFilename("test.zig");

    // We want to simulate JsonValue:
    // union(enum) JsonValue {
    //     Null: void,
    //     Bool: bool,
    //     Number: f64,
    //     String: []const u8,
    //     Array: []const JsonValue,
    //     Object: []const JsonObjectEntry,
    // }
    // struct JsonObjectEntry {
    //     key: []const u8,
    //     value: JsonValue,
    // }

    // This is complex to set up manually with placeholders.
    // But we can check if pointer-like types have the correct size even with placeholders.

    Type* placeholder = (Type*)arena.alloc(sizeof(Type));
    plat_memset(placeholder, 0, sizeof(Type));
    placeholder->kind = TYPE_PLACEHOLDER;
    placeholder->as.placeholder.name = "Recursive";
    placeholder->as.placeholder.module = mod;

    Type* ptr_to_placeholder = createPointerType(arena, placeholder, true, false, NULL);
    Type* slice_of_placeholder = createSliceType(arena, placeholder, true, NULL);
    createOptionalType(arena, placeholder, NULL);

    ASSERT_EQ((long)ptr_to_placeholder->size, 4L);
    ASSERT_EQ((long)slice_of_placeholder->size, 8L);

    // Now let's check calculateTaggedUnionLayout with a field that is a pointer to placeholder.
    DynamicArray<StructField>* fields = (DynamicArray<StructField>*)arena.alloc(sizeof(DynamicArray<StructField>));
    new (fields) DynamicArray<StructField>(arena);

    StructField f1;
    f1.name = "f1";
    f1.type = ptr_to_placeholder;
    f1.offset = 0;
    fields->append(f1);

    Type* tagged = createTaggedUnionType(unit, mod, fields, get_g_type_i32(), "Tagged", NULL);
    // createTaggedUnionType calls calculateTaggedUnionLayout.

    // Tag (4) + Union (4) = 8.
    ASSERT_EQ((long)tagged->size, 8L);

    return true;
}

TEST_FUNC(JsonValueRecursiveSize) {
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
    ASSERT_TRUE(unit.performTestPipeline(file));

    // Verify size of JsonValue
    Symbol* sym = unit.getSymbolTable().lookup("JsonValue");
    ASSERT_TRUE(sym != NULL);
    Type* json_type = sym->symbol_type;
    ASSERT_TRUE(json_type != NULL);
    ASSERT_TRUE(json_type->kind == TYPE_TAGGED_UNION || json_type->kind == TYPE_UNION);

    // Tag (4) + Padding (4) + Union(max(void:0, f64:8, slice:8) = 8) = 16
    // Alignment should be 8 because of f64 and slice alignment
    ASSERT_EQ((long)json_type->size, 16L);
    ASSERT_EQ((long)json_type->alignment, 8L);

    return true;
}
