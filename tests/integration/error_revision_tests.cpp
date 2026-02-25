#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include <cstdio>
#include <cstring>

TEST_FUNC(ErrorHandling_DuplicateTags) {
    ArenaAllocator arena(1024 * 64);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // Test duplicate tags in same set
    u32 file_id = unit.addSource("test_dup.zig", "const E = error { Foo, Bar, Foo };");
    unit.performFullPipeline(file_id);

    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    bool found_dup_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_REDEFINITION &&
            errors[i].hint && strstr(errors[i].hint, "Duplicate error tag 'Foo'")) {
            found_dup_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_dup_error);
    return true;
}

TEST_FUNC(ErrorHandling_SetMerging) {
    ArenaAllocator arena(1024 * 64);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const E1 = error { A, B };\n"
        "const E2 = error { B, C };\n"
        "const E3 = E1 || E2;\n";

    u32 file_id = unit.addSource("test_merge.zig", source);
    unit.performFullPipeline(file_id);

    ASSERT_TRUE(!unit.getErrorHandler().hasErrors());

    Symbol* sym = unit.getSymbolTable().lookup("E3");
    ASSERT_TRUE(sym != NULL);
    ASSERT_TRUE(sym->symbol_type->kind == TYPE_ERROR_SET);

    DynamicArray<const char*>* tags = sym->symbol_type->as.error_set.tags;
    ASSERT_TRUE(tags != NULL);
    ASSERT_EQ(3, (int)tags->length());

    bool found_a = false, found_b = false, found_c = false;
    for (size_t i = 0; i < tags->length(); ++i) {
        if (plat_strcmp((*tags)[i], "A") == 0) found_a = true;
        if (plat_strcmp((*tags)[i], "B") == 0) found_b = true;
        if (plat_strcmp((*tags)[i], "C") == 0) found_c = true;
    }
    ASSERT_TRUE(found_a && found_b && found_c);

    return true;
}

TEST_FUNC(ErrorHandling_Layout) {
    ArenaAllocator arena(1024 * 64);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    Type* void_type = get_g_type_void();
    Type* i32_type = get_g_type_i32();
    Type* i64_type = get_g_type_i64();

    Type* eu_void = createErrorUnionType(arena, void_type, NULL, true);
    Type* eu_i32 = createErrorUnionType(arena, i32_type, NULL, true);
    Type* eu_i64 = createErrorUnionType(arena, i64_type, NULL, true);

    // !void: struct { int err; int is_error; } -> size 8, align 4
    ASSERT_EQ(8, (int)eu_void->size);
    ASSERT_EQ(4, (int)eu_void->alignment);

    // !i32: struct { union { i32 payload; int err; } data; int is_error; }
    // union size 4, align 4. struct size 8, align 4
    ASSERT_EQ(8, (int)eu_i32->size);
    ASSERT_EQ(4, (int)eu_i32->alignment);

    // !i64: struct { union { i64 payload; int err; } data; int is_error; }
    // union size 8, align 8 (because of i64). struct size 16, align 8
    // data at 0, is_error at 8. Total 12 -> padded to 16.
    ASSERT_EQ(16, (int)eu_i64->size);
    ASSERT_EQ(8, (int)eu_i64->alignment);

    return true;
}
