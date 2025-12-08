#include "../src/include/string_interner.hpp"
#include "../src/include/memory.hpp"
#include <cstdio>
#include <cstring>

#define ASSERT_TRUE(condition) do { \
    if (!(condition)) { \
        printf("FAIL: %s at %s:%d\n", #condition, __FILE__, __LINE__); \
        return 1; \
    } \
} while(0)

#define ASSERT_EQ(expected, actual) do { \
    if ((expected) != (actual)) { \
        printf("FAIL: %s != %s at %s:%d\n", #expected, #actual, __FILE__, __LINE__); \
        return 1; \
    } \
} while(0)

int main() {
    ArenaAllocator arena(1024 * 1024); // 1MB arena
    StringInterner interner(arena);

    const char* s1 = interner.intern("hello");
    const char* s2 = interner.intern("world");
    const char* s3 = interner.intern("hello");

    ASSERT_TRUE(s1 != s2);
    ASSERT_EQ(s1, s3);
    ASSERT_TRUE(strcmp(s1, "hello") == 0);
    ASSERT_TRUE(strcmp(s2, "world") == 0);

    printf("PASS: All tests passed.\n");

    return 0;
}
