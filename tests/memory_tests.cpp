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
    ArenaAllocator arena(1024);
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
    // Expected calls:
    // - 1 for the 1st append (triggers initial allocation)
    // - 7 for appends 2-8
    // - On 9th append (reallocation):
    //   - 8 for copying old elements
    //   - 1 for the new element
    // Total = 1 + 7 + 8 + 1 = 17
    ASSERT_EQ(17, copy_assignment_calls);

    return true;
}
