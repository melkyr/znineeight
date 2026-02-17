#include "../src/include/test_framework.hpp"
#include "../src/include/memory.hpp"
#include <cstddef> // For size_t
#include <stdint.h> // For uintptr_t

// A struct that should be 8-byte aligned
struct AlignedStruct {
    double d;
    int i;
};

TEST_FUNC(ArenaAllocator_AllocShouldReturn8ByteAligned) {
    ArenaAllocator arena(262144);

    // Make a small allocation to potentially misalign the next one
    arena.alloc(1);

    // Allocate our struct that requires 8-byte alignment
    void* ptr = arena.alloc(sizeof(AlignedStruct));

    // The test fails if the pointer is not 8-byte aligned.
    ASSERT_TRUE(((uintptr_t)ptr % 8) == 0);

    return true;
}
