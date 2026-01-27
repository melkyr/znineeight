#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "parser.hpp"
#include <string.h>

TEST_FUNC(Integration_ErrorFunctionCatalogue) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const std = @import(\"std\");\n"
        "const MyError = error { Bad, Worse };\n"
        "fn simple() !i32 { return 42; }\n"
        "fn openFile(comptime path: []const u8) !void {}\n"
        "fn readFile() ![]u8 { return \"\"; }\n"
        "fn processFile() !void {\n"
        "    try openFile(\"test.txt\");\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    // 1. Run validator in check-only mode to populate catalogue without aborting
    C89FeatureValidator validator(unit);
    validator.checkOnly(root);

    // 2. Verify catalogue
    // Expected: simple, openFile, readFile, processFile
    ASSERT_EQ(4u, unit.getErrorFunctionCatalogue().getCount());

    bool found_simple = false;
    bool found_open = false;
    bool found_generic = false;

    for (size_t i = 0; i < unit.getErrorFunctionCatalogue().getCount(); ++i) {
        const ErrorFunctionInfo& info = unit.getErrorFunctionCatalogue().getFunction(i);
        if (strcmp(info.name, "simple") == 0) found_simple = true;
        if (strcmp(info.name, "openFile") == 0) {
            found_open = true;
            if (info.is_generic) found_generic = true;
        }
    }

    ASSERT_TRUE(found_simple);
    ASSERT_TRUE(found_open);
    ASSERT_TRUE(found_generic);

    // 3. Run type checker to verify symbol marking
    TypeChecker checker(unit);
    checker.check(root);

    Symbol* sym_simple = unit.getSymbolTable().lookup("simple");
    ASSERT_TRUE(sym_simple != NULL);
    ASSERT_TRUE(sym_simple->returns_error);

    Symbol* sym_open = unit.getSymbolTable().lookup("openFile");
    ASSERT_TRUE(sym_open != NULL);
    ASSERT_TRUE(sym_open->returns_error);
    ASSERT_TRUE(sym_open->is_generic);

    return true;
}
