#include "test_runner_main.hpp"
#include "type_registry.hpp"
#include "memory.hpp"
#include "utils.hpp"
#include "type_system.hpp"
#include "compilation_unit.hpp"
#include "module.hpp"
#include <cstdio>
#include <assert.h>

bool test_mutual_recursion_standalone() {
    ArenaAllocator arena(1024 * 1024);
    TypeRegistry registry(arena);
    Module mod(arena);
    mod.name = "TestModule";

    // Phase 1: Register placeholders
    Type* ph_a = (Type*)arena.alloc(sizeof(Type));
    plat_memset(ph_a, 0, sizeof(Type));
    ph_a->kind = TYPE_PLACEHOLDER;
    ph_a->as.placeholder.name = "A";
    registry.insert((struct Module*)&mod, "A", ph_a);

    Type* ph_b = (Type*)arena.alloc(sizeof(Type));
    plat_memset(ph_b, 0, sizeof(Type));
    ph_b->kind = TYPE_PLACEHOLDER;
    ph_b->as.placeholder.name = "B";
    registry.insert((struct Module*)&mod, "B", ph_b);

    // Phase 2: Resolve structure
    // Struct A { b: *B }
    void* fields_a_mem = arena.alloc(sizeof(DynamicArray<StructField>));
    DynamicArray<StructField>* fields_a = new (fields_a_mem) DynamicArray<StructField>(arena);

    Type* ptr_b = createPointerType(arena, ph_b, false, false, NULL);
    StructField f_b;
    f_b.name = "b";
    f_b.type = ptr_b;
    f_b.offset = 0;
    fields_a->append(f_b);

    // Mutate ph_a to STRUCT
    ph_a->kind = TYPE_STRUCT;
    ph_a->as.struct_details.name = "A";
    ph_a->as.struct_details.fields = fields_a;
    ph_a->size = 4; // Pointer size
    ph_a->alignment = 4;

    // Struct B { a: *A }
    void* fields_b_mem = arena.alloc(sizeof(DynamicArray<StructField>));
    DynamicArray<StructField>* fields_b = new (fields_b_mem) DynamicArray<StructField>(arena);

    Type* ptr_a = createPointerType(arena, ph_a, false, false, NULL);
    StructField f_a;
    f_a.name = "a";
    f_a.type = ptr_a;
    f_a.offset = 0;
    fields_b->append(f_a);

    // Mutate ph_b to STRUCT
    ph_b->kind = TYPE_STRUCT;
    ph_b->as.struct_details.name = "B";
    ph_b->as.struct_details.fields = fields_b;
    ph_b->size = 4;
    ph_b->alignment = 4;

    // Verify final state
    assert(ph_a->kind == TYPE_STRUCT);
    assert(ph_b->kind == TYPE_STRUCT);
    assert((*ph_a->as.struct_details.fields)[0].type->kind == TYPE_POINTER);
    assert((*ph_a->as.struct_details.fields)[0].type->as.pointer.base == ph_b);
    assert((*ph_b->as.struct_details.fields)[0].type->kind == TYPE_POINTER);
    assert((*ph_b->as.struct_details.fields)[0].type->as.pointer.base == ph_a);

    printf("PASSED: Mutual recursion resolution\n");
    return true;
}

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_mutual_recursion_standalone
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
