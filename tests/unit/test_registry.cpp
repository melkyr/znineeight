#include "type_registry.hpp"
#include "memory.hpp"
#include "utils.hpp"
#include "type_system.hpp"
#include <cstdio>

#ifdef Z98_TEST
#include "module.hpp"
#else
// Mock Module for registry testing to avoid full dependencies in standalone
struct Module {
    const char* name;
    Module(const char* n) : name(n) {}
};
#endif

void test_basic_insert_lookup() {
    ArenaAllocator arena(1024 * 1024);
    TypeRegistry registry(arena);

#ifdef Z98_TEST
    Module mod_a(arena);
    mod_a.name = "ModuleA";
#else
    Module mod_a("ModuleA");
#endif
    Type type_1;
    plat_memset(&type_1, 0, sizeof(Type));
    type_1.kind = TYPE_STRUCT;

    if (registry.insert((struct Module*)&mod_a, "Foo", &type_1) != TypeRegistry::OK) {
        printf("FAILED: Basic insert\n");
        return;
    }

    if (registry.find((struct Module*)&mod_a, "Foo") != &type_1) {
        printf("FAILED: Basic lookup\n");
        return;
    }

    printf("PASSED: Basic insert & lookup\n");
}

void test_duplicate_prevention() {
    ArenaAllocator arena(1024 * 1024);
    TypeRegistry registry(arena);

#ifdef Z98_TEST
    Module mod_a(arena);
    mod_a.name = "ModuleA";
#else
    Module mod_a("ModuleA");
#endif
    Type type_1;
    plat_memset(&type_1, 0, sizeof(Type));
    type_1.kind = TYPE_STRUCT;

    registry.insert((struct Module*)&mod_a, "Foo", &type_1);
    if (registry.insert((struct Module*)&mod_a, "Foo", &type_1) != TypeRegistry::DUPLICATE) {
        printf("FAILED: Duplicate prevention\n");
        return;
    }

    printf("PASSED: Duplicate prevention\n");
}

void test_namespace_isolation() {
    ArenaAllocator arena(1024 * 1024);
    TypeRegistry registry(arena);

#ifdef Z98_TEST
    Module mod_a(arena);
    mod_a.name = "ModuleA";
    Module mod_b(arena);
    mod_b.name = "ModuleB";
#else
    Module mod_a("ModuleA");
    Module mod_b("ModuleB");
#endif
    Type type_1;
    plat_memset(&type_1, 0, sizeof(Type));
    type_1.kind = TYPE_STRUCT;
    Type type_2;
    plat_memset(&type_2, 0, sizeof(Type));
    type_2.kind = TYPE_STRUCT;

    registry.insert((struct Module*)&mod_a, "Foo", &type_1);
    if (registry.insert((struct Module*)&mod_b, "Foo", &type_2) != TypeRegistry::OK) {
        printf("FAILED: Namespace isolation insert\n");
        return;
    }

    if (registry.find((struct Module*)&mod_a, "Foo") != &type_1) {
        printf("FAILED: Namespace isolation lookup A\n");
        return;
    }

    if (registry.find((struct Module*)&mod_b, "Foo") != &type_2) {
        printf("FAILED: Namespace isolation lookup B\n");
        return;
    }

    printf("PASSED: Namespace isolation\n");
}

#ifndef Z98_TEST
int main() {
    test_basic_insert_lookup();
    test_duplicate_prevention();
    test_namespace_isolation();
    return 0;
}
#endif
