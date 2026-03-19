#include "type_registry.hpp"
#include "memory.hpp"
#include "utils.hpp"
#include <cstdio>

// Mock structures for testing
struct Module {
    const char* name;
};

struct Type {
    const char* name;
};

void test_basic_insert_lookup() {
    ArenaAllocator arena(1024 * 1024);
    TypeRegistry registry(arena);

    Module mod_a = { "ModuleA" };
    Type type_1 = { "StructA" };

    if (registry.insert(&mod_a, "Foo", &type_1) != TypeRegistry::OK) {
        printf("FAILED: Basic insert\n");
        return;
    }

    if (registry.find(&mod_a, "Foo") != &type_1) {
        printf("FAILED: Basic lookup\n");
        return;
    }

    printf("PASSED: Basic insert & lookup\n");
}

void test_duplicate_prevention() {
    ArenaAllocator arena(1024 * 1024);
    TypeRegistry registry(arena);

    Module mod_a = { "ModuleA" };
    Type type_1 = { "StructA" };

    registry.insert(&mod_a, "Foo", &type_1);
    if (registry.insert(&mod_a, "Foo", &type_1) != TypeRegistry::DUPLICATE) {
        printf("FAILED: Duplicate prevention\n");
        return;
    }

    printf("PASSED: Duplicate prevention\n");
}

void test_namespace_isolation() {
    ArenaAllocator arena(1024 * 1024);
    TypeRegistry registry(arena);

    Module mod_a = { "ModuleA" };
    Module mod_b = { "ModuleB" };
    Type type_1 = { "StructA" };
    Type type_2 = { "StructB" };

    registry.insert(&mod_a, "Foo", &type_1);
    if (registry.insert(&mod_b, "Foo", &type_2) != TypeRegistry::OK) {
        printf("FAILED: Namespace isolation insert\n");
        return;
    }

    if (registry.find(&mod_a, "Foo") != &type_1) {
        printf("FAILED: Namespace isolation lookup A\n");
        return;
    }

    if (registry.find(&mod_b, "Foo") != &type_2) {
        printf("FAILED: Namespace isolation lookup B\n");
        return;
    }

    printf("PASSED: Namespace isolation\n");
}

int main() {
    test_basic_insert_lookup();
    test_duplicate_prevention();
    test_namespace_isolation();
    return 0;
}
