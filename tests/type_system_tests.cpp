#include "test_framework.hpp"
#include "type_system.hpp"

TEST_FUNC(TypeSystem_StructLayout)
{
    // On a 32-bit system, we expect:
    // TypeKind kind;      // 4 bytes (size of enum is typically int)
    // size_t size;         // 4 bytes
    // size_t alignment;    // 4 bytes
    // union { ... } as;   // 4 bytes (contains a pointer)
    // Total: 16 bytes
    // This test might fail on a 64-bit build environment, but it serves as a
    // sanity check for the target 32-bit architecture.
    const size_t expected_size = sizeof(int) + sizeof(size_t) + sizeof(size_t) + sizeof(void*);
    ASSERT_EQ(expected_size, sizeof(Type));

    return 0;
}
