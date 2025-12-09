#include "../src/include/test_framework.hpp"
#include "../src/include/string_interner.hpp"
#include "../src/include/memory.hpp"
#include <cstring>

TEST_FUNC(string_interning) {
    ArenaAllocator arena(1024 * 1024); // 1MB arena
    StringInterner interner(arena);

    const char* s1 = interner.intern("hello");
    const char* s2 = interner.intern("world");
    const char* s3 = interner.intern("hello");

    ASSERT_TRUE(s1 != s2);
    ASSERT_TRUE(s1 == s3);
    ASSERT_TRUE(strcmp(s1, "hello") == 0);
    ASSERT_TRUE(strcmp(s2, "world") == 0);

    return true;
}
