#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "platform.hpp"

bool test_TypeChecker_CallSiteRecording_Direct() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn foo() void {}\n"
        "fn main() void { foo(); }\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    // main() calls foo()
    ASSERT_EQ(1, table.count());
    ASSERT_EQ(0, table.getUnresolvedCount());

    const CallSiteEntry& entry = table.getEntry(0);
    ASSERT_TRUE(plat_strcmp(entry.context, "main") == 0);
    ASSERT_EQ(CALL_DIRECT, entry.call_type);
    ASSERT_TRUE(entry.mangled_name != NULL);
    // Based on NameMangler, it should be main_foo (if module is main) or similar
    // Actually it should be "foo" if it's not generic and module is main and it's C89 safe.

    return true;
}

bool test_TypeChecker_CallSiteRecording_Recursive() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn factorial(n: i32) i32 {\n"
        "    if (n <= 1) { return 1; }\n"
        "    return n * factorial(n - 1);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    ASSERT_EQ(1, table.count());
    ASSERT_EQ(0, table.getUnresolvedCount());

    const CallSiteEntry& entry = table.getEntry(0);
    ASSERT_TRUE(plat_strcmp(entry.context, "factorial") == 0);
    ASSERT_EQ(CALL_RECURSIVE, entry.call_type);

    return true;
}

bool test_TypeChecker_CallSiteRecording_Generic() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn identity(comptime T: type, x: T) T { return x; }\n"
        "fn main() void {\n"
        "    identity(i32, 42);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    // performFullPipeline might return false because Generic functions are rejected by C89FeatureValidator
    // but we want to check if they were recorded in the CallSiteLookupTable
    unit.performFullPipeline(file_id);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    ASSERT_TRUE(table.count() >= 1);

    // We need to find the entry for identity
    bool found = false;
    for (int i = 0; i < table.count(); ++i) {
        const CallSiteEntry& entry = table.getEntry(i);
        if (plat_strcmp(entry.context, "main") == 0) {
            ASSERT_EQ(CALL_GENERIC, entry.call_type);
            ASSERT_TRUE(entry.resolved);
            ASSERT_TRUE(entry.mangled_name != NULL);
            // It should look like identity__i32
            found = true;
            break;
        }
    }
    ASSERT_TRUE(found);

    return true;
}
