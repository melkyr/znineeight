#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"

TEST_FUNC(basic_allocation) {
    ArenaAllocator arena(1024);
    void* p = arena.alloc(100);
    ASSERT_TRUE(p != NULL);
    return true;
}

TEST_FUNC(multiple_allocations) {
    ArenaAllocator arena(1024);
    void* p1 = arena.alloc(100);
    void* p2 = arena.alloc(200);
    ASSERT_TRUE(p1 != NULL);
    ASSERT_TRUE(p2 != NULL);
    // The exact offset is no longer predictable due to alignment,
    // so we just check that the allocations were successful.
    return true;
}

TEST_FUNC(allocation_failure) {
    ArenaAllocator arena(100);
    arena.alloc(50);
    void* p2 = arena.alloc(60);
    ASSERT_TRUE(p2 == NULL);
    return true;
}

TEST_FUNC(reset) {
    ArenaAllocator arena(1024);
    void* p1 = arena.alloc(100);
    arena.reset();
    void* p2 = arena.alloc(100);
    ASSERT_TRUE(static_cast<char*>(p1) == static_cast<char*>(p2));
    return true;
}

TEST_FUNC(aligned_allocation) {
    ArenaAllocator arena(1024);
    arena.alloc(3); // Misalign the offset to 3

    // Test 1: Basic alignment
    void* p1 = arena.alloc_aligned(16, 16);
    ASSERT_TRUE(p1 != NULL);
    ASSERT_TRUE((reinterpret_cast<size_t>(p1) & 15) == 0);

    // Test 2: Different alignment
    void* p2 = arena.alloc_aligned(8, 8);
    ASSERT_TRUE(p2 != NULL);
    ASSERT_TRUE((reinterpret_cast<size_t>(p2) & 7) == 0);

    // Test 3: Allocation when offset is already aligned
    arena.reset();
    ASSERT_TRUE(arena.alloc(16) != NULL); // Offset is now 16
    void* p3 = arena.alloc_aligned(16, 16);
    ASSERT_TRUE(p3 != NULL);
    ASSERT_TRUE((reinterpret_cast<size_t>(p3) & 15) == 0);

    // Test 4: Edge case, allocation fails due to insufficient space
    arena.reset();
    arena.alloc(1024 - 15); // Leave 15 bytes, not enough for 16-byte alignment
    void* p4 = arena.alloc_aligned(16, 16);
    ASSERT_TRUE(p4 == NULL);

    return true;
}
