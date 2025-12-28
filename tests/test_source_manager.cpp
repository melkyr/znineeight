#include "../src/include/source_manager.hpp"
#include <cstdio>
#include <cassert>

void test_source_manager_add_file() {
    ArenaAllocator arena(4096);
    SourceManager sm(arena);
    const char* content = "line 1\nline 2";
    u32 file_id = sm.addFile("test.zig", content, 13);
    assert(file_id == 0);
    printf("test_source_manager_add_file: PASS\n");
}

void test_source_manager_get_location() {
    ArenaAllocator arena(4096);
    SourceManager sm(arena);
    const char* content = "line 1\nline 2\n  line 3";
    u32 file_id = sm.addFile("test.zig", content, 23);

    SourceLocation loc1 = sm.getLocation(file_id, 0);
    assert(loc1.line == 1);
    assert(loc1.column == 1);

    SourceLocation loc2 = sm.getLocation(file_id, 7);
    assert(loc2.line == 2);
    assert(loc2.column == 1);

    SourceLocation loc3 = sm.getLocation(file_id, 16);
    assert(loc3.line == 3);
    assert(loc3.column == 3);

    printf("test_source_manager_get_location: PASS\n");
}

int main() {
    test_source_manager_add_file();
    test_source_manager_get_location();
    printf("All SourceManager tests passed!\n");
    return 0;
}
