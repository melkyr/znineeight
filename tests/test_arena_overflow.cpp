#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"

/**
 * @brief Tests that ArenaAllocator::alloc returns NULL when out of memory.
 */
TEST_FUNC(arena_alloc_out_of_memory) {
    ArenaAllocator arena(16);
    arena.alloc(10);
    void* ptr = arena.alloc(10); // Should fail
    ASSERT_TRUE(ptr == NULL);
    return true;
}

/**
 * @brief Tests that ArenaAllocator::alloc returns NULL on a zero-size allocation.
 */
TEST_FUNC(arena_alloc_zero_size) {
    ArenaAllocator arena(16);
    void* ptr = arena.alloc(0);
    ASSERT_TRUE(ptr == NULL);
    return true;
}

/**
 * @brief Tests that ArenaAllocator::alloc_aligned returns NULL when out of memory.
 */
TEST_FUNC(arena_alloc_aligned_out_of_memory) {
    ArenaAllocator arena(32);
    arena.alloc(20);
    // This should fail because it needs space for alignment padding + 16 bytes.
    void* ptr = arena.alloc_aligned(16, 16);
    ASSERT_TRUE(ptr == NULL);
    return true;
}

/**
 * @brief Tests the overflow check in alloc_aligned.
 *
 * This test simulates a scenario where an aligned allocation request could
 * pass a simple capacity check but should fail the more robust overflow check.
 */
TEST_FUNC(arena_alloc_aligned_overflow_check) {
    const size_t capacity = 1024;
    ArenaAllocator arena(capacity);

    // Allocate almost all the memory, leaving just a little space.
    arena.alloc(capacity - 16);

    // Try to allocate a block that is larger than the remaining raw space.
    // The alignment calculation might produce a `new_offset` that fits within
    // the capacity, but the final `offset = new_offset + size` would overflow.
    // The `new_offset > capacity - size` check should prevent this.
    void* ptr = arena.alloc_aligned(32, 16);

    ASSERT_TRUE(ptr == NULL);
    return true;
}
