#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include <cstdio>
#include <cstring>
#include <cstdlib>

// Helper to check if a string contains another string
static bool string_contains(const char* haystack, const char* needle) {
    if (!haystack || !needle) return false;
    return strstr(haystack, needle) != NULL;
}

// Helper to run syntax-only compilation check
static bool compile_check(const char* code) {
    FILE* f = fopen("test_task_148.c", "w");
    if (!f) return false;
    fprintf(f, "#include <string.h>\n");
    fprintf(f, "struct PlaceholderStruct { int dummy; };\n");
    fprintf(f, "struct PlaceholderArray { int dummy; };\n");
    fprintf(f, "%s\n", code);
    fclose(f);

    // Use gcc -std=c89 -fsyntax-only for validation in Linux environment
    int result = system("gcc -std=c89 -fsyntax-only test_task_148.c");

    // Clean up
    remove("test_task_148.c");

    return result == 0;
}

TEST_FUNC(Task148_PatternGeneration_StructReturn) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    unit.setTestMode(true);

    const char* source = "fn foo() !i32 { return 42; }";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    C89FeatureValidator validator(unit);
    validator.visitAll(ast);

    unit.testErrorPatternGeneration();

    ASSERT_EQ(1, unit.getGeneratedPatternCount());
    const char* pattern = unit.getGeneratedPattern(0);
    ASSERT_TRUE(pattern != NULL);

    ASSERT_TRUE(string_contains(pattern, "typedef struct {"));
    ASSERT_TRUE(string_contains(pattern, "int value;"));
    ASSERT_TRUE(string_contains(pattern, "int is_error;"));
    ASSERT_TRUE(string_contains(pattern, "foo(void)"));

    // Syntax check
    ASSERT_TRUE(compile_check(pattern));

    return true;
}

TEST_FUNC(Task148_PatternGeneration_OutParameter) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    unit.setTestMode(true);

    // Use a struct to avoid array-pointer syntax issues in this simple generator
    const char* source = "const Large = struct { data: [2048]u8 };\n"
                         "fn large() !Large { return undefined; }";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    C89FeatureValidator validator(unit);
    validator.visitAll(ast);

    unit.testErrorPatternGeneration();

    ASSERT_EQ(1, unit.getGeneratedPatternCount());
    const char* pattern = unit.getGeneratedPattern(0);

    ASSERT_TRUE(string_contains(pattern, "int large("));
    ASSERT_TRUE(string_contains(pattern, "struct"));
    ASSERT_TRUE(string_contains(pattern, "out_value"));

    // Syntax check
    ASSERT_TRUE(compile_check(pattern));

    return true;
}

TEST_FUNC(Task148_PatternGeneration_Arena) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    unit.setTestMode(true);

    // Payload size 128 forces Arena (64 < 128 <= 1024)
    const char* source = "const Medium = struct { data: [128]u8 };\n"
                         "fn medium() !Medium { return undefined; }";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    C89FeatureValidator validator(unit);
    validator.visitAll(ast);

    unit.testErrorPatternGeneration();

    ASSERT_EQ(1, unit.getGeneratedPatternCount());
    const char* pattern = unit.getGeneratedPattern(0);

    ASSERT_TRUE(string_contains(pattern, "typedef struct {"));
    ASSERT_TRUE(string_contains(pattern, "struct"));
    ASSERT_TRUE(string_contains(pattern, "value_ptr;"));
    ASSERT_TRUE(string_contains(pattern, "medium(void* arena)"));

    // Syntax check
    ASSERT_TRUE(compile_check(pattern));

    return true;
}
