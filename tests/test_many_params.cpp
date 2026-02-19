#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "codegen.hpp"

TEST_FUNC(ManyParameters_Call) {
    const char* source =
        "fn take8(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32) i32 {\n"
        "    return a + b + c + d + e + f + g + h;\n"
        "}\n"
        "fn main() void {\n"
        "    _ = take8(1, 2, 3, 4, 5, 6, 7, 8);\n"
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(ManyParameters_Generic) {
    const char* source =
        "fn genMany(comptime T: type, a: T, b: T, c: T, d: T, e: T) T {\n"
        "    return a;\n"
        "}\n"
        "fn test_caller() void {\n"
        "    _ = genMany(i32, 1, 2, 3, 4, 5);\n"
        "}\n";

    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    // Verify it was catalogued correctly
    ASSERT_EQ(1, unit.getGenericCatalogue().count());
    const GenericInstantiation* inst = &((*unit.getGenericCatalogue().getInstantiations())[0]);
    ASSERT_EQ(6, inst->param_count);
    ASSERT_TRUE(inst->params != NULL);
    ASSERT_EQ(6, inst->params->length());

    return true;
}
