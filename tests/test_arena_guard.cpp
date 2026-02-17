#include "test_framework.hpp"
#include "test_utils.hpp"
#include "memory.hpp"

TEST_FUNC(ArenaLifetimeGuard_ResetsArena) {
    ArenaAllocator arena(262144);
    size_t initial_offset = arena.getOffset();

    {
        ArenaLifetimeGuard guard(arena);
        arena.alloc(128);
        ASSERT_TRUE(arena.getOffset() > initial_offset);
    }

    ASSERT_EQ(arena.getOffset(), initial_offset);

    return true;
}
