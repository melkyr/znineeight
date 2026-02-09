#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "platform.hpp"

TEST_FUNC(Recursive_Factorial) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn factorial(n: i32) i32 {\n"
        "    if (n <= 1) { return 1; }\n"
        "    return n * factorial(n - 1);\n"
        "}\n"
        "fn main() void {\n"
        "    var x: i32 = factorial(5);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    // 1. factorial calling itself
    // 2. main calling factorial
    ASSERT_EQ(2, table.count());

    bool found_recursive = false;
    bool found_direct = false;

    for (int i = 0; i < table.count(); ++i) {
        const CallSiteEntry& entry = table.getEntry(i);
        if (plat_strcmp(entry.context, "factorial") == 0) {
            ASSERT_EQ(CALL_RECURSIVE, entry.call_type);
            ASSERT_TRUE(entry.mangled_name != NULL);
            // It should be mangled as "factorial" because it's C89 safe
            ASSERT_STREQ("factorial", entry.mangled_name);
            found_recursive = true;
        } else if (plat_strcmp(entry.context, "main") == 0) {
            ASSERT_EQ(CALL_DIRECT, entry.call_type);
            ASSERT_TRUE(entry.mangled_name != NULL);
            ASSERT_STREQ("factorial", entry.mangled_name);
            found_direct = true;
        }
    }

    ASSERT_TRUE(found_recursive);
    ASSERT_TRUE(found_direct);

    return true;
}

TEST_FUNC(Recursive_Mutual_Mangled) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn isEven(n: i32) bool {\n"
        "    if (n == 0) { return true; }\n"
        "    return isOdd(n - 1);\n"
        "}\n"
        "fn isOdd(n: i32) bool {\n"
        "    if (n == 0) { return false; }\n"
        "    return isEven(n - 1);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    ASSERT_EQ(2, table.count());

    bool found_isEven_call = false;
    bool found_isOdd_call = false;

    for (int i = 0; i < table.count(); ++i) {
        const CallSiteEntry& entry = table.getEntry(i);
        if (plat_strcmp(entry.context, "isEven") == 0) {
            ASSERT_EQ(CALL_DIRECT, entry.call_type);
            ASSERT_STREQ("isOdd", entry.mangled_name);
            found_isOdd_call = true;
        } else if (plat_strcmp(entry.context, "isOdd") == 0) {
            ASSERT_EQ(CALL_DIRECT, entry.call_type);
            ASSERT_STREQ("isEven", entry.mangled_name);
            found_isEven_call = true;
        }
    }

    ASSERT_TRUE(found_isEven_call);
    ASSERT_TRUE(found_isOdd_call);

    return true;
}

TEST_FUNC(Recursive_Forward_Mangled) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn start() void { later(); }\n"
        "fn later() void { start(); }\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    ASSERT_EQ(2, table.count());

    bool found_start_call = false;
    bool found_later_call = false;

    for (int i = 0; i < table.count(); ++i) {
        const CallSiteEntry& entry = table.getEntry(i);
        if (plat_strcmp(entry.context, "start") == 0) {
            ASSERT_EQ(CALL_DIRECT, entry.call_type);
            ASSERT_STREQ("later", entry.mangled_name);
            found_later_call = true;
        } else if (plat_strcmp(entry.context, "later") == 0) {
            ASSERT_EQ(CALL_DIRECT, entry.call_type);
            ASSERT_STREQ("start", entry.mangled_name);
            found_start_call = true;
        }
    }

    ASSERT_TRUE(found_start_call);
    ASSERT_TRUE(found_later_call);

    return true;
}
