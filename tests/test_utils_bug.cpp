#include "test_framework.hpp"
#include "utils.hpp"
#include <cstring>

TEST_FUNC(safe_append_null_termination) {
    char buffer[10];
    char* dest = buffer;
    size_t remaining = 10;

    // 1. Normal append (no truncation)
    // "abc" is 3 chars, remaining is 10. len < remaining.
    safe_append(dest, remaining, "abc");
    // buffer should be {'a', 'b', 'c', '\0', ...}
    ASSERT_TRUE(buffer[3] == '\0');
    ASSERT_TRUE(remaining == 7);
    ASSERT_TRUE(dest == buffer + 3);

    // 2. Truncated append
    // "123456789" is 9 chars, remaining is 7. len >= remaining.
    safe_append(dest, remaining, "123456789");
    // remaining was 7. strncpy(dest, src, 7-1) -> copies 6 chars: "123456"
    // dest[6] = '\0'
    // Total buffer should be "abc" + "123456" + '\0'
    // buffer index: 012 345678 9
    ASSERT_TRUE(buffer[9] == '\0');
    // If bug is present, buffer[9] will be '0' (ASCII 48)
    if (buffer[9] == '0') {
        // This is where we detect the bug
        return false;
    }

    ASSERT_TRUE(remaining == 0);
    ASSERT_TRUE(dest == buffer + 9);

    return true;
}

TEST_FUNC(safe_append_explicit_check) {
    char buf[5];
    memset(buf, 'X', 5); // Fill with X

    char* ptr = buf;
    size_t remaining = 4;
    // This should trigger the 'else if (remaining > 0)' branch in safe_append
    safe_append(ptr, remaining, "LONG_STRING");

    // buf index 0, 1, 2 should be 'L', 'O', 'N'
    // buf index 3 should be '\0'
    // buf index 4 should still be 'X' (as safe_append with remaining=4 only touches up to index 3)

    ASSERT_TRUE(buf[0] == 'L');
    ASSERT_TRUE(buf[1] == 'O');
    ASSERT_TRUE(buf[2] == 'N');
    ASSERT_TRUE(buf[3] == '\0');

    // Explicitly check against the '0' bug
    ASSERT_TRUE(buf[3] != '0');

    // Verify strlen stops at the null terminator
    size_t len = strlen(buf);
    ASSERT_TRUE(len == 3);

    return true;
}

TEST_FUNC(plat_itoa_null_termination) {
    char buffer[10];

    // 1. Test zero
    plat_i64_to_string(0, buffer, 10);
    ASSERT_TRUE(buffer[0] == '0');
    ASSERT_TRUE(buffer[1] == '\0');
    if (buffer[1] == '0') return false; // Bug detection

    // 2. Test positive
    plat_i64_to_string(123, buffer, 10);
    // "123" -> buffer[0]='1', [1]='2', [2]='3', [3]='\0'
    ASSERT_TRUE(buffer[3] == '\0');
    if (buffer[3] == '0') return false; // Bug detection
    ASSERT_TRUE(strcmp(buffer, "123") == 0);

    // 3. Test negative
    plat_i64_to_string(-456, buffer, 10);
    ASSERT_TRUE(strcmp(buffer, "-456") == 0);
    ASSERT_TRUE(buffer[4] == '\0');
    if (buffer[4] == '0') return false; // Bug detection

    return true;
}
