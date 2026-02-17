#include "test_framework.hpp"
#include "name_mangler.hpp"
#include "type_system.hpp"
#include "memory.hpp"

TEST_FUNC(NameMangler_Milestone4Types) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    // Error Union: !i32 -> err_i32
    Type* i32_type = get_g_type_i32();
    Type* err_union = createErrorUnionType(arena, i32_type, NULL, true);
    ASSERT_STREQ("err_i32", mangler.mangleType(err_union));

    // Optional: ?u8 -> opt_u8
    Type* u8_type = get_g_type_u8();
    Type* optional_type = createOptionalType(arena, u8_type);
    ASSERT_STREQ("opt_u8", mangler.mangleType(optional_type));

    // Error Set: error{A, B} -> errset_A_B
    DynamicArray<const char*>* tags = new (arena.alloc(sizeof(DynamicArray<const char*>))) DynamicArray<const char*>(arena);
    tags->append(interner.intern("A"));
    tags->append(interner.intern("B"));
    Type* err_set = createErrorSetType(arena, NULL, tags, true);
    ASSERT_STREQ("errset_A_B", mangler.mangleType(err_set));

    // Named Error Set: MyError -> MyError
    Type* named_err_set = createErrorSetType(arena, interner.intern("MyError"), tags, false);
    ASSERT_STREQ("MyError", mangler.mangleType(named_err_set));

    return true;
}
