#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"

static int copy_assignment_calls = 0;
struct AssignmentLogger {
    int val;
    AssignmentLogger(int v = 0) : val(v) {}
    AssignmentLogger(const AssignmentLogger& other) : val(other.val) {
        // Not tracking copy constructions, only assignments in this test
    }
    AssignmentLogger& operator=(const AssignmentLogger& other) {
        val = other.val;
        copy_assignment_calls++;
        return *this;
    }
};

TEST_FUNC(dynamic_array_non_pod_reallocation) {
    ArenaAllocator arena(16384);
    DynamicArray<AssignmentLogger> arr(arena);
    copy_assignment_calls = 0;

    for (int i = 0; i < 9; ++i) {
        arr.append(AssignmentLogger(i));
    }

    // With incorrect memcpy, reallocation will not call operator= for the
    // existing elements. It will only be called once for each append().
    // Total calls = 9.
    //
    // A correct implementation uses an element-wise copy loop during
    // reallocation.
    // With copy-construction on realloc, only the append calls use assignment.
    // Total = 9
    ASSERT_EQ(9, copy_assignment_calls);

    return true;
}

#ifdef DEBUG
TEST_FUNC(simple_itoa_conversion) {
    char buffer[21]; // Sufficient for 64-bit size_t

    // Test zero
    simple_itoa(0, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "0") == 0);

    // Test single digit
    simple_itoa(5, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "5") == 0);

    // Test multi-digit
    simple_itoa(12345, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "12345") == 0);

    // Test a larger number
    simple_itoa(987654321, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "987654321") == 0);

    // Test max size_t value (assuming 32-bit for this test)
    // MSVC 6.0 might not have stdint.h, so use unsigned long
    size_t max_val = (size_t)-1;
    if (sizeof(size_t) == 4) {
        simple_itoa(4294967295UL, buffer, sizeof(buffer));
        ASSERT_TRUE(strcmp(buffer, "4294967295") == 0);
    } else if (sizeof(size_t) == 8) {
        // This will be a large number, let's just test a boundary case
        simple_itoa(18446744073709551615ULL, buffer, sizeof(buffer));
        ASSERT_TRUE(strcmp(buffer, "18446744073709551615") == 0);
    }

    return true;
}
#endif // DEBUG
