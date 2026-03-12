#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"

TEST_FUNC(IssueSegfaultReturn) {
    ArenaAllocator arena(262144); // 256KB
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "const JsonValue = union(enum) {\n"
        "    Null: void,\n"
        "    Boolean: bool,\n"
        "};\n"
        "\n"
        "fn makeBoolean(b: bool) JsonValue {\n"
        "    if (b) {\n"
        "        return JsonValue{ .Boolean = true };\n"
        "    } else {\n"
        "        return JsonValue{ .Null = {} };\n"
        "    }\n"
        "}\n"
        "\n"
        "pub fn main() void {\n"
        "    _ = makeBoolean(true);\n"
        "}\n";

    ParserTestContext ctx(source, arena, interner);
    CompilationUnit& unit = ctx.getCompilationUnit();

    // No need to inject runtime symbols for this test as it doesn't use print/alloc
    // unit.injectRuntimeSymbols();

    Parser* parser = ctx.getParser();
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(unit);
    type_checker.check(ast);

    // Verify no errors
    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
    }
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    return true;
}
