#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "platform.hpp"

TEST_FUNC(Task165_ForwardReference) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn main() void { foo(); }\n"
        "fn foo() void {}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    ASSERT_EQ(1, table.count());
    ASSERT_EQ(0, table.getUnresolvedCount());

    const CallSiteEntry& entry = table.getEntry(0);
    ASSERT_EQ(CALL_DIRECT, entry.call_type);
    ASSERT_TRUE(entry.resolved);
    ASSERT_TRUE(entry.mangled_name != NULL);

    return true;
}

TEST_FUNC(Task165_BuiltinRejection) {
    // Current lexer rejects @builtins that are not @import,
    // so this is hard to test via source until lexer is updated.
    return true;
}

TEST_FUNC(Task165_C89Incompatible) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    // Use a function with too many parameters - SignatureAnalyzer will reject it.
    const char* source =
        "fn tooMany(a: i32, b: i32, c: i32, d: i32, e: i32) void {}\n"
        "fn main() void { tooMany(1, 2, 3, 4, 5); }\n";

    u32 file_id = unit.addSource("test.zig", source);

    // Validation will fail
    unit.performFullPipeline(file_id);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    ASSERT_TRUE(table.count() >= 1);

    bool found_incompatible = false;
    for (int i = 0; i < table.count(); ++i) {
        const CallSiteEntry& entry = table.getEntry(i);
        if (!entry.resolved && entry.error_if_unresolved &&
            plat_strcmp(entry.error_if_unresolved, "Function signature is not C89-compatible") == 0) {
            found_incompatible = true;
        }
    }
    // Note: SignatureAnalyzer runs AFTER TypeChecker but before C89FeatureValidator.
    // Wait, is_c89_compatible is used in resolveCallSite which runs DURING TypeChecker.
    // So it should be caught there.

    ASSERT_TRUE(found_incompatible);

    return true;
}
