#include "c89_pattern_generator.hpp"
#include "c89_type_mapping.hpp"
#include "utils.hpp"
#include "platform.hpp"

C89PatternGenerator::C89PatternGenerator(ArenaAllocator& arena) : arena_(arena) {}

const char* C89PatternGenerator::generatePattern(const ErrorFunctionInfo& info) {
    // Strategy selection logic based on metadata
    if (info.error_union_size <= 64 && info.msvc6_stack_safe) {
        return generateStructReturn(info);
    } else if (info.error_union_size <= 1024) {
        return generateArenaAllocation(info); // Actually user suggested Arena for intermediate
    } else {
        return generateOutParameter(info);
    }
}

void C89PatternGenerator::typeToC89(Type* type, char* buffer, size_t buffer_size) {
    if (!type) {
        plat_strncpy(buffer, "void", buffer_size);
        return;
    }

    switch (type->kind) {
        case TYPE_POINTER: {
            char base_name[128];
            typeToC89(type->as.pointer.base, base_name, sizeof(base_name));
            char* cur = buffer;
            size_t rem = buffer_size;
            safe_append(cur, rem, base_name);
            safe_append(cur, rem, "*");
            break;
        }
        case TYPE_ARRAY:
            plat_strncpy(buffer, "struct PlaceholderArray", buffer_size);
            break;
        case TYPE_STRUCT:
            plat_strncpy(buffer, "struct PlaceholderStruct", buffer_size);
            break;
        case TYPE_ENUM:
            plat_strncpy(buffer, "int", buffer_size); // Simplified
            break;
        default: {
            const size_t map_size = sizeof(c89_type_map) / sizeof(c89_type_map[0]);
            for (size_t i = 0; i < map_size; ++i) {
                if (type->kind == c89_type_map[i].zig_type_kind) {
                    plat_strncpy(buffer, c89_type_map[i].c89_type_name, buffer_size);
                    return;
                }
            }
            plat_strncpy(buffer, "void", buffer_size);
            break;
        }
    }
}

void C89PatternGenerator::getTypeSuffix(Type* type, char* buffer, size_t buffer_size) {
    if (!type) {
        plat_strncpy(buffer, "Void", buffer_size);
        return;
    }

    switch (type->kind) {
        case TYPE_I32: plat_strncpy(buffer, "Int32", buffer_size); break;
        case TYPE_U32: plat_strncpy(buffer, "UInt32", buffer_size); break;
        case TYPE_I8: plat_strncpy(buffer, "Int8", buffer_size); break;
        case TYPE_U8: plat_strncpy(buffer, "UInt8", buffer_size); break;
        case TYPE_BOOL: plat_strncpy(buffer, "Bool", buffer_size); break;
        case TYPE_VOID: plat_strncpy(buffer, "Void", buffer_size); break;
        case TYPE_POINTER: plat_strncpy(buffer, "Ptr", buffer_size); break;
        case TYPE_ARRAY: plat_strncpy(buffer, "Array", buffer_size); break;
        case TYPE_STRUCT: plat_strncpy(buffer, "Struct", buffer_size); break;
        default: plat_strncpy(buffer, "Unknown", buffer_size); break;
    }
}

const char* C89PatternGenerator::generateStructReturn(const ErrorFunctionInfo& info) {
    char payload_name[128];
    typeToC89(info.payload_type, payload_name, sizeof(payload_name));

    char type_suffix[64];
    getTypeSuffix(info.payload_type, type_suffix, sizeof(type_suffix));

    char buffer[1024];
    char* cur = buffer;
    size_t rem = sizeof(buffer);
    buffer[0] = '\0';

    safe_append(cur, rem, "typedef struct {\n");
    safe_append(cur, rem, "    union {\n");
    safe_append(cur, rem, "        ");
    safe_append(cur, rem, payload_name);
    safe_append(cur, rem, " value;\n");
    safe_append(cur, rem, "        int error_code;\n");
    safe_append(cur, rem, "    } data;\n");
    safe_append(cur, rem, "    int is_error;\n");
    safe_append(cur, rem, "} Errorable");
    safe_append(cur, rem, type_suffix);
    safe_append(cur, rem, ";\n\n");

    safe_append(cur, rem, "Errorable");
    safe_append(cur, rem, type_suffix);
    safe_append(cur, rem, " ");
    safe_append(cur, rem, info.name);
    safe_append(cur, rem, "(void) {\n");
    safe_append(cur, rem, "    Errorable");
    safe_append(cur, rem, type_suffix);
    safe_append(cur, rem, " result = {0};\n");
    safe_append(cur, rem, "    return result;\n");
    safe_append(cur, rem, "}\n");

    return arena_.allocString(buffer);
}

const char* C89PatternGenerator::generateOutParameter(const ErrorFunctionInfo& info) {
    char payload_name[128];
    typeToC89(info.payload_type, payload_name, sizeof(payload_name));

    char buffer[1024];
    char* cur = buffer;
    size_t rem = sizeof(buffer);
    buffer[0] = '\0';

    safe_append(cur, rem, "int ");
    safe_append(cur, rem, info.name);
    safe_append(cur, rem, "(");
    safe_append(cur, rem, payload_name);
    safe_append(cur, rem, "* out_value) {\n");
    safe_append(cur, rem, "    /* Returns error code, 0 for success */\n");
    safe_append(cur, rem, "    if (!out_value) return 1; /* ERROR_NULL_ARGUMENT */\n");
    safe_append(cur, rem, "    return 0; /* SUCCESS */\n");
    safe_append(cur, rem, "}\n");

    return arena_.allocString(buffer);
}

const char* C89PatternGenerator::generateArenaAllocation(const ErrorFunctionInfo& info) {
    char payload_name[128];
    typeToC89(info.payload_type, payload_name, sizeof(payload_name));

    char type_suffix[64];
    getTypeSuffix(info.payload_type, type_suffix, sizeof(type_suffix));

    char buffer[1024];
    char* cur = buffer;
    size_t rem = sizeof(buffer);
    buffer[0] = '\0';

    safe_append(cur, rem, "typedef struct {\n");
    safe_append(cur, rem, "    union {\n");
    safe_append(cur, rem, "        ");
    safe_append(cur, rem, payload_name);
    safe_append(cur, rem, "* value_ptr;\n");
    safe_append(cur, rem, "        int error_code;\n");
    safe_append(cur, rem, "    } data;\n");
    safe_append(cur, rem, "    int is_error;\n");
    safe_append(cur, rem, "} Errorable");
    safe_append(cur, rem, type_suffix);
    safe_append(cur, rem, "Ptr;\n\n");

    safe_append(cur, rem, "Errorable");
    safe_append(cur, rem, type_suffix);
    safe_append(cur, rem, "Ptr ");
    safe_append(cur, rem, info.name);
    safe_append(cur, rem, "(void* arena) {\n");
    safe_append(cur, rem, "    Errorable");
    safe_append(cur, rem, type_suffix);
    safe_append(cur, rem, "Ptr result = {0};\n");
    safe_append(cur, rem, "    /* Payload allocated from arena if not error */\n");
    safe_append(cur, rem, "    return result;\n");
    safe_append(cur, rem, "}\n");

    return arena_.allocString(buffer);
}
