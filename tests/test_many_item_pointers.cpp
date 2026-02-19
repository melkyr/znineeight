#include "test_utils.hpp"
#include "test_declarations.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "type_system.hpp"

bool test_ManyItemPointer_Parsing() {
    const char* source = "const p: [*]u8 = undefined;";
    return run_type_checker_test_successfully(source);
}

bool test_ManyItemPointer_Indexing() {
    const char* source =
        "fn foo(p: [*]u8) u8 {\n"
        "    return p[0];\n"
        "}\n";
    return run_type_checker_test_successfully(source);
}

bool test_SingleItemPointer_Indexing_Rejected() {
    const char* source =
        "fn foo(p: *u8) u8 {\n"
        "    return p[0];\n"
        "}\n";
    return expect_type_checker_abort(source);
}

bool test_ManyItemPointer_Dereference_Allowed() {
    const char* source =
        "fn foo(p: [*]u8) u8 {\n"
        "    return p.*;\n"
        "}\n";
    return run_type_checker_test_successfully(source);
}

bool test_ManyItemPointer_Arithmetic() {
    const char* source =
        "fn foo(p: [*]u8) [*]u8 {\n"
        "    return p + 1;\n"
        "}\n";
    return run_type_checker_test_successfully(source);
}

bool test_SingleItemPointer_Arithmetic_Rejected() {
    const char* source =
        "fn foo(p: *u8) *u8 {\n"
        "    return p + 1;\n"
        "}\n";
    return expect_type_checker_abort(source);
}

bool test_Pointer_Conversion_Rejected() {
    const char* source =
        "fn foo(p: [*]u8) *u8 {\n"
        "    const p2: *u8 = p;\n"
        "    return p2;\n"
        "}\n";
    return expect_type_checker_abort(source);
}

bool test_ManyItemPointer_Null() {
    const char* source = "const p: [*]u8 = null;";
    return run_type_checker_test_successfully(source);
}

bool test_ManyItemPointer_TypeToString() {
    ArenaAllocator arena(256 * 1024);
    TypeInterner interner(arena);
    Type* u8_type = get_g_type_u8();

    Type* many_ptr = createPointerType(arena, u8_type, false, true, &interner);
    char buf[64];
    typeToString(many_ptr, buf, sizeof(buf));

    if (plat_strcmp(buf, "[*]u8") != 0) {
        plat_print_debug("Expected [*]u8, got ");
        plat_print_debug(buf);
        plat_print_debug("\n");
        return false;
    }

    Type* many_const_ptr = createPointerType(arena, u8_type, true, true, &interner);
    typeToString(many_const_ptr, buf, sizeof(buf));
    if (plat_strcmp(buf, "[*]const u8") != 0) {
        plat_print_debug("Expected [*]const u8, got ");
        plat_print_debug(buf);
        plat_print_debug("\n");
        return false;
    }

    return true;
}
