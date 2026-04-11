#include "name_mangler.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"
#include "platform.hpp"
#include "utils.hpp"

NameMangler::NameMangler(ArenaAllocator& arena, StringInterner& interner, CompilationUnit& unit)
    : arena_(arena), interner_(interner), unit_(unit) {}

const char* NameMangler::mangle(char kind, const char* module_path, const char* local_name) {
    if (isInternalCompilerIdentifier(local_name)) {
        if (!local_name) return interner_.intern("anon");
        char buf[256];
        plat_strcpy(buf, local_name);
        if (plat_strlen(buf) > 31) buf[31] = '\0';
        return interner_.intern(buf);
    }

    if (unit_.isTestMode()) {
        return unit_.getTestName(kind, module_path, local_name);
    }

    if (!local_name) local_name = "anon";

    // Hashed mode
    u32 hash = 0;
    if (module_path) {
        char rel_path[1024];
        get_relative_path(module_path, ".", rel_path, sizeof(rel_path));
        hash = fnv1a_32(rel_path);
    } else {
        hash = fnv1a_32("global");
    }

    char hash_str[8];
    char hex_chars[] = "0123456789abcdef";
    for (int i = 5; i >= 0; --i) {
        hash_str[i] = hex_chars[hash & 0xF];
        hash >>= 4;
    }
    hash_str[6] = '\0';

    char hashed_prefix[32];
    hashed_prefix[0] = 'z';
    hashed_prefix[1] = kind;
    hashed_prefix[2] = '_';
    hashed_prefix[3] = '\0';
    plat_strcat(hashed_prefix, hash_str);
    plat_strcat(hashed_prefix, "_");

    size_t hp_len = plat_strlen(hashed_prefix);
    size_t available = 31 - hp_len;
    size_t local_len = plat_strlen(local_name);

    char final_name[256];
    plat_strcpy(final_name, hashed_prefix);
    if (local_len > available) {
        plat_strcat(final_name, local_name + (local_len - available));
    } else {
        plat_strcat(final_name, local_name);
    }

    ::sanitizeForC89(final_name);
    return interner_.intern(final_name);
}

const char* NameMangler::mangleFunction(const char* name,
                                       DynamicArray<GenericParamInfo>* params,
                                       int param_count,
                                       const char* module) {
    if (isInternalCompilerIdentifier(name)) {
        char buffer[256];
        plat_strcpy(buffer, name);
        if (plat_strlen(buffer) > 31) buffer[31] = '\0';
        return interner_.intern(buffer);
    }

    if (plat_strcmp(name, "main") == 0) return interner_.intern("main");
    if (plat_strcmp(name, "__bootstrap_print") == 0) return interner_.intern("__bootstrap_print");
    if (plat_strcmp(name, "__bootstrap_print_int") == 0) return interner_.intern("__bootstrap_print_int");
    if (plat_strcmp(name, "__bootstrap_print_char") == 0) return interner_.intern("__bootstrap_print_char");
    if (plat_strcmp(name, "__bootstrap_panic") == 0) return interner_.intern("__bootstrap_panic");

    char local_name[512];
    plat_strcpy(local_name, name);

    if (param_count > 0) {
        plat_strcat(local_name, "__");
        for (int i = 0; i < param_count; i++) {
            if (i > 0) plat_strcat(local_name, "_");
            const char* type_str = "";
            if ((*params)[i].kind == GENERIC_PARAM_TYPE) {
                type_str = mangleType((*params)[i].type_value);
            } else if ((*params)[i].kind == GENERIC_PARAM_ANYTYPE) {
                type_str = "any";
            } else {
                type_str = "val";
            }
            plat_strcat(local_name, type_str);
        }
    }

    return mangle('F', module, local_name);
}

const char* NameMangler::mangleTypeName(const char* name, const char* module) {
    return mangle('S', module, name);
}

