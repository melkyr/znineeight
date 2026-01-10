#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"
#include "test_utils.hpp"

// A struct to track copy constructions vs. copy assignments
static int copy_constructions = 0;
static int copy_assignments = 0;

struct CopyLogger {
    int id;

    CopyLogger(int id = 0) : id(id) {}

    // Copy constructor
    CopyLogger(const CopyLogger& other) : id(other.id) {
        copy_constructions++;
    }

    // Copy assignment operator
    CopyLogger& operator=(const CopyLogger& other) {
        id = other.id;
        copy_assignments++;
        return *this;
    }
};

TEST_FUNC(DynamicArray_ShouldUseCopyConstructionOnReallocation) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);

    // Reset counters for this test
    copy_constructions = 0;
    copy_assignments = 0;

    DynamicArray<CopyLogger> arr(arena);

    // Append 9 items to trigger reallocation
    for (int i = 0; i < 9; ++i) {
        arr.append(CopyLogger(i));
    }

    // Expected behavior with copy construction:
    // - 9 copy assignments for the `append` calls.
    // - 8 copy constructions for moving the old elements during reallocation.
    ASSERT_EQ(8, copy_constructions);
    ASSERT_EQ(9, copy_assignments);


    return true;
}
