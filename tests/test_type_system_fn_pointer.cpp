#include "test_framework.hpp"
#include "type_system.hpp"
#include "memory.hpp"

TEST_FUNC(TypeSystem_FunctionPointerType) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);

    void* mem = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params = new (mem) DynamicArray<Type*>(arena);
    params->append(get_g_type_i32());

    Type* fn_ptr = createFunctionPointerType(arena, params, get_g_type_void());

    ASSERT_TRUE(fn_ptr != NULL);
    ASSERT_EQ(fn_ptr->kind, TYPE_FUNCTION_POINTER);
    ASSERT_EQ(fn_ptr->size, 4);
    ASSERT_EQ(fn_ptr->alignment, 4);
    ASSERT_EQ(fn_ptr->as.function_pointer.param_types->length(), 1);
    ASSERT_EQ((*fn_ptr->as.function_pointer.param_types)[0], get_g_type_i32());
    ASSERT_EQ(fn_ptr->as.function_pointer.return_type, get_g_type_void());

    char buffer[128];
    typeToString(fn_ptr, buffer, sizeof(buffer));
    ASSERT_STREQ("fn(i32) void", buffer);

    return true;
}

TEST_FUNC(TypeSystem_SignaturesMatch) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);

    void* mem1 = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params1 = new (mem1) DynamicArray<Type*>(arena);
    params1->append(get_g_type_i32());

    void* mem2 = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params2 = new (mem2) DynamicArray<Type*>(arena);
    params2->append(get_g_type_i32());

    ASSERT_TRUE(signaturesMatch(params1, get_g_type_void(), params2, get_g_type_void()));

    params2->append(get_g_type_bool());
    ASSERT_FALSE(signaturesMatch(params1, get_g_type_void(), params2, get_g_type_void()));

    return true;
}

TEST_FUNC(TypeSystem_AreTypesEqual_FnPtr) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);

    void* mem1 = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params1 = new (mem1) DynamicArray<Type*>(arena);
    params1->append(get_g_type_i32());

    void* mem2 = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params2 = new (mem2) DynamicArray<Type*>(arena);
    params2->append(get_g_type_i32());

    Type* fn_ptr1 = createFunctionPointerType(arena, params1, get_g_type_void());
    Type* fn_ptr2 = createFunctionPointerType(arena, params2, get_g_type_void());

    ASSERT_TRUE(areTypesEqual(fn_ptr1, fn_ptr2));
    ASSERT_TRUE(fn_ptr1 != fn_ptr2); // Should be different objects

    void* mem3 = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params3 = new (mem3) DynamicArray<Type*>(arena);
    params3->append(get_g_type_bool());
    Type* fn_ptr3 = createFunctionPointerType(arena, params3, get_g_type_void());

    ASSERT_FALSE(areTypesEqual(fn_ptr1, fn_ptr3));

    return true;
}
