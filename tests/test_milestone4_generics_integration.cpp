#include "../src/include/test_framework.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/type_checker.hpp"
#include "../src/include/c89_feature_validator.hpp"
#include "../src/include/generic_catalogue.hpp"
#include "test_utils.hpp"

TEST_FUNC(Milestone4_GenericsIntegration_MixedCalls) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* zig_source =
        "fn generic(comptime T: type, x: T) T { return x; }\n"
        "fn main() void {\n"
        "    var a: i32 = generic(i32, 10);\n"
        "    var b: i32 = generic(20);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", zig_source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    // Verify both instantiations are in the catalogue
    const GenericCatalogue& catalogue = unit.getGenericCatalogue();
    ASSERT_EQ(2, catalogue.count());

    // Verify rejection
    ASSERT_TRUE(expect_type_checker_abort(zig_source));

    return true;
}

TEST_FUNC(Milestone4_GenericsIntegration_ComplexParams) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    // Test with multiple generic params and mixed types
    const char* zig_source =
        "fn complex(comptime T: type, comptime U: type, x: T, y: U) void {}\n"
        "fn main() void {\n"
        "    complex(i32, f64, 10, 3.14);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", zig_source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    const GenericCatalogue& catalogue = unit.getGenericCatalogue();
    ASSERT_EQ(1, catalogue.count());

    const GenericInstantiation& inst = (*catalogue.getInstantiations())[0];
    ASSERT_EQ(4, inst.param_count); // T, U, x, y (wait, does it count all or just generic?)
    // Actually TypeChecker::catalogGenericInstantiation loops through all arguments of the call.

    ASSERT_EQ(TYPE_I32, inst.arg_types[2]->kind);
    ASSERT_EQ(TYPE_F64, inst.arg_types[3]->kind);

    ASSERT_TRUE(expect_type_checker_abort(zig_source));

    return true;
}