const char* NameMangler::mangleType(Type* type) {
    if (!type) return "void";

    switch (type->kind) {
        case TYPE_VOID: return "void";
        case TYPE_BOOL: return "bool";
        case TYPE_I8:   return "i8";
        case TYPE_I16:  return "i16";
        case TYPE_I32:  return "i32";
        case TYPE_I64:  return "i64";
        case TYPE_U8:   return "u8";
        case TYPE_U16:  return "u16";
        case TYPE_U32:  return "u32";
        case TYPE_U64:  return "u64";
        case TYPE_F32:  return "f32";
        case TYPE_F64:  return "f64";
        case TYPE_ISIZE: return "isize";
        case TYPE_USIZE: return "usize";
        case TYPE_C_CHAR: return "c_char";
        case TYPE_POINTER: {
            char buf[256];
            plat_strcpy(buf, "Ptr_");
            const char* base = mangleType(type->as.pointer.base);
            plat_strcat(buf, base);
            return interner_.intern(buf);
        }
        case TYPE_SLICE: {
            char buf[256];
            plat_strcpy(buf, "Slice_");
            const char* elem = mangleType(type->as.slice.element_type);
            plat_strcat(buf, elem);
            return interner_.intern(buf);
        }
        case TYPE_ARRAY: {
            char buf[256];
            char* ptr = buf;
            size_t remaining = sizeof(buf);

            safe_append(ptr, remaining, "Arr_");
            char size_buf[21];
            plat_u64_to_string(type->as.array.size, size_buf, sizeof(size_buf));
            safe_append(ptr, remaining, size_buf);
            safe_append(ptr, remaining, "_");

            const char* elem = mangleType(type->as.array.element_type);
            safe_append(ptr, remaining, elem);

            return interner_.intern(buf);
        }
        case TYPE_TYPE: return "type";
        case TYPE_ANYTYPE: return "anytype";
        case TYPE_ERROR_UNION: {
            char buf[256];
            plat_strcpy(buf, "ErrorUnion_");
            const char* payload = mangleType(type->as.error_union.payload);
            plat_strcat(buf, payload);
            return interner_.intern(buf);
        }
        case TYPE_OPTIONAL: {
            char buf[256];
            plat_strcpy(buf, "Optional_");
            const char* payload = mangleType(type->as.optional.payload);
            plat_strcat(buf, payload);
            return interner_.intern(buf);
        }
        case TYPE_STRUCT:
        case TYPE_UNION:
        case TYPE_TAGGED_UNION:
        case TYPE_ENUM: {
            if (type->c_name) return type->c_name;
            const char* name = NULL;
            char kind = 'S';
            if (type->kind == TYPE_ENUM) {
                name = type->as.enum_details.name;
                kind = 'E';
            } else if (type->kind == TYPE_TAGGED_UNION) {
                name = type->as.tagged_union.name;
                kind = 'S';
            } else if (type->kind == TYPE_UNION) {
                name = type->as.struct_details.name;
                kind = 'U';
            } else {
                name = type->as.struct_details.name;
                kind = 'S';
            }

            const char* module_path = type->owner_module ? type->owner_module->filename : NULL;
            
            if (!name) {
                char anon_name[64];
                plat_strcpy(anon_name, "anon_");
                if (type->owner_module) {
                    char count_buf[16];
                    plat_i64_to_string(++type->owner_module->anon_counter, count_buf, sizeof(count_buf));
                    plat_strcat(anon_name, count_buf);
                } else {
                    plat_strcat(anon_name, "0");
                }
                type->c_name = mangle(kind, module_path, anon_name);
                return type->c_name;
            }

            type->c_name = mangle(kind, module_path, name);
            return type->c_name;
        }
        case TYPE_ERROR_SET: {
            if (type->as.error_set.name) {
                return type->as.error_set.name;
            }
            char buf[256];
            char* ptr = buf;
            size_t remaining = sizeof(buf);
            safe_append(ptr, remaining, "errset");
            if (type->as.error_set.tags) {
                for (size_t i = 0; i < type->as.error_set.tags->length(); ++i) {
                    safe_append(ptr, remaining, "_");
                    safe_append(ptr, remaining, (*type->as.error_set.tags)[i]);
                }
            }
            return interner_.intern(buf);
        }
        case TYPE_TUPLE: {
            if (type->c_name) return type->c_name;
            DynamicArray<Type*>* elements = type->as.tuple.elements;
            if (!elements || elements->length() == 0) {
                type->c_name = interner_.intern("Tuple_empty");
                return type->c_name;
            }

            u32 hash = 2166136261u;
            for (size_t i = 0; i < elements->length(); ++i) {
                const char* elem_name = mangleType((*elements)[i]);
                for (const char* p = elem_name; *p; ++p) {
                    hash ^= (u8)*p;
                    hash *= 16777619u;
                }
            }

            char buf[64];
            plat_snprintf(buf, sizeof(buf), "Tuple_%08x", hash);
            type->c_name = interner_.intern(buf);
            return type->c_name;
        }
        default: return "type";
    }
}
