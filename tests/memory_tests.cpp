#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"
#include "../src/include/utils.hpp"

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
TEST_FUNC(plat_itoa_conversion) {
    char buffer[32];

    // Test zero
    plat_i64_to_string(0, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "0") == 0);

    // Test single digit
    plat_i64_to_string(5, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "5") == 0);

    // Test multi-digit
    plat_i64_to_string(12345, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "12345") == 0);

    // Test a larger number
    plat_i64_to_string(987654321, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "987654321") == 0);

    // Test large values using plat_u64_to_string for unsigned
    plat_u64_to_string(4294967295ULL, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "4294967295") == 0);

    plat_i64_to_string(9223372036854775807LL, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer, "9223372036854775807") == 0);

    return true;
}
#endif // DEBUG
