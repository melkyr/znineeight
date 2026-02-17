#include "test_framework.hpp"
#include "test_utils.hpp"
#include "c89_type_mapping.hpp"
#include "type_system.hpp"

TEST_FUNC(C89Compat_FunctionTypeValidation) {
    ArenaAllocator arena(1024 * 1024); // Increased arena size for more complex types
    ArenaLifetimeGuard guard(arena);

    // Test Case 1: Simple valid function type fn() -> void
    {
        DynamicArray<Type*>* params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        Type* func_type = createFunctionType(arena, params, get_g_type_void());
        ASSERT_TRUE(is_c89_compatible(func_type));
    }

    // Test Case 2: Valid function with C89-compatible parameters and return type
    {
        DynamicArray<Type*>* params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        params->append(get_g_type_i32());
        Type* ptr_to_u8 = createPointerType(arena, get_g_type_u8(), false);
        params->append(ptr_to_u8);
        Type* func_type = createFunctionType(arena, params, get_g_type_bool());
        ASSERT_TRUE(is_c89_compatible(func_type));
    }

    // Test Case 3: Invalid function with more than 4 parameters
    {
        DynamicArray<Type*>* params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        params->append(get_g_type_i8());
        params->append(get_g_type_i16());
        params->append(get_g_type_i32());
        params->append(get_g_type_i64());
        params->append(get_g_type_u8()); // 5th parameter
        Type* func_type = createFunctionType(arena, params, get_g_type_void());
        ASSERT_FALSE(is_c89_compatible(func_type));
    }

    // Test Case 4: Invalid function with a function pointer as a parameter
    {
        DynamicArray<Type*>* inner_params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        Type* inner_func_type = createFunctionType(arena, inner_params, get_g_type_void());

        DynamicArray<Type*>* outer_params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        outer_params->append(inner_func_type);
        Type* outer_func_type = createFunctionType(arena, outer_params, get_g_type_void());
        ASSERT_FALSE(is_c89_compatible(outer_func_type));
    }

    // Test Case 5: Invalid function returning a function pointer
    {
        DynamicArray<Type*>* inner_params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        Type* inner_func_type = createFunctionType(arena, inner_params, get_g_type_void());

        DynamicArray<Type*>* outer_params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        Type* outer_func_type = createFunctionType(arena, outer_params, inner_func_type);
        ASSERT_FALSE(is_c89_compatible(outer_func_type));
    }

    // Test Case 6: Valid function with isize parameter
    {
        DynamicArray<Type*>* params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        params->append(get_g_type_isize()); // isize is now C89 compatible
        Type* func_type = createFunctionType(arena, params, get_g_type_void());
        ASSERT_TRUE(is_c89_compatible(func_type));
    }

    // Test Case 7: Valid function with usize return type
    {
        DynamicArray<Type*>* params = new (arena.alloc(sizeof(DynamicArray<Type*>))) DynamicArray<Type*>(arena);
        Type* func_type = createFunctionType(arena, params, get_g_type_usize()); // usize is now C89 compatible
        ASSERT_TRUE(is_c89_compatible(func_type));
    }

    return true;
}
