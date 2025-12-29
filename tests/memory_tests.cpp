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
    ArenaAllocator arena(8192);
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
