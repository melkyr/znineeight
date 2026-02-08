#include "../src/include/test_framework.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/type_checker.hpp"
#include "../src/include/generic_catalogue.hpp"
#include "../src/include/utils.hpp"
#include "test_utils.hpp"

TEST_FUNC(TypeChecker_ImplicitGenericDetection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* zig_source =
        "fn genericFn(comptime T: type, x: T) T {\n"
        "    return x;\n"
        "}\n"
        "\n"
        "fn main() void {\n"
        "    const a = genericFn(10);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", zig_source);

    // We need to run the full pipeline or at least Parser -> TypeChecker
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    const GenericCatalogue& catalogue = unit.getGenericCatalogue();

    bool found = false;
    const DynamicArray<GenericInstantiation>* insts = catalogue.getInstantiations();

    for (size_t i = 0; i < insts->length(); ++i) {
        const GenericInstantiation& inst = (*insts)[i];
        if (plat_strcmp(inst.function_name, "genericFn") == 0 && !inst.is_explicit) {
            found = true;
            // Verify inferred types
            ASSERT_EQ(1, inst.param_count);
            ASSERT_TRUE(inst.arg_types[0] != NULL);
            ASSERT_EQ(TYPE_I32, inst.arg_types[0]->kind);
        }
    }

    ASSERT_TRUE(found);

    return true;
}

TEST_FUNC(TypeChecker_MultipleImplicitInstantiations) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* zig_source =
        "fn genericFn(x: anytype) void {\n"
        "    _ = x;\n"
        "}\n"
        "\n"
        "fn main() void {\n"
        "    genericFn(10);\n"
        "    genericFn(3.14);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", zig_source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    const GenericCatalogue& catalogue = unit.getGenericCatalogue();
    const DynamicArray<GenericInstantiation>* insts = catalogue.getInstantiations();

    int found_count = 0;
    bool found_i32 = false;
    bool found_f64 = false;

    for (size_t i = 0; i < insts->length(); ++i) {
        const GenericInstantiation& inst = (*insts)[i];
        if (plat_strcmp(inst.function_name, "genericFn") == 0 && !inst.is_explicit) {
            found_count++;
            if (inst.arg_types[0]->kind == TYPE_I32) found_i32 = true;
            if (inst.arg_types[0]->kind == TYPE_F64) found_f64 = true;
        }
    }

    ASSERT_EQ(2, found_count);
    ASSERT_TRUE(found_i32);
    ASSERT_TRUE(found_f64);

    return true;
}

TEST_FUNC(TypeChecker_AnytypeImplicitDetection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* zig_source =
        "fn anytypeFn(x: anytype) void {\n"
        "    _ = x;\n"
        "}\n"
        "\n"
        "fn main() void {\n"
        "    anytypeFn(3.14);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", zig_source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    const GenericCatalogue& catalogue = unit.getGenericCatalogue();

    bool found = false;
    const DynamicArray<GenericInstantiation>* insts = catalogue.getInstantiations();
    for (size_t i = 0; i < insts->length(); ++i) {
        const GenericInstantiation& inst = (*insts)[i];
        if (plat_strcmp(inst.function_name, "anytypeFn") == 0 && !inst.is_explicit) {
            found = true;
            ASSERT_EQ(1, inst.param_count);
            ASSERT_TRUE(inst.arg_types[0] != NULL);
            ASSERT_EQ(TYPE_F64, inst.arg_types[0]->kind);
        }
    }

    ASSERT_TRUE(found);

    return true;
}
