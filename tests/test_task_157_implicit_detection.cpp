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

    // Check if implicit instantiation was catalogued
    // Note: Task 156 might have already catalogued it as explicit if it was foo(i32, 10),
    // but here it's foo(10) which is implicit.

    bool found = false;
    const DynamicArray<GenericInstantiation>* insts = catalogue.getInstantiations();
    char buf[128];
    simple_itoa(insts->length(), buf, sizeof(buf));
    plat_print_debug("Instantiations count: ");
    plat_print_debug(buf);
    plat_print_debug("\n");

    for (size_t i = 0; i < insts->length(); ++i) {
        const GenericInstantiation& inst = (*insts)[i];
        if (plat_strcmp(inst.function_name, "genericFn") == 0 && !inst.is_explicit) {
            found = true;
            // Verify inferred types
            ASSERT_EQ(1, inst.param_count);
            ASSERT_TRUE(inst.params[0].type_value != NULL);
            ASSERT_EQ(TYPE_I32, inst.params[0].type_value->kind);
        }
    }

    ASSERT_TRUE(found);

    return true;
}

TEST_FUNC(TypeChecker_AnytypeImplicitDetection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

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
            ASSERT_TRUE(inst.params[0].type_value != NULL);
            ASSERT_EQ(TYPE_F64, inst.params[0].type_value->kind);
        }
    }

    ASSERT_TRUE(found);

    return true;
}
