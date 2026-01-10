#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"

TEST_FUNC(dynamic_array_append) {
    ArenaAllocator arena(16384);
    DynamicArray<int> arr(arena);
    arr.append(10);
    arr.append(20);
    ASSERT_TRUE(arr.length() == 2);
    ASSERT_TRUE(arr[0] == 10);
    ASSERT_TRUE(arr[1] == 20);
    return true;
}

TEST_FUNC(dynamic_array_growth) {
    ArenaAllocator arena(16384);
    DynamicArray<int> arr(arena);
    for (int i = 0; i < 20; ++i) {
        arr.append(i);
    }
    ASSERT_TRUE(arr.length() == 20);
    ASSERT_TRUE(arr[19] == 19);
    return true;
}

TEST_FUNC(dynamic_array_growth_from_zero) {
    ArenaAllocator arena(16384);
    DynamicArray<int> arr(arena);
    arr.append(42);
    ASSERT_EQ(arr.length(), 1);
    ASSERT_TRUE(arr.getCapacity() > 0);
    ASSERT_EQ(arr[0], 42);
    return true;
}

TEST_FUNC(arena_allocator_actually_allocates) {
    ArenaAllocator arena(16384);
    void* ptr = arena.alloc(16);
    ASSERT_TRUE(ptr != NULL);
    // Attempt to write to the allocated memory. This will cause a crash
    // if the pointer is null, providing a more robust failure signal.
    memset(ptr, 0, 16);
    return true;
}
