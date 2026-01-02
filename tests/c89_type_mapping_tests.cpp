// tests/c89_type_mapping_tests.cpp
// Tests for the C89 type mapping and compatibility functions.

#include "test_framework.hpp"
#include "test_utils.hpp" // For ArenaLifetimeGuard
#include "c89_type_mapping.hpp"
#include "type_system.hpp"
#include "memory.hpp"
#include <cstdio> // For printf in test verification

// Helper to create a pointer type for testing purposes
static Type* createTestPointerType(ArenaAllocator& arena, Type* base_type, bool is_const) {
    Type* ptr_type = (Type*)arena.alloc(sizeof(Type));
    ptr_type->kind = TYPE_POINTER;
    ptr_type->size = 4; // Assuming 32-bit pointers
    ptr_type->alignment = 4;
    ptr_type->as.pointer.base = base_type;
    ptr_type->as.pointer.is_const = is_const;
    return ptr_type;
}

TEST_FUNC(C89TypeMapping_Validation) {
    // 1. Print the mapping table for manual verification, as requested.
    printf("\n--- C89 Type Mappings ---\n");
    const size_t map_size = sizeof(c89_type_map) / sizeof(c89_type_map[0]);
    for (size_t i = 0; i < map_size; ++i) {
        printf("Mapping: Zig TypeKind %d -> C89 \"%s\"\n", c89_type_map[i].zig_type_kind, c89_type_map[i].c89_type_name);
    }
    printf("-------------------------\n");

    // 2. Setup Arena for creating test types
    ArenaAllocator arena(1024);
    ArenaLifetimeGuard guard(arena);

    // 3. Verify all whitelisted primitive types are compatible
    ASSERT_TRUE(is_c89_compatible(&g_type_void));
    ASSERT_TRUE(is_c89_compatible(&g_type_bool));
    ASSERT_TRUE(is_c89_compatible(&g_type_i8));
    ASSERT_TRUE(is_c89_compatible(&g_type_i16));
    ASSERT_TRUE(is_c89_compatible(&g_type_i32));
    ASSERT_TRUE(is_c89_compatible(&g_type_i64));
    ASSERT_TRUE(is_c89_compatible(&g_type_u8));
    ASSERT_TRUE(is_c89_compatible(&g_type_u16));
    ASSERT_TRUE(is_c89_compatible(&g_type_u32));
    ASSERT_TRUE(is_c89_compatible(&g_type_u64));
    ASSERT_TRUE(is_c89_compatible(&g_type_f32));
    ASSERT_TRUE(is_c89_compatible(&g_type_f64));

    // 4. Verify that single-level pointers to whitelisted types are compatible
    Type* ptr_to_i32 = createTestPointerType(arena, &g_type_i32, false);
    ASSERT_TRUE(is_c89_compatible(ptr_to_i32));

    Type* const_ptr_to_u8 = createTestPointerType(arena, &g_type_u8, true);
    ASSERT_TRUE(is_c89_compatible(const_ptr_to_u8));

    Type* ptr_to_void = createTestPointerType(arena, &g_type_void, false);
    ASSERT_TRUE(is_c89_compatible(ptr_to_void));

    // 5. Verify that invalid or unsupported types are NOT compatible
    ASSERT_FALSE(is_c89_compatible(NULL));

    // isize and usize are not in the C89 map
    ASSERT_FALSE(is_c89_compatible(&g_type_isize));
    ASSERT_FALSE(is_c89_compatible(&g_type_usize));

    // Function types are not C89 compatible in this context
    Type func_type;
    func_type.kind = TYPE_FUNCTION;
    ASSERT_FALSE(is_c89_compatible(&func_type));

    // Multi-level pointers are not compatible
    Type* ptr_to_ptr_to_i32 = createTestPointerType(arena, ptr_to_i32, false);
    ASSERT_FALSE(is_c89_compatible(ptr_to_ptr_to_i32));

    Type* const_ptr_to_ptr_to_u8 = createTestPointerType(arena, const_ptr_to_u8, true);
    ASSERT_FALSE(is_c89_compatible(const_ptr_to_ptr_to_u8));

    return true; // Test passed
}
