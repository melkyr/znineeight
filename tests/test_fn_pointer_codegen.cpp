#include "codegen.hpp"
#include "platform.hpp"
#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"

TEST_FUNC(Codegen_FunctionPointer_Simple) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    C89Emitter emitter(unit, "temp_fp.c");

    // Type: fn(i32) void
    void* mem = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params = new (mem) DynamicArray<Type*>(arena);
    params->append(get_g_type_i32());
    Type* fp_type = createFunctionPointerType(arena, params, get_g_type_void());

    emitter.emitDeclarator(fp_type, "my_fp");
    emitter.writeString(";\n");
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    ASSERT_TRUE(plat_file_read("temp_fp.c", &buffer, &size));

    // Expected: void (* my_fp)(int);
    if (strstr(buffer, "void (* my_fp)(int)") == NULL) {
        plat_print_debug("Expected: 'void (* my_fp)(int)', Got: '");
        plat_print_debug(buffer);
        plat_print_debug("'\n");
        ASSERT_TRUE(false);
    }

    plat_free(buffer);
    plat_delete_file("temp_fp.c");
    return true;
}

TEST_FUNC(Codegen_FunctionPointer_InArray) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    C89Emitter emitter(unit, "temp_fp_array.c");

    // Type: [10]fn(i32) i32
    void* mem = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params = new (mem) DynamicArray<Type*>(arena);
    params->append(get_g_type_i32());
    Type* fp_type = createFunctionPointerType(arena, params, get_g_type_i32());
    Type* arr_type = createArrayType(arena, fp_type, 10, &unit.getTypeInterner());

    emitter.emitDeclarator(arr_type, "fp_arr");
    emitter.writeString(";\n");
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    ASSERT_TRUE(plat_file_read("temp_fp_array.c", &buffer, &size));

    // Expected: int (* fp_arr[10])(int);
    if (strstr(buffer, "int (* fp_arr[10])(int)") == NULL) {
        plat_print_debug("Expected: 'int (* fp_arr[10])(int)', Got: '");
        plat_print_debug(buffer);
        plat_print_debug("'\n");
        ASSERT_TRUE(false);
    }

    plat_free(buffer);
    plat_delete_file("temp_fp_array.c");
    return true;
}

TEST_FUNC(Codegen_PointerToFunctionPointer) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    C89Emitter emitter(unit, "temp_pfp.c");

    // Type: *fn() void
    void* mem = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params = new (mem) DynamicArray<Type*>(arena);
    Type* fp_type = createFunctionPointerType(arena, params, get_g_type_void());
    Type* pfp_type = createPointerType(arena, fp_type, false, false, &unit.getTypeInterner());

    emitter.emitDeclarator(pfp_type, "pfp");
    emitter.writeString(";\n");
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    ASSERT_TRUE(plat_file_read("temp_pfp.c", &buffer, &size));

    // Expected: void (* (* pfp))(void);
    if (strstr(buffer, "void (* (* pfp))(void)") == NULL) {
        plat_print_debug("Expected: 'void (* (* pfp))(void)', Got: '");
        plat_print_debug(buffer);
        plat_print_debug("'\n");
        ASSERT_TRUE(false);
    }

    plat_free(buffer);
    plat_delete_file("temp_pfp.c");
    return true;
}

TEST_FUNC(Codegen_FunctionReturningFunctionPointer) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    C89Emitter emitter(unit, "temp_frfp.c");

    // Type: fn(i32) fn(f64) void
    void* mem1 = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params1 = new (mem1) DynamicArray<Type*>(arena);
    params1->append(get_g_type_f64());
    Type* fp_inner = createFunctionPointerType(arena, params1, get_g_type_void());

    void* mem2 = arena.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params2 = new (mem2) DynamicArray<Type*>(arena);
    params2->append(get_g_type_i32());
    Type* fn_outer = createFunctionType(arena, params2, fp_inner);

    emitter.emitDeclarator(fn_outer, "foo");
    emitter.writeString(";\n");
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    ASSERT_TRUE(plat_file_read("temp_frfp.c", &buffer, &size));

    // Expected: void (* foo(int))(double);
    if (strstr(buffer, "void (* foo(int))(double)") == NULL) {
        plat_print_debug("Expected: 'void (* foo(int))(double)', Got: '");
        plat_print_debug(buffer);
        plat_print_debug("'\n");
        ASSERT_TRUE(false);
    }

    plat_free(buffer);
    plat_delete_file("temp_frfp.c");
    return true;
}
