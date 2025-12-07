#include "../src/include/memory.hpp"
#include <cstdio>
#include <cassert>

void test_basic_allocation() {
    ArenaAllocator arena(1024);
    void* p = arena.alloc(100);
    assert(p != nullptr);
    printf("test_basic_allocation: PASS\n");
}

void test_multiple_allocations() {
    ArenaAllocator arena(1024);
    void* p1 = arena.alloc(100);
    void* p2 = arena.alloc(200);
    assert(p1 != nullptr);
    assert(p2 != nullptr);
    assert(static_cast<char*>(p2) == static_cast<char*>(p1) + 100);
    printf("test_multiple_allocations: PASS\n");
}

void test_allocation_failure() {
    ArenaAllocator arena(100);
    arena.alloc(50);
    void* p2 = arena.alloc(60);
    assert(p2 == nullptr);
    printf("test_allocation_failure: PASS\n");
}

void test_reset() {
    ArenaAllocator arena(1024);
    void* p1 = arena.alloc(100);
    arena.reset();
    void* p2 = arena.alloc(100);
    assert(static_cast<char*>(p1) == static_cast<char*>(p2));
    printf("test_reset: PASS\n");
}

void test_aligned_allocation() {
    ArenaAllocator arena(1024);
    arena.alloc(3); // Misalign the offset to 3

    // Test 1: Basic alignment
    void* p1 = arena.alloc_aligned(16, 16);
    assert(p1 != nullptr);
    assert((reinterpret_cast<size_t>(p1) & 15) == 0);
    printf("test_aligned_allocation (basic): PASS\n");

    // Test 2: Different alignment
    void* p2 = arena.alloc_aligned(8, 8);
    assert(p2 != nullptr);
    assert((reinterpret_cast<size_t>(p2) & 7) == 0);
    printf("test_aligned_allocation (align 8): PASS\n");

    // Test 3: Allocation when offset is already aligned
    arena.reset();
    assert(arena.alloc(16) != nullptr); // Offset is now 16
    void* p3 = arena.alloc_aligned(16, 16);
    assert(p3 != nullptr);
    assert((reinterpret_cast<size_t>(p3) & 15) == 0);
    printf("test_aligned_allocation (already aligned): PASS\n");

    // Test 4: Edge case, allocation fails due to insufficient space
    arena.reset();
    arena.alloc(1024 - 15); // Leave 15 bytes, not enough for 16-byte alignment
    void* p4 = arena.alloc_aligned(16, 16);
    assert(p4 == nullptr);
    printf("test_aligned_allocation (insufficient space): PASS\n");
}

int main() {
    test_basic_allocation();
    test_multiple_allocations();
    test_allocation_failure();
    test_reset();
    test_aligned_allocation();

    printf("All ArenaAllocator tests passed!\n");
    return 0;
}
