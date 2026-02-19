#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "signature_analyzer.hpp"

TEST_FUNC(TypeChecker_ManyParams_FunctionPointer) {
    const char* source =
        "const fp: fn(i32, i32, i32, i32, i32, i32, i32, i32, "
        "            i32, i32, i32, i32, i32, i32, i32, i32, "
        "            i32, i32, i32, i32, i32, i32, i32, i32, "
        "            i32, i32, i32, i32, i32, i32, i32, i32) void = undefined;\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));
    return true;
}

TEST_FUNC(TypeChecker_ManyParams_GenericInstantiation) {
    const char* source =
        "fn generic(comptime T: type, "
        "           p1: T, p2: T, p3: T, p4: T, p5: T, p6: T, p7: T, p8: T, "
        "           p9: T, p10: T, p11: T, p12: T, p13: T, p14: T, p15: T, p16: T, "
        "           p17: T, p18: T, p19: T, p20: T, p21: T, p22: T, p23: T, p24: T, "
        "           p25: T, p26: T, p27: T, p28: T, p29: T, p30: T, p31: T, p32: T) void {}\n"
        "fn main() void {\n"
        "    generic(i32, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, "
        "                 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);\n"
        "}\n";

    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    // Generic calls are still rejected by C89FeatureValidator, but should pass TypeChecker and be catalogued
    // Let's just run TypeChecker to verify it doesn't crash and handles 32 params.
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    const GenericCatalogue& catalogue = unit.getGenericCatalogue();
    ASSERT_EQ(1, catalogue.count());
    const GenericInstantiation& inst = (*catalogue.getInstantiations())[0];
    ASSERT_EQ(33, inst.param_count); // T + 32 params

    return true;
}
