#include "bug_test_memory.hpp"
#include "../src/include/memory.hpp"
#include "test_framework.hpp"

// A simple class to track destructor calls.
class DestructorTracker {
public:
    static int destructor_call_count;

    DestructorTracker() {}

    // The destructor increments a static counter.
    ~DestructorTracker() {
        destructor_call_count++;
    }

    // Copy constructor and assignment operator are needed for the DynamicArray.
    DestructorTracker(const DestructorTracker&) {}
    DestructorTracker& operator=(const DestructorTracker&) { return *this; }
};

// Initialize the static counter.
int DestructorTracker::destructor_call_count = 0;

// This test verifies the fix in DynamicArray's reallocation logic.
// It is expected to PASS, proving that destructors for the old elements ARE now called.
TEST_FUNC(dynamic_array_destructor_fix) {
    // 1. Reset the counter to ensure a clean test environment.
    DestructorTracker::destructor_call_count = 0;

    // 2. Set up an arena allocator.
    ArenaAllocator arena(262144);

    // 3. Create a DynamicArray inside a scope.
    {
        DynamicArray<DestructorTracker> arr(arena);

        // 4. Add 9 elements to force at least one reallocation.
        for (int i = 0; i < 9; ++i) {
            arr.append(DestructorTracker());
        }

    } // `arr` goes out of scope here. Because it is arena-allocated, it does NOT
      // have a destructor that cleans up its final 9 elements. This is expected.

    // 5. Assert that exactly 17 destructors were called.
    // - 9 for the temporary objects created in the `append` loop.
    // - 8 for the elements in the original buffer that was abandoned during reallocation.
    // This assertion will now PASS, confirming the bug is fixed.
    ASSERT_TRUE(DestructorTracker::destructor_call_count == 17);

    return true;
}
