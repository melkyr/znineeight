#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "generic_catalogue.hpp"

TEST_FUNC(C89Rejection_ExplicitGeneric) {
    const char* source = "fn main() void { max(i32, 1, 2); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(C89Rejection_ImplicitGeneric) {
    const char* source = "fn max(comptime T: type, a: T, b: T) T { return a; }\n fn main() void { max(1, 2); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(GenericCatalogue_TracksExplicit) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    // Use a source that doesn't abort if we skip validation
    const char* source = "fn bar(comptime T: type, a: i32) void {}\n fn main() void { bar(i32, 1); }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    // We expect it NOT to abort if we don't call the validator.
    // Wait, TypeChecker also has some fatalError calls, but let's see.
    checker.check(ast);

    ASSERT_EQ(1, unit.getGenericCatalogue().count());
    const GenericInstantiation& inst = (*unit.getGenericCatalogue().getInstantiations())[0];
    ASSERT_STREQ("bar", inst.function_name);
    ASSERT_EQ(2, inst.param_count);

    return true;
}

TEST_FUNC(Task155_AllTemplateFormsDetectedAndRejected) {
    const char* source =
        "fn explicit_fn(comptime T: type, x: T) T { return x; }\n"
        "fn implicit_fn(anytype x) void {}\n"
        "fn test_caller() void {\n"
        "    _ = explicit_fn(i32, 5);  // explicit instantiation\n"
        "    implicit_fn(42);      // implicit instantiation\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}

TEST_FUNC(Task155_TypeParamRejected) {
    const char* source = "fn f(comptime T: type) void {}";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task155_AnytypeParamRejected) {
    const char* source = "fn f(anytype x) void {}";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(GenericCatalogue_TracksImplicit) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source = "fn max(comptime T: i32, a: i32, b: i32) i32 { return a; }\n fn main() void { max(1, 2, 3); }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    ASSERT_EQ(1, unit.getGenericCatalogue().count());
    const GenericInstantiation& inst = (*unit.getGenericCatalogue().getInstantiations())[0];
    ASSERT_STREQ("max", inst.function_name);

    return true;
}

TEST_FUNC(C89Rejection_ComptimeValueParam) {
    const char* source = "fn makeArray(comptime n: i32) void {}\n fn main() void { makeArray(10); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(GenericCatalogue_Deduplication) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source = "fn generic(comptime T: type) void {}\n fn main() void { generic(i32); generic(i32); }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    ASSERT_EQ(1, unit.getGenericCatalogue().count());

    return true;
}
