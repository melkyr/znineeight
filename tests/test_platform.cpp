#include "platform.hpp"
#include "test_framework.hpp"
#include <cassert>

TEST_FUNC(platform_alloc) {
    void* ptr = plat_alloc(100);
    ASSERT_TRUE(ptr != NULL);

    // Test that we can write to it
    plat_memcpy(ptr, "Hello PAL", 10);
    ASSERT_EQ(0, plat_strcmp((char*)ptr, "Hello PAL"));

    plat_free(ptr);
    return true;
}

TEST_FUNC(platform_realloc) {
    void* ptr = plat_alloc(10);
    plat_memcpy(ptr, "123456789", 10);

    ptr = plat_realloc(ptr, 20);
    ASSERT_TRUE(ptr != NULL);
    ASSERT_EQ(0, plat_strcmp((char*)ptr, "123456789"));

    plat_free(ptr);
    return true;
}

TEST_FUNC(platform_string) {
    ASSERT_EQ(3, (int)plat_strlen("abc"));
    ASSERT_EQ(0, (int)plat_strlen(""));

    ASSERT_EQ(0, plat_strcmp("abc", "abc"));
    ASSERT_TRUE(plat_strcmp("abc", "abd") < 0);
    ASSERT_TRUE(plat_strcmp("abd", "abc") > 0);

    char buf[10];
    plat_memcpy(buf, "hello", 6);
    ASSERT_EQ(0, plat_strcmp(buf, "hello"));

    plat_memmove(buf + 1, buf, 5); // "hhello"
    ASSERT_EQ('h', buf[0]);
    ASSERT_EQ('h', buf[1]);
    ASSERT_EQ('e', buf[2]);

    return true;
}

TEST_FUNC(platform_file) {
    char* buffer = NULL;
    size_t size = 0;

    // Use a file we know exists in the root
    if (!plat_file_read("LICENSE", &buffer, &size)) {
        return false;
    }

    ASSERT_TRUE(buffer != NULL);
    ASSERT_TRUE(size > 0);
    ASSERT_EQ(size, plat_strlen(buffer));

    plat_free(buffer);
    return true;
}

TEST_FUNC(platform_print) {
    // These just shouldn't crash
    plat_print_info("Testing plat_print_info\n");
    plat_print_error("Testing plat_print_error\n");
    plat_print_debug("Testing plat_print_debug\n");
    return true;
}
