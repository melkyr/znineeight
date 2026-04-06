#include "codegen.hpp"
#include "compilation_unit.hpp"
#include "ast_utils.hpp"
#include <new>
#include "platform.hpp"
#include "utils.hpp"
#include "symbol_table.hpp"

static const size_t TYPE_DEF_BUFFER_SIZE = 131072;

const char* const C89Emitter::KW_BREAK = "break";
const char* const C89Emitter::KW_CONTINUE = "continue";
const char* const C89Emitter::KW_RETURN = "return";
const char* const C89Emitter::KW_GOTO = "goto";
const char* const C89Emitter::KW_IF = "if";
const char* const C89Emitter::KW_ELSE = "else";
const char* const C89Emitter::KW_WHILE = "while";
const char* const C89Emitter::KW_FOR = "for";
const char* const C89Emitter::KW_SWITCH = "switch";
const char* const C89Emitter::KW_CASE = "case";
const char* const C89Emitter::KW_DEFAULT = "default";
const char* const C89Emitter::KW_STRUCT = "struct";
const char* const C89Emitter::KW_UNION = "union";
const char* const C89Emitter::KW_ENUM = "enum";
const char* const C89Emitter::KW_TYPEDEF = "typedef";
const char* const C89Emitter::KW_EXTERN = "extern";
const char* const C89Emitter::KW_STATIC = "static";
const char* const C89Emitter::KW_CONST = "const";
const char* const C89Emitter::KW_VOID = "void";
const char* const C89Emitter::KW_INT = "int";
const char* const C89Emitter::KW_SIZEOF = "sizeof";
const char* const C89Emitter::KW_CHAR = "char";
const char* const C89Emitter::KW_SHORT = "short";
const char* const C89Emitter::KW_LONG = "long";
const char* const C89Emitter::KW_FLOAT = "float";
const char* const C89Emitter::KW_DOUBLE = "double";
const char* const C89Emitter::KW_SIGNED = "signed";
const char* const C89Emitter::KW_UNSIGNED = "unsigned";
const char* const C89Emitter::KW_REGISTER = "register";
const char* const C89Emitter::KW_VOLATILE = "volatile";

C89Emitter::C89Emitter(CompilationUnit& unit, bool is_header)
    : TextWriter(unit.getOptions().win_friendly_line_endings ? "\r\n" : "\n"),
      buffer_pos_(0), output_file_(PLAT_INVALID_FILE), indent_level_(0), owns_file_(false),
      debug_trace_(false), emit_depth_(0), emitted_decls_(unit.getTransientArena()),
      unit_(unit), var_alloc_(unit.getTransientArena()), error_handler_(unit.getErrorHandler()), arena_(unit.getArena()), transient_arena_(unit.getTransientArena()),
      global_names_(unit.getArena()),
      used_names_(unit.getTransientArena()),
      emitted_slices_(unit.getTransientArena()), emitted_error_unions_(unit.getTransientArena()), emitted_optionals_(unit.getTransientArena()), emitted_enums_(unit.getTransientArena()), emitted_forward_decls_(unit.getTransientArena()), external_cache_(is_header ? NULL : &unit.getEmittedTypesCache()),
      defer_stack_(unit.getTransientArena()), current_fn_ret_type_(NULL), current_err_flag_(NULL), is_header_(is_header),
      type_def_buffer_(NULL), type_def_pos_(0), type_def_cap_(TYPE_DEF_BUFFER_SIZE), in_type_def_mode_(false),
      module_name_(NULL), current_fn_name_(NULL), is_main_function_(false), last_char_('\0'), for_loop_counter_(0), current_loc_(),
      max_string_literal_chunk_(1024),
      loop_id_stack_(unit.getTransientArena()),
      loop_has_continue_(unit.getTransientArena()) {
    type_def_buffer_ = (char*)transient_arena_.alloc(type_def_cap_);
    plat_memset(loop_uses_labels_, 0, sizeof(loop_uses_labels_));
}

C89Emitter::C89Emitter(CompilationUnit& unit, const char* path, bool is_header)
    : TextWriter(unit.getOptions().win_friendly_line_endings ? "\r\n" : "\n"),
      buffer_pos_(0), indent_level_(0), owns_file_(true),
      debug_trace_(false), emit_depth_(0), emitted_decls_(unit.getTransientArena()),
      unit_(unit), var_alloc_(unit.getTransientArena()), error_handler_(unit.getErrorHandler()), arena_(unit.getArena()), transient_arena_(unit.getTransientArena()),
      global_names_(unit.getArena()),
      used_names_(unit.getTransientArena()),
      emitted_slices_(unit.getTransientArena()), emitted_error_unions_(unit.getTransientArena()), emitted_optionals_(unit.getTransientArena()), emitted_enums_(unit.getTransientArena()), emitted_forward_decls_(unit.getTransientArena()), external_cache_(is_header ? NULL : &unit.getEmittedTypesCache()),
      defer_stack_(unit.getTransientArena()), current_fn_ret_type_(NULL), current_err_flag_(NULL), is_header_(is_header),
      type_def_buffer_(NULL), type_def_pos_(0), type_def_cap_(TYPE_DEF_BUFFER_SIZE), in_type_def_mode_(false),
      module_name_(NULL), current_fn_name_(NULL), is_main_function_(false), last_char_('\0'), for_loop_counter_(0), current_loc_(),
      max_string_literal_chunk_(1024),
      loop_id_stack_(unit.getTransientArena()),
      loop_has_continue_(unit.getTransientArena()) {
    output_file_ = plat_open_file(path, true);
    type_def_buffer_ = (char*)transient_arena_.alloc(type_def_cap_);
    plat_memset(loop_uses_labels_, 0, sizeof(loop_uses_labels_));
}


C89Emitter::C89Emitter(CompilationUnit& unit, PlatFile file, bool is_header)
    : TextWriter(unit.getOptions().win_friendly_line_endings ? "\r\n" : "\n"),
      buffer_pos_(0), output_file_(file), indent_level_(0), owns_file_(false),
      debug_trace_(false), emit_depth_(0), emitted_decls_(unit.getTransientArena()),
      unit_(unit), var_alloc_(unit.getTransientArena()), error_handler_(unit.getErrorHandler()), arena_(unit.getArena()), transient_arena_(unit.getTransientArena()),
      global_names_(unit.getArena()),
      used_names_(unit.getTransientArena()),
      emitted_slices_(unit.getTransientArena()), emitted_error_unions_(unit.getTransientArena()), emitted_optionals_(unit.getTransientArena()), emitted_enums_(unit.getTransientArena()), emitted_forward_decls_(unit.getTransientArena()), external_cache_(is_header ? NULL : &unit.getEmittedTypesCache()),
      defer_stack_(unit.getTransientArena()), current_fn_ret_type_(NULL), current_err_flag_(NULL), is_header_(is_header),
      type_def_buffer_(NULL), type_def_pos_(0), type_def_cap_(TYPE_DEF_BUFFER_SIZE), in_type_def_mode_(false),
      module_name_(NULL), current_fn_name_(NULL), is_main_function_(false), last_char_('\0'), for_loop_counter_(0), current_loc_(),
      max_string_literal_chunk_(1024),
      loop_id_stack_(unit.getTransientArena()),
      loop_has_continue_(unit.getTransientArena()) {
    type_def_buffer_ = (char*)transient_arena_.alloc(type_def_cap_);
    plat_memset(loop_uses_labels_, 0, sizeof(loop_uses_labels_));
}

C89Emitter::~C89Emitter() {
    close();
}

void C89Emitter::indent() {
    indent_level_++;
}

void C89Emitter::dedent() {
    if (indent_level_ > 0) {
        indent_level_--;
    }
}

void C89Emitter::writeIndent() {
    for (int i = 0; i < indent_level_; ++i) {
        write("    ", 4);
    }
}

void C89Emitter::emitPrologue() {
    emitComment("Generated by Z98 bootstrap compiler");
    emitSymbolMap();
    writeString("#include <string.h>\n");
    writeString("#include \"zig_runtime.h\"\n");
    writeString("#include \"zig_special_types.h\"\n\n");

    /* Emit error tag constants */
    const DynamicArray<ErrorTag>& tags = unit_.getGlobalErrorRegistry().getTags();
    if (tags.length() > 0) {
        emitComment("Error tags");
        for (size_t i = 0; i < tags.length(); ++i) {
            char buffer[512];
            char* ptr = buffer;
            size_t remaining = sizeof(buffer);
            safe_append(ptr, remaining, "#define ERROR_");
            safe_append(ptr, remaining, tags[i].name);
            safe_append(ptr, remaining, " ");
            char id_buf[16];
            plat_i64_to_string(tags[i].id, id_buf, sizeof(id_buf));
            safe_append(ptr, remaining, id_buf);
            safe_append(ptr, remaining, "\n");
            writeString(buffer);
        }
        writeLine();
    }
}

void C89Emitter::beginFunction() {
    var_alloc_.reset();
    for_loop_counter_ = 0;
    plat_memset(loop_uses_labels_, 0, sizeof(loop_uses_labels_));
    loop_id_stack_.clear();
}

void C89Emitter::emitType(Type* type, const char* name) {
    emitDeclarator(type, name);
}

void C89Emitter::emitDeclarator(Type* type, const char* name, const ASTFnDeclNode* params_node) {
    emitTypePrefix(type);
    if (name && type->kind != TYPE_ANYTYPE) {
        if (last_char_ != '(' && last_char_ != ' ') {
            writeString(" ");
        }
        writeString(name);
    }

    if (params_node) {
        writeString("(");
        if (!params_node->params || params_node->params->length() == 0) {
            writeString(KW_VOID);
        } else {
            for (size_t i = 0; i < params_node->params->length(); ++i) {
                ASTNode* param_node = (*params_node->params)[i];
                ASTParamDeclNode& param = param_node->as.param_decl;
                if (param.is_anytype) {
                    writeString("...");
                    break;
                }
                /* For definition (within FnDecl), use mangled local name. */
                /* For prototype, use original name. */
                const char* param_name = param.symbol ? var_alloc_.allocate(param.symbol) : param.name;
                emitDeclarator(param.type->resolved_type, param_name);
                if (i < params_node->params->length() - 1) {
                    writeString(", ");
                }
            }
        }
        writeString(")");
    }

    emitTypeSuffix(type);
}

void C89Emitter::emitTypePrefix(Type* type) {
    if (!type) {
        writeString(KW_VOID);
        return;
    }

    switch (type->kind) {
        case TYPE_POINTER:
            if (type->as.pointer.base && type->as.pointer.base->kind == TYPE_VOID) {
                writeString(KW_VOID);
                if (last_char_ != ' ') {
                    writeString(" ");
                }
                writeString("*");
                break;
            }
            if (type->as.pointer.base) {
                emitTypePrefix(type->as.pointer.base);
            } else {
                writeKeyword(KW_VOID);
            }
            if (type->as.pointer.is_const) {
                writeString(" const");
            }
            if (type->as.pointer.base && type->as.pointer.base->kind != TYPE_POINTER &&
                (type->as.pointer.base->kind == TYPE_ARRAY ||
                 type->as.pointer.base->kind == TYPE_FUNCTION_POINTER ||
                 type->as.pointer.base->kind == TYPE_FUNCTION)) {
                writeString(" (*");
            } else {
                /* No space before asterisk for simple pointers to match existing tests and convention */
                writeString("*");
            }
            break;
        case TYPE_ARRAY:
            emitTypePrefix(type->as.array.element_type);
            break;
        case TYPE_FUNCTION:
            emitTypePrefix(type->as.function.return_type);
            break;
        case TYPE_FUNCTION_POINTER:
            emitTypePrefix(type->as.function_pointer.return_type);
            writeString(" (*");
            break;
        default:
            emitBaseType(type);
            break;
    }
}

void C89Emitter::emitTypeSuffix(Type* type) {
    if (!type) return;

    switch (type->kind) {
        case TYPE_POINTER:
            if (type->as.pointer.base && type->as.pointer.base->kind == TYPE_VOID) {
                break;
            }
            if (type->as.pointer.base && type->as.pointer.base->kind != TYPE_POINTER &&
                (type->as.pointer.base->kind == TYPE_ARRAY ||
                 type->as.pointer.base->kind == TYPE_FUNCTION_POINTER ||
                 type->as.pointer.base->kind == TYPE_FUNCTION)) {
                writeString(")");
            }
            if (type->as.pointer.base) {
                emitTypeSuffix(type->as.pointer.base);
            }
            break;
        case TYPE_ARRAY: {
            char buf[32];
            writeString("[");
            plat_u64_to_string(type->as.array.size, buf, sizeof(buf));
            writeString(buf);
            writeString("]");
            emitTypeSuffix(type->as.array.element_type);
            break;
        }
        case TYPE_FUNCTION: {
            writeString("(");
            DynamicArray<Type*>* params = type->as.function.params;
            if (!params || params->length() == 0) {
                writeString(KW_VOID);
            } else {
                for (size_t i = 0; i < params->length(); ++i) {
                    if ((*params)[i]->kind == TYPE_ANYTYPE) {
                        writeString("...");
                        break;
                    }
                    emitDeclarator((*params)[i], NULL);
                    if (i < params->length() - 1) writeString(", ");
                }
            }
            writeString(")");
            emitTypeSuffix(type->as.function.return_type);
            break;
        }
        case TYPE_FUNCTION_POINTER: {
            writeString(")");
            writeString("(");
            DynamicArray<Type*>* params = type->as.function_pointer.param_types;
            if (!params || params->length() == 0) {
                writeString(KW_VOID);
            } else {
                for (size_t i = 0; i < params->length(); ++i) {
                    emitDeclarator((*params)[i], NULL);
                    if (i < params->length() - 1) writeString(", ");
                }
            }
            writeString(")");
            emitTypeSuffix(type->as.function_pointer.return_type);
            break;
        }
        default:
            break;
    }
}

void C89Emitter::emitBaseType(Type* type) {
    if (!type) {
        writeString(KW_VOID);
        return;
    }

    switch (type->kind) {
        case TYPE_VOID: writeString(KW_VOID); break;
        case TYPE_BOOL: writeString(KW_INT); break;
        case TYPE_I8: writeKeyword(KW_SIGNED); writeString(KW_CHAR); break;
        case TYPE_U8: writeKeyword(KW_UNSIGNED); writeString(KW_CHAR); break;
        case TYPE_I16: writeString(KW_SHORT); break;
        case TYPE_U16: writeKeyword(KW_UNSIGNED); writeString(KW_SHORT); break;
        case TYPE_I32: writeString(KW_INT); break;
        case TYPE_U32: writeKeyword(KW_UNSIGNED); writeString(KW_INT); break;
        case TYPE_I64:
            #ifdef _MSC_VER
            writeString("__int64");
            #else
            writeString("i64");
            #endif
            break;
        case TYPE_U64:
            #ifdef _MSC_VER
            writeString("unsigned __int64");
            #else
            writeString("u64");
            #endif
            break;
        case TYPE_C_CHAR: writeString(KW_CHAR); break;
        case TYPE_F32: writeString(KW_FLOAT); break;
        case TYPE_F64: writeString(KW_DOUBLE); break;
        case TYPE_ISIZE: writeString("isize"); break;
        case TYPE_USIZE: writeString("usize"); break;
        case TYPE_SLICE:
            ensureSliceType(type);
            writeString(getMangledTypeName(type));
            break;
        case TYPE_ERROR_UNION:
            ensureErrorUnionType(type);
            writeString(getMangledTypeName(type));
            break;
        case TYPE_OPTIONAL:
            ensureOptionalType(type);
            writeString(getMangledTypeName(type));
            break;
        case TYPE_ERROR_SET:
            writeString(KW_INT);
            break;
        case TYPE_STRUCT:
            if (!type->c_name && type->as.struct_details.name) {
                type->c_name = unit_.getNameMangler().mangleType(type);
            }
            if (type->c_name) {
                writeKeyword(KW_STRUCT);
                writeString(type->c_name);
            } else {
                writeKeyword(KW_STRUCT);
                emitStructBody(type);
            }
            break;
        case TYPE_UNION:
        case TYPE_TAGGED_UNION:
            if (isTaggedUnion(type)) {
                const char* name = (type->kind == TYPE_TAGGED_UNION) ? type->as.tagged_union.name : type->as.struct_details.name;
                if (!type->c_name && name) {
                    type->c_name = unit_.getNameMangler().mangleType(type);
                }
                if (type->c_name) {
                    writeKeyword(KW_STRUCT);
                    writeString(type->c_name);
                } else {
                    writeKeyword(KW_STRUCT);
                    emitTaggedUnionBody(type);
                }
            } else {
                if (!type->c_name && type->as.struct_details.name) {
                    type->c_name = unit_.getNameMangler().mangleType(type);
                }
                if (type->c_name) {
                    writeKeyword(KW_UNION);
                    writeString(type->c_name);
                } else {
                    writeKeyword(KW_UNION);
                    emitUnionBody(type);
                }
            }
            break;
        case TYPE_ENUM:
            writeKeyword(KW_ENUM);
            if (!type->c_name && type->as.enum_details.name) {
                type->c_name = unit_.getNameMangler().mangleType(type);
            }
            if (type->c_name) {
                writeString(type->c_name);
            } else {
                writeString("/* anonymous */");
            }
            break;
        case TYPE_ANYTYPE:
            writeString("...");
            break;
        default:
            writeString("/* unsupported type */");
            break;
    }
}

void C89Emitter::emitGlobalVarDecl(const ASTNode* node, bool is_public) {
    if (!node || node->type != NODE_VAR_DECL) return;
    const ASTVarDeclNode* decl = node->as.var_decl;

    /* Use flags from node, but allow override from is_public for now to avoid breaking tests */
    bool external = is_public || decl->is_pub || decl->is_extern || decl->is_export;

    /* Skip type and module declarations (e.g. const T = struct { ... } or const std = @import("std")) */
    if (decl->initializer) {
        if (decl->initializer->type == NODE_IMPORT_STMT ||
            (decl->initializer->resolved_type && decl->initializer->resolved_type->kind == TYPE_MODULE)) {
            return;
        }
        if (decl->is_const && isTypeExpression(decl->initializer, unit_.getSymbolTable())) {
            return;
        }
    }

    if (decl->initializer && decl->initializer->type != NODE_UNDEFINED_LITERAL && !isConstantInitializer(decl->initializer)) {
        error_handler_.report(ERR_GLOBAL_VAR_NON_CONSTANT_INIT, decl->name_loc, ErrorHandler::getMessage(ERR_GLOBAL_VAR_NON_CONSTANT_INIT), "Try using a literal or a constant expression");
        return;
    }

    writeIndent();
    if (decl->is_extern) {
        writeKeyword(KW_EXTERN);
    } else if (!external) {
        writeKeyword(KW_STATIC);
    }

    bool is_const_in_c = false;
    if (decl->is_const) {
        if (decl->initializer && isConstantInitializer(decl->initializer)) {
            is_const_in_c = true;
        }
    }

    if (is_const_in_c) {
        writeKeyword(KW_CONST);
    }

    Type* type = node->resolved_type;
    const char* c_name = NULL;
    if (decl->symbol && (decl->symbol->flags & SYMBOL_FLAG_EXTERN)) {
        c_name = decl->symbol->name;
    } else if (decl->symbol && decl->symbol->mangled_name) {
        c_name = decl->symbol->mangled_name;
    } else if (decl->is_extern) {
        c_name = decl->name;
    } else {
        c_name = getC89GlobalName(decl->name);
    }

    emitDeclarator(type, c_name);

    if (decl->initializer && decl->initializer->type != NODE_UNDEFINED_LITERAL) {
        writeString(" = ");
        if (type && type->kind == TYPE_OPTIONAL && decl->initializer->type == NODE_NULL_LITERAL) {
            writeString("{0}");
        } else {
            emitExpression(decl->initializer);
        }
    }

    endStmt();
}

void C89Emitter::emitInitializerAssignments(const char* base_name, const ASTNode* init_node) {
    if (!init_node || init_node->type != NODE_STRUCT_INITIALIZER) return;
    const ASTStructInitializerNode* init = init_node->as.struct_initializer;
    Type* type = init_node->resolved_type;

    if (!type) return;

    if (type->kind == TYPE_STRUCT || type->kind == TYPE_UNION || type->kind == TYPE_TAGGED_UNION || type->kind == TYPE_ERROR_UNION || type->kind == TYPE_OPTIONAL || type->kind == TYPE_ANYTYPE) {
        if (type->kind == TYPE_ERROR_UNION || type->kind == TYPE_OPTIONAL || type->kind == TYPE_ANYTYPE) {
            /* Handle ErrorUnion and Optional special structures */
            const ASTStructInitializerNode* init = init_node->as.struct_initializer;
            for (size_t j = 0; j < init->fields->length(); ++j) {
                ASTNamedInitializer* field_init = (*init->fields)[j];
                char nested_name[256];
                char* cur = nested_name;
                size_t rem = sizeof(nested_name);
                safe_append(cur, rem, base_name);
                safe_append(cur, rem, ".");
                safe_append(cur, rem, field_init->field_name);

                Type* f_type = NULL;
                if (type->kind == TYPE_OPTIONAL) {
                    if (plat_strcmp(field_init->field_name, "value") == 0) f_type = type->as.optional.payload;
                    else if (plat_strcmp(field_init->field_name, "has_value") == 0) f_type = get_g_type_bool();
                } else {
                    if (plat_strcmp(field_init->field_name, "is_error") == 0) f_type = get_g_type_bool();
                    else if (plat_strcmp(field_init->field_name, "err") == 0) f_type = get_g_type_i32();
                    else if (plat_strcmp(field_init->field_name, "data") == 0) f_type = get_g_type_anytype();
                }

                emitAssignmentWithLifting(nested_name, NULL, field_init->value, f_type);
            }
            return;
        }

        DynamicArray<StructField>* fields = (type->kind == TYPE_TAGGED_UNION) ? type->as.tagged_union.payload_fields : type->as.struct_details.fields;
        bool is_tagged = isTaggedUnion(type);

        if (is_tagged) {
#ifdef DEBUG_TAGGED_UNION
            plat_printf_debug("[CODEGEN] emitInitializerAssignments (tagged union): base_name=%s\n", base_name);
#endif
            /* Emit tag assignment */
            const char* field_name = NULL;
            if (init->fields->length() > 0) {
                field_name = (*init->fields)[0]->field_name;
            } else {
                return;
            }
            writeIndent();
            writeString(base_name);
            writeString(".tag = ");
            Type* t_type = (type->kind == TYPE_TAGGED_UNION) ? type->as.tagged_union.tag_type : type->as.struct_details.tag_type;
            if (t_type && t_type->c_name) {
                writeString(t_type->c_name);
            } else if (t_type && t_type->as.enum_details.name) {
                writeString(unit_.getNameMangler().mangleTypeName(t_type->as.enum_details.name, t_type->owner_module ? t_type->owner_module->name : "unknown"));
            } else {
                writeString("/* enum */");
            }
            writeString("_");
            writeString(field_name);
            endStmt();

            /* New: handle nested struct initializer for the variant value */
            bool handled = false;
            if (init->fields->length() > 0) {
                ASTNamedInitializer* variant_init = (*init->fields)[0];
                
                /* Find the type of this variant */
                Type* variant_type = findTaggedUnionPayload(type, variant_init->field_name);

                if (variant_type && variant_type->kind == TYPE_VOID) {
#ifdef DEBUG_TAGGED_UNION
                    plat_printf_debug("[CODEGEN] Variant %s is VOID, skipping payload emission\n", variant_init->field_name);
#endif
                    handled = true; /* Nothing to emit for void payload */
                } else if (variant_init->value && variant_init->value->type == NODE_STRUCT_INITIALIZER) {
                    if (variant_type && (variant_type->kind == TYPE_STRUCT || variant_type->kind == TYPE_UNION)) {
                        const ASTStructInitializerNode* payload_init = variant_init->value->as.struct_initializer;
                        DynamicArray<StructField>* payload_fields = variant_type->as.struct_details.fields;

                        for (size_t j = 0; j < payload_fields->length(); ++j) {
                            const char* field_name_j = (*payload_fields)[j].name;
                            Type* field_type = (*payload_fields)[j].type;
                            if (field_type->kind == TYPE_VOID) continue;

                            /* Find this field in the nested initializer */
                            ASTNode* val = NULL;
                            for (size_t k = 0; k < payload_init->fields->length(); ++k) {
                                if (plat_strcmp((*payload_init->fields)[k]->field_name, field_name_j) == 0) {
                                    val = (*payload_init->fields)[k]->value;
                                    break;
                                }
                            }

                            if (val) {
                                char nested_name[512];
                                char* cur = nested_name;
                                size_t rem = sizeof(nested_name);
                                bool needs_parens = (base_name[0] == '*');
                                if (needs_parens) safe_append(cur, rem, "(");
                                safe_append(cur, rem, base_name);
                                if (needs_parens) safe_append(cur, rem, ")");
                                safe_append(cur, rem, ".data.");
                                safe_append(cur, rem, getSafeFieldName(variant_init->field_name));
                                safe_append(cur, rem, ".");
                                safe_append(cur, rem, getSafeFieldName(field_name_j));
                                emitAssignmentWithLifting(nested_name, NULL, val, field_type);
                            }
                        }
                        handled = true; /* skip the regular loop */
                    }
                }
            }

            if (!handled) {
                /* Fallback: original field-by-field loop for non-struct payloads (e.g., integers) */
                for (size_t i = 0; i < fields->length(); ++i) {
                    const char* field_name_j = (*fields)[i].name;
                    Type* field_type = (*fields)[i].type;
                    if (field_type->kind == TYPE_VOID) continue;

                    ASTNode* val = NULL;
                    for (size_t j = 0; j < init->fields->length(); ++j) {
                        if (plat_strcmp((*init->fields)[j]->field_name, field_name_j) == 0) {
                            val = (*init->fields)[j]->value;
                            break;
                        }
                    }

                    if (val) {
                        char nested_name[256];
                        char* cur = nested_name;
                        size_t rem = sizeof(nested_name);
                        bool needs_parens = (base_name[0] == '*');
                        if (needs_parens) safe_append(cur, rem, "(");
                        safe_append(cur, rem, base_name);
                        if (needs_parens) safe_append(cur, rem, ")");
                        if (is_tagged) safe_append(cur, rem, ".data");
                        safe_append(cur, rem, ".");
                        safe_append(cur, rem, field_name_j);
                        emitAssignmentWithLifting(nested_name, NULL, val, field_type);
                    }
                }
            }
        } else {
            for (size_t i = 0; i < fields->length(); ++i) {
                const char* field_name = (*fields)[i].name;
                Type* field_type = (*fields)[i].type;

                /* Skip void fields in C */
                if (field_type->kind == TYPE_VOID) continue;

                /* Find in initializer */
                ASTNode* val = NULL;
                for (size_t j = 0; j < init->fields->length(); ++j) {
                    if (plat_strcmp((*init->fields)[j]->field_name, field_name) == 0) {
                        val = (*init->fields)[j]->value;
                        break;
                    }
                }

                if (val) {
                    char nested_name[256];
                    char* cur = nested_name;
                    size_t rem = sizeof(nested_name);

                    bool needs_parens = false;
                    /* If base_name contains operators that have lower precedence than '.', wrap it.
                       Specifically if it starts with '*' (dereference). */
                    if (base_name[0] == '*') needs_parens = true;

                    if (needs_parens) safe_append(cur, rem, "(");
                    safe_append(cur, rem, base_name);
                    if (needs_parens) safe_append(cur, rem, ")");

                    if (is_tagged) {
                        safe_append(cur, rem, ".data");
                    }
                    safe_append(cur, rem, ".");
                    safe_append(cur, rem, field_name);

                    emitAssignmentWithLifting(nested_name, NULL, val, field_type);
                }
            }
        }
    } else if (type->kind == TYPE_ARRAY) {
        for (size_t i = 0; i < init->fields->length(); ++i) {
            ASTNode* val = (*init->fields)[i]->value;
            char idx_str[32];
            plat_i64_to_string(i, idx_str, sizeof(idx_str));

            char nested_name[256];
            char* cur = nested_name;
            size_t rem = sizeof(nested_name);
            safe_append(cur, rem, base_name);
            safe_append(cur, rem, "[");
            safe_append(cur, rem, idx_str);
            safe_append(cur, rem, "]");

            emitAssignmentWithLifting(nested_name, NULL, val, type->as.array.element_type);
        }
    }
}

void C89Emitter::emitAssignmentWithLifting(const char* target_var, const ASTNode* lvalue_node, const ASTNode* rvalue, Type* target_type) {
    if (!rvalue) return;

    if (!target_type && lvalue_node) {
        target_type = lvalue_node->resolved_type;
    }

    Type* source_type = rvalue->resolved_type;
    const char* effective_target = target_var;
    bool is_discard = false;

    if (lvalue_node && lvalue_node->type == NODE_IDENTIFIER && plat_strcmp(lvalue_node->as.identifier.name, "_") == 0) {
        is_discard = true;
    } else if (!effective_target && !lvalue_node) {
        is_discard = true;
    }

    if (!effective_target && lvalue_node) {
        if (lvalue_node->type == NODE_IDENTIFIER && lvalue_node->as.identifier.symbol) {
            effective_target = var_alloc_.allocate(lvalue_node->as.identifier.symbol);
        } else if (lvalue_node->type == NODE_VAR_DECL && lvalue_node->as.var_decl->symbol) {
            effective_target = var_alloc_.allocate(lvalue_node->as.var_decl->symbol);
        }
    }

    if (rvalue->type == NODE_UNDEFINED_LITERAL) {
        /* In C89, assigning undefined means doing nothing as a statement.
           If we are in an expression context (like initializers), we already handled it in emitLiteral. */
        return;
    }

    if (is_discard) {
        switch (rvalue->type) {
            case NODE_STRUCT_INITIALIZER:
                /* Special case: discarding a struct initializer means evaluating its components for side effects */
                if (rvalue->as.struct_initializer->fields) {
                    DynamicArray<ASTNamedInitializer*>* fields = rvalue->as.struct_initializer->fields;
                    for (size_t i = 0; i < fields->length(); ++i) {
                        emitAssignmentWithLifting(NULL, NULL, (*fields)[i]->value, NULL);
                    }
                }
                break;
            default:
                writeIndent();
                writeString("(void)(");
                emitExpression(rvalue);
                writeString(");\n");
                break;
        }
        return;
    }

    /* Coercions */
    if (target_type && target_type->kind == TYPE_ERROR_UNION && source_type && source_type->kind != TYPE_ERROR_UNION) {
        emitErrorUnionWrapping(target_var, lvalue_node, target_type, rvalue);
        return;
    }
    if (target_type && target_type->kind == TYPE_OPTIONAL && source_type && source_type->kind != TYPE_OPTIONAL) {
        emitOptionalWrapping(target_var, lvalue_node, target_type, rvalue);
        return;
    }

    if (target_type && isTaggedUnion(target_type) && rvalue->type == NODE_INTEGER_LITERAL && rvalue->as.integer_literal.original_name) {
        /* Assignment of a tag literal to a tagged union */
        writeIndent();
        if (effective_target) {
            writeString(effective_target);
        } else if (lvalue_node) {
            if (!isSimpleLValue(lvalue_node)) {
                writeString("(");
                emitExpression(lvalue_node);
                writeString(")");
            } else {
                emitExpression(lvalue_node);
            }
        }
        writeString(".tag = ");
        emitExpression(rvalue);
        endStmt();
        return;
    }

    /* Initializer Lifting */
    if (rvalue->type == NODE_STRUCT_INITIALIZER) {
        if (!rvalue->resolved_type && target_type) {
            ((ASTNode*)rvalue)->resolved_type = target_type;
        }
        if (effective_target) {
            emitInitializerAssignments(effective_target, rvalue);
        } else if (lvalue_node) {
            bool needs_temporary = !isSimpleLValue(lvalue_node);

            if (needs_temporary) {
                const char* lval_ptr = var_alloc_.generate("init_lval_tmp");
                writeIndent();
                writeString("{\n");
                indent();
                writeIndent();
                Type* ptr_type = createPointerType(arena_, target_type, false, false, &unit_.getTypeInterner());
                emitType(ptr_type, lval_ptr);
                writeString(" = &(");
                emitExpression(lvalue_node);
                writeString(");\n");

                char lval_buf[512];
                plat_strcpy(lval_buf, "(*");
                plat_strcat(lval_buf, lval_ptr);
                plat_strcat(lval_buf, ")");

                emitInitializerAssignments(lval_buf, rvalue);

                dedent();
                writeIndent();
                writeString("}\n");
            } else {
                char lval_buf[512];
                if (captureExpression(lvalue_node, lval_buf, sizeof(lval_buf))) {
                    emitInitializerAssignments(lval_buf, rvalue);
                } else {
                    /* Fallback if capture failed or truncated */
                    writeIndent();
                    emitExpression(lvalue_node);
                    writeString(" = ");
                    emitExpression(rvalue);
                    endStmt();
                }
            }
            return;
        } else {
            if (allPathsExit(rvalue)) {
                emitStatement(rvalue);
                return;
            }
            writeIndent();
            if (lvalue_node) {
                emitExpression(lvalue_node);
                writeString(" = ");
            }
            emitExpression(rvalue);
            endStmt();
        }
    } else {
        if (allPathsExit(rvalue)) {
            emitStatement(rvalue);
            return;
        }

        if (effective_target || lvalue_node) {
            writeIndent();
            if (effective_target) {
                writeString(effective_target);
            } else if (lvalue_node) {
                emitExpression(lvalue_node);
            }
            writeString(" = ");
            emitExpression(rvalue);
            endStmt();
        } else {
            writeExprStmt(rvalue);
        }
    }
}

void C89Emitter::emitLocalVarDecl(const ASTNode* node, bool emit_assignment) {
    if (!node || node->type != NODE_VAR_DECL) return;
    const ASTVarDeclNode* decl = node->as.var_decl;

    /* Skip type and module declarations in local scope */
    if (decl->initializer) {
        if (decl->initializer->type == NODE_IMPORT_STMT ||
            (decl->initializer->resolved_type && decl->initializer->resolved_type->kind == TYPE_MODULE)) {
            return;
        }
        if (decl->is_const && isTypeExpression(decl->initializer, unit_.getSymbolTable())) {
            return;
        }
    }

    if (debug_trace_) {
        plat_printf_debug("[CODEGEN] emitLocalVarDecl: name=%s has_symbol=%d\n",
                         decl->name ? decl->name : "NULL",
                         decl->symbol ? 1 : 0);
    }

    const char* c_name = NULL;
    if (decl->symbol) {
        c_name = var_alloc_.allocate(decl->symbol);
    } else if (decl->name && (plat_strncmp(decl->name, "__tmp_", 6) == 0 ||
                              plat_strncmp(decl->name, "__return_", 9) == 0)) {
        c_name = decl->name;
        if (debug_trace_) {
            plat_printf_debug("[CODEGEN] WARNING: Temp var %s has no symbol!\n", c_name);
        }
    } else {
        if (debug_trace_) {
            plat_printf_debug("[CODEGEN] ERROR: Skipping var decl with no symbol and non-temp name: %s\n",
                             decl->name ? decl->name : "NULL");
        }
        return;
    }

    if (c_name) {
        bool already_emitted = false;
        for (size_t i = 0; i < emitted_decls_.length(); ++i) {
            if (plat_strcmp(emitted_decls_[i], c_name) == 0) {
                already_emitted = true;
                break;
            }
        }
        if (!already_emitted) {
            emitted_decls_.append(c_name);
        }
    }

    if (!emit_assignment) {
        writeIndent();

        bool is_const_in_c = false;
        if (decl->is_const) {
            /* Only emit 'const' if the initializer is a C89 constant expression */
            if (decl->initializer && isConstantInitializer(decl->initializer)) {
                is_const_in_c = true;
            }
        }

        if (is_const_in_c) {
            writeKeyword(KW_CONST);
        }

        emitDeclarator(node->resolved_type, c_name);

        /* Special case: zero-initialization for catch temporaries and other lifted vars */
        if (decl->initializer && decl->initializer->type == NODE_STRUCT_INITIALIZER &&
            (!decl->initializer->as.struct_initializer->fields || decl->initializer->as.struct_initializer->fields->length() == 0)) {
            writeString(" = {0}");
        } else if (decl->initializer && decl->initializer->type != NODE_UNDEFINED_LITERAL && isConstantInitializer(decl->initializer)) {
            /* C89: cannot initialize Optional or Error Union with a primitive constant */
            Type* target_type = node->resolved_type;
            Type* source_type = decl->initializer->resolved_type;

            bool needs_wrapping = false;
            if (target_type && (target_type->kind == TYPE_OPTIONAL || target_type->kind == TYPE_ERROR_UNION)) {
                if (source_type && source_type->kind != target_type->kind) {
                    needs_wrapping = true;
                }
            }

            if (needs_wrapping) {
                /* For locals, we prefer splitting declaration and wrapping assignment.
                   But here emit_assignment is false, meaning we are ONLY emitting the declaration.
                   We emit the declaration with {0} and let the second pass (emit_assignment=true)
                   handle the wrapping via emitAssignmentWithLifting. */
                writeString(" = {0}");
            } else {
                /* Support constant initializers in C89 for globals/statics, or simple locals if optimized */
                writeString(" = ");
                emitExpression(decl->initializer);
            }
        } else if (decl->initializer && decl->initializer->type == NODE_UNDEFINED_LITERAL) {
            /* Zig 'undefined' means no initialization in C */
        }

        endStmt();
        if (debug_trace_) {
            plat_printf_debug("[CODEGEN] Emitted decl: %s\n", c_name);
        }
    } else {
        if (decl->initializer && decl->initializer->type != NODE_UNDEFINED_LITERAL) {
            /* Skip if already handled by = {0} in declaration */
            if (decl->initializer->type == NODE_STRUCT_INITIALIZER &&
                (!decl->initializer->as.struct_initializer->fields || decl->initializer->as.struct_initializer->fields->length() == 0)) {
                return;
            }

            /* For constants, we already emitted an '=' in the declaration if it wasn't a complex type.
               If it WAS a complex type, we used = {0} and now we MUST emit the full assignment. */
            if (isConstantInitializer(decl->initializer)) {
                Type* target_type = node->resolved_type;
                Type* source_type = decl->initializer->resolved_type;
                bool was_wrapped = false;
                if (target_type && (target_type->kind == TYPE_OPTIONAL || target_type->kind == TYPE_ERROR_UNION || isTaggedUnion(target_type))) {
                    if (source_type && source_type->kind != target_type->kind) {
                        was_wrapped = true;
                    }
                    /* For tagged unions, we always want the decomposition for better C89 compliance and clarity,
                       even if initialized with a constant. */
                    if (isTaggedUnion(target_type)) was_wrapped = true;
                }
                if (!was_wrapped) return;
            }

            emitAssignmentWithLifting(c_name, node, decl->initializer);
            if (debug_trace_) {
                plat_printf_debug("[CODEGEN] Emitted assignment for: %s\n", c_name);
            }
        }
    }
}

void C89Emitter::emitFnProto(const ASTFnDeclNode* node, bool is_public) {
    if (!node) return;

    writeIndent();

    /* Special handling for the main entry point */
    if (plat_strcmp(node->name, "main") == 0 && (node->is_pub || is_public)) {
        writeString("int main(");
        if (!node->params || node->params->length() == 0) {
            writeString(KW_VOID);
        } else {
            for (size_t i = 0; i < node->params->length(); ++i) {
                ASTNode* param_node = (*node->params)[i];
                emitDeclarator(param_node->as.param_decl.type->resolved_type, NULL);
                if (i < node->params->length() - 1) {
                    writeString(", ");
                }
            }
        }
        writeString(");");
    } else if (plat_strcmp(node->name, "__bootstrap_print") == 0 ||
               plat_strcmp(node->name, "__bootstrap_print_int") == 0 ||
               plat_strcmp(node->name, "__bootstrap_panic") == 0) {
        /* Skip internal runtime prototypes in module headers to avoid conflicts with zig_runtime.h */
    } else {
        if (node->is_extern) {
            writeKeyword(KW_EXTERN);
        } else if (!is_public && !node->is_pub && !node->is_export) {
            writeKeyword(KW_STATIC);
        }

        Type* ret_type = node->return_type ? node->return_type->resolved_type : get_g_type_void();
        const char* mangled_name = NULL;
        Symbol* sym = unit_.getSymbolTable(module_name_).lookup(node->name);
        if (sym && (sym->flags & SYMBOL_FLAG_EXTERN)) {
            mangled_name = sym->name;
        } else if (sym && sym->mangled_name) {
            mangled_name = sym->mangled_name;
        } else if (node->is_extern) {
            mangled_name = node->name;
        } else {
            mangled_name = getC89GlobalName(node->name);
        }

        if (sym && sym->c_prototype_type) {
            Type* abi_type = sym->c_prototype_type;
            emitTypePrefix(abi_type->as.function.return_type);
            writeString(" ");
            writeString(mangled_name);
            writeString("(");
            DynamicArray<Type*>* params = abi_type->as.function.params;
            if (!params || params->length() == 0) {
                writeString(KW_VOID);
            } else {
                for (size_t i = 0; i < params->length(); ++i) {
                    emitDeclarator((*params)[i], NULL);
                    if (i < params->length() - 1) writeString(", ");
                }
            }
        } else {
            /* For prototype, we don't necessarily want to allocate parameter names in var_alloc_, */
            /* so we don't pass 'node' as params_node if we want to avoid side effects. */
            /* But we want to emit parameter types correctly. */
            emitTypePrefix(ret_type);
            writeString(" ");
            writeString(mangled_name);
            writeString("(");
            if (!node->params || node->params->length() == 0) {
                writeString(KW_VOID);
            } else {
                for (size_t i = 0; i < node->params->length(); ++i) {
                    ASTNode* param_node = (*node->params)[i];
                    emitDeclarator(param_node->as.param_decl.type->resolved_type, NULL);
                    if (i < node->params->length() - 1) {
                        writeString(", ");
                    }
                }
            }
        }
        writeString(")");
        emitTypeSuffix(ret_type);
        writeString(";");
    }
}

void C89Emitter::emitFunctionPrototype(Symbol* sym) {
    if (!sym || !sym->details) return;

    ASTFnDeclNode* fn = (ASTFnDeclNode*)sym->details;
    Type* ret_type = fn->return_type ? fn->return_type->resolved_type : get_g_type_void();
    const char* mangled_name = sym->mangled_name;

    writeIndent();
    if (!fn->is_pub && !fn->is_extern && !fn->is_export) {
        writeKeyword(KW_STATIC);
    }

    if (sym->c_prototype_type) {
        Type* abi_type = sym->c_prototype_type;
        emitTypePrefix(abi_type->as.function.return_type);
        writeString(" ");
        writeString(mangled_name);
        writeString("(");
        DynamicArray<Type*>* params = abi_type->as.function.params;
        if (!params || params->length() == 0) {
            writeString(KW_VOID);
        } else {
            for (size_t i = 0; i < params->length(); ++i) {
                if (i > 0) writeString(", ");
                emitDeclarator((*params)[i], NULL);
            }
        }
        writeString(")");
        emitTypeSuffix(abi_type->as.function.return_type);
    } else {
        emitTypePrefix(ret_type);
        writeString(" ");
        writeString(mangled_name);
        writeString("(");
        if (!fn->params || fn->params->length() == 0) {
            writeString(KW_VOID);
        } else {
            for (size_t i = 0; i < fn->params->length(); ++i) {
                if (i > 0) writeString(", ");
                ASTNode* param_node = (*fn->params)[i];
                emitType(param_node->as.param_decl.type->resolved_type);
            }
        }
        writeString(")");
        emitTypeSuffix(ret_type);
    }
    endStmt();
}

void C89Emitter::emitSymbolMap() {
    size_t global_count = 0;
    for (size_t i = 0; i < global_names_.length(); ++i) {
        if (plat_strncmp(global_names_[i].c89_name, "z", 1) == 0 && 
            global_names_[i].c89_name[1] >= 'A' && global_names_[i].c89_name[1] <= 'V' &&
            global_names_[i].c89_name[2] == '_') {
            global_count++;
        }
    }
    if (global_count == 0) return;

    writeString("/*\n * Z98 Symbol Map:\n");
    for (size_t i = 0; i < global_names_.length(); ++i) {
        const GlobalNameEntry& entry = global_names_[i];
        if (!(plat_strncmp(entry.c89_name, "z", 1) == 0 && 
              entry.c89_name[1] >= 'A' && entry.c89_name[1] <= 'V' &&
              entry.c89_name[2] == '_')) {
            continue;
        }

        writeString(" * ");
        writeString(entry.c89_name);
        // Padding for alignment
        size_t len = plat_strlen(entry.c89_name);
        for (size_t j = len; j < 24; ++j) writeString(" ");
        writeString(" -> ");
        writeString(entry.location ? entry.location : "unknown");
        writeString(":");
        writeString(entry.zig_name);
        writeString(" (");
        writeString(entry.kind ? entry.kind : "unknown");
        writeString(")\n");
    }
    writeString(" */\n\n");
}

void C89Emitter::emitFnDecl(const ASTFnDeclNode* node) {
    if (!node) return;

    SymbolTable& table = unit_.getSymbolTable(module_name_);
    table.enterScope();

    beginFunction();
    emitted_decls_.clear();
    current_fn_name_ = node->name;
    is_main_function_ = false;

    writeIndent();

    Type* ret_type = node->return_type ? node->return_type->resolved_type : get_g_type_void();
    Symbol* sym = unit_.getSymbolTable(module_name_).lookup(node->name);
    if (sym && sym->c_prototype_type) {
        current_fn_ret_type_ = sym->c_prototype_type->as.function.return_type;
    } else {
        current_fn_ret_type_ = ret_type;
    }
    defer_stack_.clear();

    /* Special handling for the main entry point */
    if (plat_strcmp(node->name, "main") == 0 && node->is_pub) {
        writeString("int main(");
        if (!node->params || node->params->length() == 0) {
            writeString(KW_VOID);
        } else {
            for (size_t i = 0; i < node->params->length(); ++i) {
                ASTNode* param_node = (*node->params)[i];
                ASTParamDeclNode& param = param_node->as.param_decl;
                const char* param_name = param.symbol ? var_alloc_.allocate(param.symbol) : param.name;
                emitDeclarator(param.type->resolved_type, param_name);
                if (i < node->params->length() - 1) {
                    writeString(", ");
                }
            }
        }
        writeString(")");
        is_main_function_ = true;
    } else if (plat_strcmp(node->name, "__bootstrap_print") == 0 ||
               plat_strcmp(node->name, "__bootstrap_print_int") == 0 ||
               plat_strcmp(node->name, "__bootstrap_panic") == 0) {
        /* Use standard prototypes from zig_runtime.h for internal helpers */
        const char* mangled_name = node->name;
        emitDeclarator(ret_type, mangled_name, node);
    } else {
        if (node->is_extern) {
            writeKeyword(KW_EXTERN);
        } else if (!node->is_pub && !node->is_export) {
            writeKeyword(KW_STATIC);
        }

        const char* mangled_name = NULL;
        Symbol* sym = unit_.getSymbolTable(module_name_).lookup(node->name);
        if (sym && (sym->flags & SYMBOL_FLAG_EXTERN)) {
            mangled_name = sym->name;
        } else if (sym && sym->mangled_name) {
            mangled_name = sym->mangled_name;
        } else if (node->is_extern) {
            mangled_name = node->name;
        } else {
            mangled_name = getC89GlobalName(node->name);
        }

        if (sym && sym->c_prototype_type) {
            Type* abi_type = sym->c_prototype_type;
            emitTypePrefix(abi_type->as.function.return_type);
            writeString(" ");
            writeString(mangled_name);
            writeString("(");
            DynamicArray<Type*>* params = abi_type->as.function.params;
            if (!params || params->length() == 0) {
                writeString(KW_VOID);
            } else {
                for (size_t i = 0; i < params->length(); ++i) {
                    ASTNode* param_node = (*node->params)[i];
                    ASTParamDeclNode& param = param_node->as.param_decl;
                    /* Use mangled local name for parameters even in ABI mode */
                    const char* p_name = param.symbol ? var_alloc_.allocate(param.symbol) : param.name;
                    emitDeclarator((*params)[i], p_name);
                    if (i < params->length() - 1) writeString(", ");
                }
            }
            writeString(")");
            emitTypeSuffix(abi_type->as.function.return_type);
        } else {
            emitDeclarator(ret_type, mangled_name, node);
        }
    }

    if (node->body) {
        /* Create error flag if needed */
        if (current_fn_ret_type_ && current_fn_ret_type_->kind == TYPE_ERROR_UNION && scanForErrDefer(node->body)) {
            current_err_flag_ = var_alloc_.generate("err_occurred");
        } else {
            current_err_flag_ = NULL;
        }

        writeString(" ");
        emitBlock(&node->body->as.block_stmt);
        writeString("\n\n");
    } else {
        writeString(";\n\n");
    }

    validateEmission();
    table.exitScope();
}

void C89Emitter::emitBlock(const ASTBlockStmtNode* node, int label_id) {
    if (!node) return;

    writeString("{\n");
    {
        IndentScope scope_indent(*this);
        DeferScopeGuard defer_guard(*this, label_id);
        DeferScope* scope = defer_stack_.back();

        /* Pass 1: Local declarations */
        if (label_id == -1 && defer_stack_.length() == 1 && current_err_flag_) {
            writeIndent();
            writeKeyword(KW_INT);
            writeString(current_err_flag_);
            writeString(" = 0");
            endStmt();
        }

        for (size_t i = 0; i < node->statements->length(); ++i) {
            ASTNode* stmt = (*node->statements)[i];
            if (stmt->type == NODE_VAR_DECL) {
                emitLocalVarDecl(stmt, false);
            }
        }

        /* Pass 2: Statements */
        bool exits = false;
        for (size_t i = 0; i < node->statements->length(); ++i) {
            ASTNode* stmt = (*node->statements)[i];
            if (stmt->type == NODE_VAR_DECL) {
                emitLocalVarDecl(stmt, true);
                if (allPathsExit(stmt)) {
                    exits = true;
                    break;
                }
            } else if (stmt->type == NODE_DEFER_STMT) {
                if (scope->defers.length() + scope->err_defers.length() >= 32) {
                    error_handler_.report(ERR_TOO_MANY_DEFERS, stmt->loc, ErrorHandler::getMessage(ERR_TOO_MANY_DEFERS), "Max 32 defers per scope");
                }
                scope->defers.append((ASTDeferStmtNode*)&stmt->as.defer_stmt);
            } else if (stmt->type == NODE_ERRDEFER_STMT) {
                if (scope->defers.length() + scope->err_defers.length() >= 32) {
                    error_handler_.report(ERR_TOO_MANY_DEFERS, stmt->loc, ErrorHandler::getMessage(ERR_TOO_MANY_DEFERS), "Max 32 defers per scope");
                }
                scope->err_defers.append((ASTDeferStmtNode*)&stmt->as.errdefer_stmt);
            } else {
                emitStatement(stmt);
                if (allPathsExit(stmt)) {
                    exits = true;
                    /* Once we hit a path that always exits, any subsequent statements in this block are unreachable. */
                    break;
                }
            }
        }

        /* Emit defers for this block in reverse order, only if not already handled by a terminator */
        if (!exits) {
            for (int i = (int)scope->defers.length() - 1; i >= 0; --i) {
                emitStatement(scope->defers[i]->statement);
            }

            /* Task: Fix #2 - Implicit return for Error!void and main */
            if (label_id == -1 && defer_stack_.length() == 1) {
                if (current_fn_ret_type_ && current_fn_ret_type_->kind == TYPE_ERROR_UNION &&
                    current_fn_ret_type_->as.error_union.payload->kind == TYPE_VOID) {
                    writeIndent();
                    if (is_main_function_) {
                        writeKeyword(KW_RETURN);
                        writeString("0");
                        endStmt();
                    } else {
                        writeBlockOpen();
                        {
                            const char* mangled = getMangledTypeName(current_fn_ret_type_);
                            writeIndent();
                            writeString(mangled);
                            writeString(" __implicit_ret = {0}");
                            endStmt();
                            writeIndent();
                            writeKeyword(KW_RETURN);
                            writeString("__implicit_ret");
                            endStmt();
                        }
                        writeBlockClose();
                    }
                } else if (is_main_function_) {
                    writeIndent();
                    writeKeyword(KW_RETURN);
                    writeString("0");
                    endStmt();
                }
            }
        }
    }
    writeIndent();
    writeString("}");
}

void C89Emitter::emitBlockWithAssignment(const ASTBlockStmtNode* node, const char* target_var, int label_id, Type* target_type) {
    if (!node) return;

    writeString("{\n");
    {
        IndentScope scope_indent(*this);
        DeferScopeGuard defer_guard(*this, label_id);
        DeferScope* scope = defer_stack_.back();

        /* Pass 1: Local declarations */
        if (label_id == -1 && defer_stack_.length() == 1 && current_err_flag_) {
            writeIndent();
            writeKeyword(KW_INT);
            writeString(current_err_flag_);
            writeString(" = 0");
            endStmt();
        }

        for (size_t i = 0; i < node->statements->length(); ++i) {
            ASTNode* stmt = (*node->statements)[i];
            if (stmt->type == NODE_VAR_DECL) {
                emitLocalVarDecl(stmt, false);
            }
        }

        /* Pass 2: Statements */
        bool exits = false;
        for (size_t i = 0; i < node->statements->length(); ++i) {
            ASTNode* stmt = (*node->statements)[i];
            if (stmt->type == NODE_VAR_DECL) {
                emitLocalVarDecl(stmt, true);
                if (allPathsExit(stmt)) {
                    exits = true;
                    break;
                }
            } else if (stmt->type == NODE_DEFER_STMT) {
                if (scope->defers.length() + scope->err_defers.length() >= 32) {
                    error_handler_.report(ERR_TOO_MANY_DEFERS, stmt->loc, ErrorHandler::getMessage(ERR_TOO_MANY_DEFERS), "Max 32 defers per scope");
                }
                scope->defers.append((ASTDeferStmtNode*)&stmt->as.defer_stmt);
            } else if (stmt->type == NODE_ERRDEFER_STMT) {
                if (scope->defers.length() + scope->err_defers.length() >= 32) {
                    error_handler_.report(ERR_TOO_MANY_DEFERS, stmt->loc, ErrorHandler::getMessage(ERR_TOO_MANY_DEFERS), "Max 32 defers per scope");
                }
                scope->err_defers.append((ASTDeferStmtNode*)&stmt->as.errdefer_stmt);
            } else {
                /* Check if it's the last expression in the block */
                if (i == node->statements->length() - 1 && target_var &&
                    stmt->type != NODE_EXPRESSION_STMT &&
                    stmt->type != NODE_IF_STMT && stmt->type != NODE_WHILE_STMT &&
                    stmt->type != NODE_FOR_STMT && stmt->type != NODE_RETURN_STMT &&
                    stmt->type != NODE_BREAK_STMT && stmt->type != NODE_CONTINUE_STMT &&
                    stmt->type != NODE_UNREACHABLE) {

                    emitAssignmentWithLifting(target_var, NULL, stmt, target_type);
                } else {
                    emitStatement(stmt);
                }

                if (allPathsExit(stmt)) {
                    exits = true;
                    break;
                }
            }
        }

        /* Emit defers for this block in reverse order, only if not already handled by a terminator */
        if (!exits) {
            for (int i = (int)scope->defers.length() - 1; i >= 0; --i) {
                emitStatement(scope->defers[i]->statement);
            }
        }
    }
    writeIndent();
    writeString("}");
}

void C89Emitter::emitStatement(const ASTNode* node) {
    if (!node) return;
    current_loc_ = node->loc;

    switch (node->type) {
        case NODE_BLOCK_STMT:
            writeIndent();
            emitBlock(&node->as.block_stmt);
            writeLine();
            break;
        case NODE_IF_STMT:
            emitIf(node->as.if_stmt);
            break;
        case NODE_WHILE_STMT:
            emitWhile(node->as.while_stmt);
            break;
        case NODE_SWITCH_STMT:
            emitSwitch(node->as.switch_stmt);
            break;
        case NODE_FOR_STMT:
            emitFor(node->as.for_stmt);
            break;
        case NODE_BREAK_STMT:
            emitBreak(&node->as.break_stmt);
            break;
        case NODE_CONTINUE_STMT:
            emitContinue(&node->as.continue_stmt);
            break;
        case NODE_RETURN_STMT:
            emitReturn(&node->as.return_stmt);
            break;
        case NODE_UNREACHABLE:
            writeIndent();
            emitExpression(node);
            endStmt();
            break;
        case NODE_DEFER_STMT:
        case NODE_ERRDEFER_STMT:
            /* Should never be emitted directly; they are handled in block collection */
            error_handler_.report(ERR_INTERNAL_ERROR, node->loc,
                "Defer/errdefer statement emitted outside block context");
            break;
        case NODE_EXPRESSION_STMT: {
            emitStatement(node->as.expression_stmt.expression);
            break;
        }
        case NODE_ASSIGNMENT: {
            emitAssignmentWithLifting(NULL, node->as.assignment->lvalue, node->as.assignment->rvalue);
            break;
        }
        case NODE_COMPOUND_ASSIGNMENT: {
            /* Compound assignment as a statement */
            writeExprStmt(node);
            break;
        }
        case NODE_FUNCTION_CALL: {
            /* Check if it's std.debug.print */
            bool is_print = false;
            const ASTNode* callee = node->as.function_call->callee;
            if (callee->type == NODE_MEMBER_ACCESS && plat_strcmp(callee->as.member_access->field_name, "print") == 0) {
                is_print = true;
            }

            if (is_print) {
                emitPrintCall(node->as.function_call);
            } else {
                writeExprStmt(node);
            }
            break;
        }
        /* Handle remaining expression nodes as statements */
        case NODE_BINARY_OP:
        case NODE_UNARY_OP:
        case NODE_INTEGER_LITERAL:
        case NODE_FLOAT_LITERAL:
        case NODE_STRING_LITERAL:
        case NODE_CHAR_LITERAL:
        case NODE_BOOL_LITERAL:
        case NODE_NULL_LITERAL:
        case NODE_ERROR_LITERAL:
        case NODE_IDENTIFIER:
        case NODE_STRUCT_INITIALIZER:
        case NODE_ARRAY_ACCESS:
        case NODE_MEMBER_ACCESS:
        case NODE_ARRAY_SLICE:
        case NODE_IF_EXPR:
        case NODE_SWITCH_EXPR:
        case NODE_TRY_EXPR:
        case NODE_CATCH_EXPR:
        case NODE_ORELSE_EXPR:
        case NODE_OFFSET_OF:
        case NODE_PTR_CAST:
        case NODE_INT_CAST:
        case NODE_FLOAT_CAST:
        case NODE_INT_TO_FLOAT:
        case NODE_RANGE:
        case NODE_PAREN_EXPR:
        case NODE_ASYNC_EXPR:
        case NODE_AWAIT_EXPR:
        case NODE_TUPLE_LITERAL:
            writeExprStmt(node);
            break;
        case NODE_EMPTY_STMT:
            writeIndent();
            endStmt();
            break;
        default:
            writeIndent();
            writeString("/* Unimplemented statement type ");
            char num[16];
            plat_i64_to_string(node->type, num, sizeof(num));
            writeString(num);
            writeString(" */\n");
            break;
    }
}

void C89Emitter::emitIf(const ASTIfStmtNode* node) {
    if (!node) return;

    Type* cond_type = node->condition->resolved_type;
    bool is_optional = (cond_type && cond_type->kind == TYPE_OPTIONAL);

    if (is_optional) {
        writeIndent();
        writeBlockOpen();

        const char* cond_tmp = makeTempVarForType(cond_type, "opt_tmp", true);
        writeIndent();
        writeString(cond_tmp);
        writeString(" = ");
        emitExpression(node->condition);
        endStmt();

        writeIndent();
        writeKeyword(KW_IF);
        writeString("(");
        writeString(cond_tmp);
        writeString(".has_value) ");
        writeBlockOpen();

        if (node->capture_name && node->capture_sym && node->capture_sym->symbol_type->kind != TYPE_VOID) {
            const char* c_name = var_alloc_.allocate(node->capture_sym);
            writeIndent();
            writeDecl(node->capture_sym->symbol_type, c_name);
            writeIndent();
            writeString(c_name);
            writeString(" = ");
            writeString(cond_tmp);
            writeString(".value");
            endStmt();
        }
        if (node->then_block->type == NODE_BLOCK_STMT) {
            emitBlock(&node->then_block->as.block_stmt);
        } else {
            emitStatement(node->then_block);
        }

        dedent();
        writeIndent();
        writeString("}");

        if (node->else_block) {
            writeString(" ");
            writeKeyword(KW_ELSE);
            writeBlockOpen();

            if (node->else_block->type == NODE_IF_STMT) {
                emitIf(node->else_block->as.if_stmt);
            } else if (node->else_block->type == NODE_BLOCK_STMT) {
                emitBlock(&node->else_block->as.block_stmt);
            } else {
                emitStatement(node->else_block);
            }

            writeBlockClose();
        } else {
            writeLine();
        }

        writeBlockClose();
    } else {
        writeIndent();
        writeKeyword(KW_IF);
        writeString("(");
        emitExpression(node->condition);
        writeString(") ");

        if (node->then_block->type == NODE_BLOCK_STMT) {
            emitBlock(&node->then_block->as.block_stmt);
        } else {
            emitStatement(node->then_block);
        }

        if (node->else_block) {
            writeString(" ");
            writeKeyword(KW_ELSE);
            if (node->else_block->type == NODE_IF_STMT) {
                emitIf(node->else_block->as.if_stmt);
            } else if (node->else_block->type == NODE_BLOCK_STMT) {
                emitBlock(&node->else_block->as.block_stmt);
            } else {
                emitStatement(node->else_block);
            }
        }
        writeLine();
    }
}

bool C89Emitter::scanForErrDefer(const ASTNode* node) const {
    if (!node) return false;
    if (node->type == NODE_ERRDEFER_STMT) return true;

    struct ScanVisitor : ChildVisitor {
        bool found;
        const C89Emitter* emitter;
        ScanVisitor(const C89Emitter* e) : found(false), emitter(e) {}
        void visitChild(ASTNode** child_slot) {
            if (found) return;
            if (emitter->scanForErrDefer(*child_slot)) {
                found = true;
            }
        }
    };

    ScanVisitor visitor(this);
    forEachChild((ASTNode*)node, visitor);
    return visitor.found;
}

bool C89Emitter::evaluateSimpleConstant(const ASTNode* node, i64* out_value) const {
    if (!node) return false;
    if (node->type == NODE_INTEGER_LITERAL) {
        *out_value = (i64)node->as.integer_literal.value;
        return true;
    }
    if (node->type == NODE_CHAR_LITERAL) {
        *out_value = (i64)node->as.char_literal.value;
        return true;
    }
    if (node->type == NODE_BOOL_LITERAL) {
        *out_value = node->as.bool_literal.value ? 1 : 0;
        return true;
    }
    if (node->type == NODE_UNARY_OP && node->as.unary_op.op == TOKEN_MINUS) {
        i64 val;
        if (evaluateSimpleConstant(node->as.unary_op.operand, &val)) {
            *out_value = -val;
            return true;
        }
    }
    if (node->type == NODE_PAREN_EXPR) {
        return evaluateSimpleConstant(node->as.paren_expr.expr, out_value);
    }
    if (node->type == NODE_IDENTIFIER) {
        SymbolTable& table = unit_.getSymbolTable(module_name_);
        Symbol* sym = table.lookup(node->as.identifier.name);
        if (sym && sym->kind == SYMBOL_VARIABLE && sym->details) {
            ASTVarDeclNode* decl = (ASTVarDeclNode*)sym->details;
            if (decl->is_const && decl->initializer) {
                return evaluateSimpleConstant(decl->initializer, out_value);
            }
        }
    }
    return false;
}

void C89Emitter::emitPrintCall(const ASTFunctionCallNode* node) {
    if (!node->args || node->args->length() != 2) return;

    ASTNode* fmt_node = (*node->args)[0];
    ASTNode* tuple_node = (*node->args)[1];

    if (fmt_node->type != NODE_STRING_LITERAL) {
        /* Fallback: just emit as a normal call if we can't lower it */
        writeIndent();
        writeString("/* warning: could not lower std.debug.print (not a string literal) */\n");
        return;
    }

    const char* fmt = fmt_node->as.string_literal.value;
    DynamicArray<ASTNode*>* elements = (tuple_node->type == NODE_TUPLE_LITERAL) ?
                                      tuple_node->as.tuple_literal->elements : NULL;

    size_t element_idx = 0;
    const char* start = fmt;
    const char* p = fmt;

    while (*p) {
        if (*p == '{' && *(p+1) == '}') {
            /* Print what we have so far */
            if (p > start) {
                writeIndent();
                writeString("__bootstrap_print(\"");
                const char* s = start;
                while (s < p) {
                    emitEscapedByte((unsigned char)*s, false);
                    s++;
                }
                writeString("\");\n");
            }

            /* Print the element */
            if (elements && element_idx < elements->length()) {
                writeIndent();
                writeString("__bootstrap_print_int(");
                emitExpression((*elements)[element_idx]);
                writeString(");\n");
                element_idx++;
            } else {
                writeIndent();
                writeString("__bootstrap_print(\"{}\");\n");
            }

            p += 2;
            start = p;
        } else {
            p++;
        }
    }

    /* Print remaining part */
    if (*start) {
        writeIndent();
        writeString("__bootstrap_print(\"");
        const char* s = start;
        while (*s) {
            emitEscapedByte((unsigned char)*s, false);
            s++;
        }
        writeString("\");\n");
    }
}

void C89Emitter::emitSwitch(const ASTSwitchStmtNode* node) {
    if (!node) return;
    writeString("/* DEBUG: emitSwitch start */\n");

    Type* cond_type = node->expression->resolved_type;
    bool is_tagged_union = isTaggedUnion(cond_type);
    const char* switch_tmp = NULL;

    if (is_tagged_union) {
        writeIndent();
        writeBlockOpen();

        switch_tmp = makeTempVarForType(cond_type, "switch_tmp", true);
        writeIndent();
        writeString(switch_tmp);
        writeString(" = ");
        emitExpression(node->expression);
        endStmt();

        writeIndent();
        writeKeyword(KW_SWITCH);
        writeString("(");
        writeString(switch_tmp);
        writeString(".tag) ");
        writeBlockOpen();

    } else {
        writeIndent();
        writeKeyword(KW_SWITCH);
        writeString("(");
        emitExpression(node->expression);
        writeString(") ");
        writeBlockOpen();
    }

    {
        for (size_t i = 0; i < node->prongs->length(); ++i) {
            const ASTSwitchStmtProngNode* prong = (*node->prongs)[i];
            if (prong->is_else) {
                writeIndent();
                writeString("default:\n");
            } else {
                for (size_t j = 0; j < prong->items->length(); ++j) {
                    const ASTNode* item = (*prong->items)[j];
                    if (item->type == NODE_RANGE) {
                        i64 start, end;
                        if (evaluateSimpleConstant(item->as.range->start, &start) &&
                            evaluateSimpleConstant(item->as.range->end, &end)) {
                            i64 effective_end = item->as.range->is_inclusive ? end : end - 1;
                            for (i64 k = start; k <= effective_end; ++k) {
                                writeIndent();
                                writeKeyword(KW_CASE);
                                char buf[32];
                                plat_i64_to_string(k, buf, sizeof(buf));
                                writeString(buf);
                                writeString(":\n");
                            }
                        } else {
                            error_handler_.report(ERR_UNSUPPORTED_FEATURE, item->loc, "Non-constant range in switch is not yet supported");
                            return;
                        }
                    } else {
                        writeIndent();
                        writeKeyword(KW_CASE);
                        emitExpression(item);
                        writeString(":\n");
                    }
                }
            }
            {
                IndentScope prong_indent(*this);

                bool has_non_void_capture = (is_tagged_union && prong->capture_name && prong->capture_sym &&
                                            prong->capture_sym->symbol_type->kind != TYPE_VOID);

                if (has_non_void_capture) {
                    ASTNode* item_expr = (*prong->items)[0];
                    Type* capture_type = prong->capture_sym->symbol_type;
                    plat_printf_debug("[emitSwitch] Non-void capture for tag '%s', capture type = %d\n",
                                      item_expr->as.integer_literal.original_name, capture_type->kind);

                    writeIndent();
                    writeBlockOpen();

                    writeIndent();
                    writeString("/* DEBUG: capture ");
                    writeString(prong->capture_name);
                    writeString(" */\n");
                    const char* c_name = var_alloc_.allocate(prong->capture_sym);
                    writeIndent();
                    writeDecl(capture_type, c_name);

                    /* Field name is preserved in original_name of the case item literal */
                    char rvalue_buf[512];
                    char* r_cur = rvalue_buf;
                    size_t r_rem = sizeof(rvalue_buf);
                    safe_append(r_cur, r_rem, switch_tmp);
                    safe_append(r_cur, r_rem, ".data.");
                    safe_append(r_cur, r_rem, getSafeFieldName(item_expr->as.integer_literal.original_name));

                    writeIndent();
                    if (capture_type->kind == TYPE_STRUCT || capture_type->kind == TYPE_UNION) {
                        writeString("memcpy(&");
                        writeString(c_name);
                        writeString(", &");
                        writeString(rvalue_buf);
                        writeString(", sizeof(");
                        emitType(capture_type);
                        writeString("));\n");
                    } else {
                        writeString(c_name);
                        writeString(" = ");
                        writeString(rvalue_buf);
                        endStmt();
                    }
                }

                if (prong->body->type == NODE_BLOCK_STMT) {
                    emitBlock(&prong->body->as.block_stmt);
                } else {
                    emitStatement(prong->body);
                }

                if (has_non_void_capture) {
                    writeBlockClose();
                }

                writeIndent();
                writeString("break;\n");
            }
        }
    }
    writeBlockClose();

    if (is_tagged_union) {
        writeBlockClose();
    }
}

void C89Emitter::emitFor(const ASTForStmtNode* node) {
    if (!node) return;

    if (node->label_id < 0 || node->label_id >= 1024) {
        error_handler_.report(ERR_INTERNAL_ERROR, SourceLocation(), "loop label_id out of range");
        plat_abort();
    }

    loop_id_stack_.append(node->label_id);
    loop_has_continue_.append(false);
    loop_uses_labels_[node->label_id] = true;

    for_loop_counter_++;

    bool is_range = (node->iterable_expr->type == NODE_RANGE);

    const char* start_label = getLoopStartLabel(node->label_id);
    const char* cont_label = getLoopContinueLabel(node->label_id);
    const char* end_label = getLoopEndLabel(node->label_id);

    const char* iter_name = NULL;
    const char* idx_name = NULL;
    const char* len_name = NULL;

    writeIndent();
    writeBlockOpen();

    /* Declarations FIRST for C89 compliance */
    if (!is_range) {
        Type* iter_type = node->iterable_expr->resolved_type;
        Type* ptr_type = (iter_type->kind == TYPE_ARRAY) ?
            createPointerType(arena_, iter_type->as.array.element_type, false, false, &unit_.getTypeInterner()) :
            iter_type;
        iter_name = makeTempVarForType(ptr_type, "for_iter", true);
    }
    idx_name = makeTempVarForType(get_g_type_usize(), "for_idx", true);
    len_name = makeTempVarForType(get_g_type_usize(), "for_len", true);

    /* Assignments */
    if (!is_range) {
        writeIndent();
        writeString(iter_name);
        writeString(" = ");
        emitExpression(node->iterable_expr);
        endStmt();
    }

    /* Initializer */
    writeIndent();
    writeString(idx_name);
    writeString(" = ");
    if (is_range) {
        emitExpression(node->iterable_expr->as.range->start);
    } else {
        writeString("0");
    }
    endStmt();

    writeIndent();
    writeString(len_name);
    writeString(" = ");
    if (is_range) {
        emitExpression(node->iterable_expr->as.range->end);
    } else {
        Type* iterable_type = node->iterable_expr->resolved_type;
        if (iterable_type && iterable_type->kind == TYPE_ARRAY) {
            char size_buf[32];
            plat_u64_to_string(iterable_type->as.array.size, size_buf, sizeof(size_buf));
            writeString(size_buf);
        } else if (iterable_type && iterable_type->kind == TYPE_POINTER &&
                   iterable_type->as.pointer.base->kind == TYPE_ARRAY) {
            char size_buf[32];
            plat_u64_to_string(iterable_type->as.pointer.base->as.array.size, size_buf, sizeof(size_buf));
            writeString(size_buf);
        } else if (iterable_type && iterable_type->kind == TYPE_SLICE) {
            writeString(iter_name);
            writeString(".len");
        } else {
            writeString("0 /* Unknown length */");
        }
    }
    endStmt();

    writeIndent();
    writeString(start_label);
    writeString(": ;");
    writeLine();

    writeIndent();
    writeKeyword(KW_WHILE);
    writeString("(");
    writeString(idx_name);
    writeString(" < ");
    writeString(len_name);
    writeString(") ");
    writeBlockOpen();

    /* Item capture */
    Type* item_type = NULL;
    if (is_range) {
        item_type = get_g_type_usize();
    } else {
        Type* iterable_type = node->iterable_expr->resolved_type;
        if (iterable_type && iterable_type->kind == TYPE_ARRAY) {
            item_type = iterable_type->as.array.element_type;
        } else if (iterable_type && iterable_type->kind == TYPE_SLICE) {
            item_type = iterable_type->as.slice.element_type;
        }
    }

    if (item_type && node->item_name && plat_strcmp(node->item_name, "_") != 0) {
        const char* actual_item_name;
        if (node->item_sym) {
            actual_item_name = var_alloc_.allocate(node->item_sym);
        } else {
            actual_item_name = var_alloc_.generate(node->item_name);
        }

        writeIndent();
        writeDecl(item_type, actual_item_name);
        writeIndent();
        writeString(actual_item_name);
        writeString(" = ");
        if (is_range) {
            writeString(idx_name);
        } else {
            writeString(iter_name);
            if (node->iterable_expr->resolved_type && node->iterable_expr->resolved_type->kind == TYPE_SLICE) {
                writeString(".ptr[");
            } else {
                writeString("[");
            }
            writeString(idx_name);
            writeString("]");
        }
        endStmt();
    }

    /* Index capture */
    if (node->index_name && plat_strcmp(node->index_name, "_") != 0) {
        const char* actual_index_name;
        if (node->index_sym) {
            actual_index_name = var_alloc_.allocate(node->index_sym);
        } else {
            actual_index_name = var_alloc_.generate(node->index_name);
        }

        writeIndent();
        writeDecl(get_g_type_usize(), actual_index_name);
        writeIndent();
        writeString(actual_index_name);
        writeString(" = ");
        writeString(idx_name);
        endStmt();
    }

    /* Emit the actual body */
    if (node->body->type == NODE_BLOCK_STMT) {
        emitBlock(&node->body->as.block_stmt, node->label_id);
    } else {
        emitStatement(node->body);
    }
    writeLine();

    /* Continue label and Increment */
    if (loop_has_continue_.back()) {
        writeIndent();
        writeString(cont_label);
        writeString(": ;");
        writeLine();
    }

    writeIndent();
    writeString(idx_name);
    writeString("++");
    endStmt();

    writeIndent();
    writeKeyword(KW_GOTO);
    writeString(start_label);
    endStmt();

    writeBlockClose();

    writeIndent();
    writeString(end_label);
    writeString(": ;");
    writeLine();

    writeBlockClose();

    loop_id_stack_.pop_back();
    loop_has_continue_.pop_back();
}


void C89Emitter::emitWhile(const ASTWhileStmtNode* node) {
    if (!node) return;

    if (node->label_id < 0 || node->label_id >= 1024) {
        error_handler_.report(ERR_INTERNAL_ERROR, SourceLocation(), "loop label_id out of range");
        plat_abort();
    }

    loop_id_stack_.append(node->label_id);
    loop_has_continue_.append(false);

    /* Always mark this loop as using labels, so that any break/continue will be emitted as goto. */
    loop_uses_labels_[node->label_id] = true;
    const char* start_label = getLoopStartLabel(node->label_id);
    const char* cont_label = getLoopContinueLabel(node->label_id);
    const char* end_label = getLoopEndLabel(node->label_id);

    if (node->capture_name) {
        writeIndent();
        writeString(start_label);
        writeString(": ;");
        writeLine();

        writeIndent();
        writeKeyword(KW_WHILE);
        writeString("(1) ");
        writeBlockOpen();

        /* Declarations FIRST for C89 compliance */
        const char* tmp = makeTempVarForType(node->condition->resolved_type, "opt_tmp", true);
        const char* c_name = NULL;
        if (node->capture_sym && node->capture_sym->symbol_type->kind != TYPE_VOID) {
            c_name = var_alloc_.allocate(node->capture_sym);
            writeIndent();
            writeDecl(node->capture_sym->symbol_type, c_name);
        }

        /* Evaluate condition into a temporary */
        writeIndent();
        writeString(tmp);
        writeString(" = ");
        emitExpression(node->condition);
        endStmt();

        writeIndent();
        writeKeyword(KW_IF);
        writeString("(!");
        writeString(tmp);
        writeString(".has_value) ");
        writeKeyword(KW_GOTO);
        writeString(end_label);
        endStmt();

        /* Unwrap capture if non-void */
        if (c_name) {
            writeIndent();
            writeString(c_name);
            writeString(" = ");
            writeString(tmp);
            writeString(".value");
            endStmt();
        }

        /* Emit body */
        if (node->body->type == NODE_BLOCK_STMT) {
            emitBlock(&node->body->as.block_stmt, node->label_id);
        } else {
            emitStatement(node->body);
        }
        writeLine();

        if (loop_has_continue_.back()) {
            writeIndent();
            writeString(cont_label);
            writeString(": ;");
            writeLine();
        }

        /* Continue expression (if any) */
        if (node->iter_expr) {
            writeExprStmt(node->iter_expr);
        }

        writeIndent();
        writeKeyword(KW_GOTO);
        writeString(start_label);
        endStmt();

        writeBlockClose();

        writeIndent();
        writeString(end_label);
        writeString(": ;");
        writeLine();
    } else {
        writeIndent();
        writeString(start_label);
        writeString(": ;");
        writeLine();

        writeIndent();
        writeKeyword(KW_IF);
        writeString("(!(");
        if (node->condition) {
            emitExpression(node->condition);
        } else {
            writeString("1");
        }
        writeString(")) ");
        writeKeyword(KW_GOTO);
        writeString(end_label);
        endStmt();

        if (node->body->type == NODE_BLOCK_STMT) {
            writeIndent();
            emitBlock(&node->body->as.block_stmt, node->label_id);
        } else {
            emitStatement(node->body);
        }
        writeLine();

        if (loop_has_continue_.back()) {
            writeIndent();
            writeString(cont_label);
            writeString(": ;");
            writeLine();
        }
        if (node->iter_expr) {
            writeExprStmt(node->iter_expr);
        }

        writeIndent();
        writeKeyword(KW_GOTO);
        writeString(start_label);
        endStmt();

        writeIndent();
        writeString(end_label);
        writeString(": ;");
        writeLine();
    }

    loop_id_stack_.pop_back();
    loop_has_continue_.pop_back();
}


bool C89Emitter::isConstantInitializer(const ASTNode* node) const {
    if (!node) return true;
    switch (node->type) {
        case NODE_INTEGER_LITERAL:
        case NODE_FLOAT_LITERAL:
        case NODE_CHAR_LITERAL:
        case NODE_STRING_LITERAL:
        case NODE_BOOL_LITERAL:
        case NODE_NULL_LITERAL:
        case NODE_ERROR_LITERAL:
            return true;
        case NODE_PAREN_EXPR:
            return isConstantInitializer(node->as.paren_expr.expr);
        case NODE_UNARY_OP:
            if (node->as.unary_op.op == TOKEN_AMPERSAND) {
                /* Address-of is constant if operand is a global variable or member of one */
                ASTNode* operand = node->as.unary_op.operand;
                if (operand->type == NODE_IDENTIFIER) return true; /* Assuming identifier is global */
                if (operand->type == NODE_MEMBER_ACCESS) return isConstantInitializer(operand->as.member_access->base);
                if (operand->type == NODE_ARRAY_ACCESS) return isConstantInitializer(operand->as.array_access->array);
                return false;
            }
            return isConstantInitializer(node->as.unary_op.operand);
        case NODE_BINARY_OP:
            return isConstantInitializer(node->as.binary_op->left) &&
                   isConstantInitializer(node->as.binary_op->right);
        case NODE_IDENTIFIER:
            /* Function names are constant addresses in C89 */
            if (node->resolved_type && node->resolved_type->kind == TYPE_FUNCTION) {
                return true;
            }
            /* Identifiers are generally not constant initializers unless they are enum members or similar. */
            /* For now, we assume they might be global addresses if they are operands of '&'. */
            return false;
        case NODE_PTR_CAST:
        case NODE_INT_CAST:
        case NODE_FLOAT_CAST:
            return isConstantInitializer(node->as.ptr_cast->expr); /* All cast nodes have expr at same offset */
        case NODE_TUPLE_LITERAL: {
            DynamicArray<ASTNode*>* elements = node->as.tuple_literal->elements;
            for (size_t i = 0; i < elements->length(); ++i) {
                if (!isConstantInitializer((*elements)[i])) return false;
            }
            return true;
        }
        case NODE_STRUCT_INITIALIZER: {
            DynamicArray<ASTNamedInitializer*>* fields = node->as.struct_initializer->fields;
            for (size_t i = 0; i < fields->length(); ++i) {
                if (!isConstantInitializer((*fields)[i]->value)) return false;
            }
            return true;
        }
        case NODE_MEMBER_ACCESS: {
            /* Enum member access is constant */
            if (node->as.member_access->base->resolved_type) {
                Type* t = node->as.member_access->base->resolved_type;
                if (t->kind == TYPE_ENUM) {
                    return true;
                }
            }
            return false;
        }
        default:
            return false;
    }
}

void C89Emitter::write(const char* data, size_t len) {
    if (len == 0) return;

    if (in_type_def_mode_) {
        if (len > type_def_cap_ || type_def_pos_ > type_def_cap_ - len) {
            error_handler_.report(ERR_INTERNAL_ERROR, SourceLocation(), "Type definition buffer overflow");
            plat_abort();
        }
        plat_memcpy(type_def_buffer_ + type_def_pos_, data, len);
        type_def_pos_ += len;
        last_char_ = data[len - 1];
        return;
    }

    if (output_file_ == PLAT_INVALID_FILE) return;

    if (buffer_pos_ + len > sizeof(buffer_)) {
        flush();
        /* If the data is larger than the buffer itself, write it directly */
        if (len > sizeof(buffer_)) {
            plat_write_file(output_file_, data, len);
            last_char_ = data[len - 1];
            return;
        }
    }

    plat_memcpy(buffer_ + buffer_pos_, data, len);
    buffer_pos_ += len;
    last_char_ = data[len - 1];
}

void C89Emitter::writeString(const char* str) {
    if (!str) return;
    write(str, plat_strlen(str));
}

void C89Emitter::emitComment(const char* text) {
    if (!text) return;
    writeIndent();
    write("/* ", 3);
    writeString(text);
    write(" */\n", 4);
}

void C89Emitter::flush() {
    if (output_file_ != PLAT_INVALID_FILE && buffer_pos_ > 0) {
        plat_write_file(output_file_, buffer_, buffer_pos_);
        buffer_pos_ = 0;
    }
}

bool C89Emitter::open(const char* path) {
    close();
    output_file_ = plat_open_file(path, true);
    owns_file_ = true;
    return isValid();
}

void C89Emitter::close() {
    flush();
    if (owns_file_ && output_file_ != PLAT_INVALID_FILE) {
        plat_close_file(output_file_);
        output_file_ = PLAT_INVALID_FILE;
    }
}

void C89Emitter::ensureForwardDeclaration(Type* type) {
    if (!type) return;

    if (type->kind == TYPE_ENUM) {
        bool was_in_type_def = in_type_def_mode_;
        in_type_def_mode_ = true;
        emitTypeDefinition(type);
        in_type_def_mode_ = was_in_type_def;
        return;
    }

    const char* keyword = NULL;

    if (type->kind == TYPE_STRUCT) {
        keyword = "struct";
    } else if (isTaggedUnion(type)) {
        keyword = "struct";
    } else if (type->kind == TYPE_UNION) {
        keyword = "union";
    } else {
        /* Other types cannot be forward-declared in C89 */
        return;
    }

    const char* mangled_name = type->c_name;
    if (!mangled_name) {
        mangled_name = unit_.getNameMangler().mangleType(type);
    }
    if (!mangled_name) return;

    /* Avoid duplicate forward declarations */
    for (size_t i = 0; i < emitted_forward_decls_.length(); ++i) {
        if (plat_strcmp(emitted_forward_decls_[i], mangled_name) == 0) return;
    }
    emitted_forward_decls_.append(mangled_name);

    bool was_in_type_def = in_type_def_mode_;
    in_type_def_mode_ = true;

    writeIndent();
    writeString(keyword);
    writeString(" ");
    writeString(mangled_name);
    endStmt();

    in_type_def_mode_ = was_in_type_def;
}

void C89Emitter::emitExpression(const ASTNode* node) {
    if (!node) return;
    current_loc_ = node->loc;

    if (debug_trace_ && node->type == NODE_IDENTIFIER) {
        const char* name = node->as.identifier.name;
        plat_printf_debug("[CODEGEN] emitExpression IDENT: name=%s has_symbol=%d\n",
                         name ? name : "NULL",
                         node->as.identifier.symbol ? 1 : 0);
    }

    switch (node->type) {
        case NODE_VAR_DECL: {
            const ASTVarDeclNode* decl = node->as.var_decl;
            if (decl->symbol) {
                writeString(var_alloc_.allocate(decl->symbol));
            } else if (decl->name) {
                writeString(getC89GlobalName(decl->name));
            }
            break;
        }
        case NODE_INTEGER_LITERAL:
        case NODE_FLOAT_LITERAL:
        case NODE_STRING_LITERAL:
        case NODE_CHAR_LITERAL:
        case NODE_BOOL_LITERAL:
        case NODE_NULL_LITERAL:
        case NODE_ERROR_LITERAL:
        case NODE_UNDEFINED_LITERAL:
            emitLiteral(node);
            break;

        case NODE_UNARY_OP:
            if (node->as.unary_op.op == TOKEN_STAR || node->as.unary_op.op == TOKEN_DOT_ASTERISK) {
                Type* operand_type = node->as.unary_op.operand->resolved_type;
                if (operand_type && operand_type->kind == TYPE_POINTER && 
                    (operand_type->as.pointer.base->kind == TYPE_OPTIONAL || 
                     operand_type->as.pointer.base->kind == TYPE_ERROR_UNION)) {
                    writeString("(*");
                    emitExpression(node->as.unary_op.operand);
                    writeString(")");
                    break;
                }
            }
            emitUnaryOp(node->as.unary_op);
            break;

        case NODE_BINARY_OP:
            emitBinaryOp(*node->as.binary_op);
            break;

        case NODE_PTR_CAST:
        case NODE_INT_CAST:
        case NODE_FLOAT_CAST:
        case NODE_INT_TO_FLOAT:
            emitCast(node);
            break;

        case NODE_ARRAY_ACCESS:
        case NODE_MEMBER_ACCESS:
        case NODE_ARRAY_SLICE:
            emitAccess(node);
            break;

        case NODE_SWITCH_EXPR:
        case NODE_IF_EXPR:
        case NODE_TRY_EXPR:
        case NODE_CATCH_EXPR:
        case NODE_ORELSE_EXPR:
        case NODE_SWITCH_STMT:
            emitControlFlow(node);
            break;

        case NODE_TUPLE_LITERAL: {
            writeString("{");
            DynamicArray<ASTNode*>* elements = node->as.tuple_literal->elements;
            for (size_t i = 0; i < elements->length(); ++i) {
                emitExpression((*elements)[i]);
                if (i < elements->length() - 1) {
                    writeString(", ");
                }
            }
            writeString("}");
            break;
        }
        case NODE_UNREACHABLE:
            writeString("__bootstrap_panic(\"reached unreachable\", __FILE__, __LINE__)");
            break;
        case NODE_IDENTIFIER:
            if (node->resolved_type && node->resolved_type->kind == TYPE_VOID) {
                writeString("0");
                break;
            }
            if (node->as.identifier.symbol) {
                Symbol* sym = node->as.identifier.symbol;
                if (sym->flags & SYMBOL_FLAG_LOCAL) {
                    const char* c_name = var_alloc_.allocate(sym);

                    bool found = false;
                    for (size_t i = 0; i < emitted_decls_.length(); ++i) {
                        if (plat_strcmp(emitted_decls_[i], c_name) == 0) {
                            found = true;
                            break;
                        }
                    }
                    if (!found && debug_trace_) {
                        plat_printf_debug("[CODEGEN] WARNING: Using undeclared var: %s\n", c_name);
                    }

                    writeString(c_name);
                } else if (sym->mangled_name) {
                    writeString(sym->mangled_name);
                } else {
                    writeString(getC89GlobalName(sym->name));
                }
            } else {
                const char* name = node->as.identifier.name;
                if (name && (plat_strncmp(name, "__tmp_", 6) == 0 ||
                             plat_strncmp(name, "__return_", 9) == 0)) {

                    bool found = false;
                    for (size_t i = 0; i < emitted_decls_.length(); ++i) {
                        if (plat_strcmp(emitted_decls_[i], name) == 0) {
                            found = true;
                            break;
                        }
                    }
                    if (!found && debug_trace_) {
                        plat_printf_debug("[CODEGEN] WARNING: Using undeclared temp: %s\n", name);
                    }

                    writeString(name);
                } else {
                    writeString(getC89GlobalName(name));
                }
            }
            break;
        case NODE_PAREN_EXPR:
            writeString("(");
            emitExpression(node->as.paren_expr.expr);
            writeString(")");
            break;
        case NODE_RANGE:
            /* This should only happen if range is used outside for/slicing */
            if (node->as.range) {
                emitExpression(node->as.range->start);
                writeString(" /* .. */ ");
                emitExpression(node->as.range->end);
            }
            break;
        case NODE_IMPORT_STMT:
            writeString("/* import \"");
            writeString(node->as.import_stmt->module_name);
            writeString("\" */");
            break;
        case NODE_FUNCTION_CALL: {
            const ASTFunctionCallNode* call = node->as.function_call;
            const char* builtin_name = NULL;
            if (call->callee->type == NODE_IDENTIFIER && call->callee->as.identifier.name[0] == '@') {
                builtin_name = call->callee->as.identifier.name;
            }

            if (builtin_name) {
                if (plat_strcmp(builtin_name, "@enumToInt") == 0 ||
                    plat_strcmp(builtin_name, "@ptrToInt") == 0) {
                    writeString("(");
                    emitType(node->resolved_type);
                    writeString(")");
                    emitExpression((*call->args)[0]);
                    break;
                } else if (plat_strcmp(builtin_name, "@intToEnum") == 0) {
                    writeString("(");
                    emitType(node->resolved_type);
                    writeString(")");
                    emitExpression((*call->args)[1]);
                    break;
                }
            }

            bool need_parens = requiresParentheses(call->callee);
            if (need_parens) writeString("(");
            emitExpression(call->callee);
            if (need_parens) writeString(")");

            writeString("(");
            if (call->args) {
                for (size_t i = 0; i < call->args->length(); ++i) {
                    emitExpression((*call->args)[i]);
                    if (i < call->args->length() - 1) {
                        writeString(", ");
                    }
                }
            }
            writeString(")");
            break;
        }
        case NODE_ASSIGNMENT:
            if (node->as.assignment->lvalue->type == NODE_IDENTIFIER &&
                plat_strcmp(node->as.assignment->lvalue->as.identifier.name, "_") == 0) {
                writeString("(void)(");
                emitExpression(node->as.assignment->rvalue);
                writeString(")");
            } else {
                emitExpression(node->as.assignment->lvalue);
                writeString(" = ");
                emitExpression(node->as.assignment->rvalue);
            }
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            writeString("(void)(");
            emitExpression(node->as.compound_assignment->lvalue);
            writeString(" ");
            writeString(getTokenSpelling(node->as.compound_assignment->op));
            writeString(" ");
            emitExpression(node->as.compound_assignment->rvalue);
            writeString(")");
            break;
        case NODE_STRUCT_INITIALIZER: {
            if (!node->as.struct_initializer->fields || node->as.struct_initializer->fields->length() == 0) {
                writeString("{0}");
                break;
            }
            writeString("{");
            Type* struct_type = node->resolved_type;
            if (struct_type && isTaggedUnion(struct_type)) {
                const ASTStructInitializerNode* init = node->as.struct_initializer;
#ifdef DEBUG_TAGGED_UNION
                plat_printf_debug("[CODEGEN] NODE_STRUCT_INITIALIZER (tagged union expression)\n");
#endif
                if (init->fields && init->fields->length() > 0) {
                    /* Emit tag: .tag = TagConstant */
                    ASTNamedInitializer* tag_init = (*init->fields)[0];
                    writeString(".tag = ");
                    
                    /* Emit the enum tag constant reference */
                    Type* tag_enum = getTagType(struct_type);
                    if (tag_enum && tag_enum->c_name) {
                        writeString(tag_enum->c_name);
                    } else {
                        writeString(unit_.getNameMangler().mangleType(tag_enum));
                    }
                    writeString("_");
                    writeString(tag_init->field_name);
                    
                    /* If variant has non-void payload, emit it too */
                    Type* variant_type = findTaggedUnionPayload(struct_type, tag_init->field_name);
                    if (variant_type && variant_type->kind != TYPE_VOID && tag_init->value) {
                        writeString(", .data = {.");
                        writeString(getSafeFieldName(tag_init->field_name));
                        writeString(" = ");
                        emitExpression(tag_init->value);
                        writeString("}");
                    }
                } else {
                    writeString("0");
                }
                writeString("}");
                break;
            }

            if (struct_type && struct_type->kind == TYPE_STRUCT) {
                DynamicArray<StructField>* type_fields = struct_type->as.struct_details.fields;
                DynamicArray<ASTNamedInitializer*>* init_fields = node->as.struct_initializer->fields;

                for (size_t i = 0; i < type_fields->length(); ++i) {
                    const char* field_name = (*type_fields)[i].name;
                    /* Find this field in the initializer */
                    bool found = false;
                    for (size_t j = 0; j < init_fields->length(); ++j) {
                        if (plat_strcmp((*init_fields)[j]->field_name, field_name) == 0) {
                            emitExpression((*init_fields)[j]->value);
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        writeString("0"); /* Fallback for missing fields if allowed */
                    }
                    if (i < type_fields->length() - 1) {
                        writeString(", ");
                    }
                }
            } else {
                /* Fallback if type info is missing */
                DynamicArray<ASTNamedInitializer*>* fields = node->as.struct_initializer->fields;
                for (size_t i = 0; i < fields->length(); ++i) {
                    emitExpression((*fields)[i]->value);
                    if (i < fields->length() - 1) {
                        writeString(", ");
                    }
                }
            }
            writeString("}");
            break;
        }
        case NODE_RETURN_STMT:
            emitReturn(&node->as.return_stmt);
            break;
        case NODE_BREAK_STMT:
            emitBreak(&node->as.break_stmt);
            break;
        case NODE_CONTINUE_STMT:
            emitContinue(&node->as.continue_stmt);
            break;
        default:
            error_handler_.report(ERR_UNSUPPORTED_FEATURE, current_loc_, "Unimplemented expression type in code generation");
            break;
    }
}

void C89Emitter::emitLiteral(const ASTNode* node) {
    switch (node->type) {
        case NODE_INTEGER_LITERAL:
            emitIntegerLiteral(&node->as.integer_literal);
            break;
        case NODE_FLOAT_LITERAL:
            emitFloatLiteral(&node->as.float_literal);
            break;
        case NODE_STRING_LITERAL:
            emitStringLiteral(&node->as.string_literal);
            break;
        case NODE_CHAR_LITERAL:
            emitCharLiteral(&node->as.char_literal);
            break;
        case NODE_BOOL_LITERAL:
            writeString(node->as.bool_literal.value ? "1" : "0");
            break;
        case NODE_NULL_LITERAL:
            writeString("((void*)0)");
            break;
        case NODE_ERROR_LITERAL:
            writeString("ERROR_");
            writeString(node->as.error_literal.tag_name);
            break;
        case NODE_UNDEFINED_LITERAL:
            /* undefined in Zig means "uninitialized". In expression context,
               we emit 0 for safety and to maintain valid C syntax. */
            if (node->resolved_type && (node->resolved_type->kind == TYPE_POINTER || node->resolved_type->kind == TYPE_FUNCTION_POINTER)) {
                writeString("((void*)0)");
            } else if (node->resolved_type && (node->resolved_type->kind == TYPE_STRUCT || node->resolved_type->kind == TYPE_UNION || node->resolved_type->kind == TYPE_TAGGED_UNION || node->resolved_type->kind == TYPE_ARRAY)) {
                writeString("{0}");
            } else {
                writeString("0");
            }
            break;
        default: break;
    }
}

void C89Emitter::emitUnaryOp(const ASTUnaryOpNode& node) {
    writeString(getTokenSpelling(node.op));
    emitExpression(node.operand);
}

void C89Emitter::emitBinaryOp(const ASTBinaryOpNode& node) {
    /* Optional vs null comparisons. */
    Type* left_type = node.left->resolved_type;
    Type* right_type = node.right->resolved_type;

    if ((left_type && left_type->kind == TYPE_OPTIONAL && right_type && right_type->kind == TYPE_NULL) ||
        (left_type && left_type->kind == TYPE_NULL && right_type && right_type->kind == TYPE_OPTIONAL)) {

        const ASTNode* opt_node = (left_type && left_type->kind == TYPE_OPTIONAL) ? node.left : node.right;

        if (node.op == TOKEN_EQUAL_EQUAL) {
            writeString("(!");
            emitExpression(opt_node);
            writeString(".has_value)");
        } else if (node.op == TOKEN_BANG_EQUAL) {
            writeString("(");
            emitExpression(opt_node);
            writeString(".has_value)");
        } else {
            /* Fallback (should be rejected by type checker) */
            emitExpression(node.left);
            writeString(" ");
            writeString(getTokenSpelling(node.op));
            writeString(" ");
            emitExpression(node.right);
        }
        return;
    }

    emitExpression(node.left);
    writeString(" ");
    writeString(getTokenSpelling(node.op));
    writeString(" ");
    emitExpression(node.right);
}

void C89Emitter::emitCast(const ASTNode* node) {
    switch (node->type) {
        case NODE_PTR_CAST:
            writeString("(");
            emitType(node->as.ptr_cast->target_type->resolved_type);
            writeString(")");
            emitExpression(node->as.ptr_cast->expr);
            break;
        case NODE_INT_CAST:
            emitIntCast(node->as.numeric_cast);
            break;
        case NODE_FLOAT_CAST:
        case NODE_INT_TO_FLOAT:
            emitFloatCast(node->as.numeric_cast);
            break;
        default: break;
    }
}

void C89Emitter::emitBaseWithParens(const ASTNode* base) {
    if (base->type == NODE_UNARY_OP &&
        (base->as.unary_op.op == TOKEN_STAR ||
         base->as.unary_op.op == TOKEN_DOT_ASTERISK)) {
        writeString("(");
        emitExpression(base);
        writeString(")");
    } else {
        bool need_parens = requiresParentheses(base);
        if (need_parens) writeString("(");
        emitExpression(base);
        if (need_parens) writeString(")");
    }
}

void C89Emitter::emitAccess(const ASTNode* node) {
#ifdef DEBUG_SYMBOL
    if (node->type == NODE_MEMBER_ACCESS) {
        const ASTMemberAccessNode* member = node->as.member_access;
        Type* base_type = member->base->resolved_type;
        plat_printf_debug("[EMITTER] MEMBER_ACCESS: field='%s' base_type=%p base_type_kind=%d\n",
                         member->field_name,
                         (void*)base_type,
                         base_type ? base_type->kind : -1);
    }
#endif
    switch (node->type) {
        case NODE_ARRAY_ACCESS: {
            const ASTNode* array_node = node->as.array_access->array;
            Type* array_type = array_node->resolved_type;
            bool is_ptr_to_array = (array_type && array_type->kind == TYPE_POINTER &&
                                    array_type->as.pointer.base->kind == TYPE_ARRAY);
            bool is_slice = (array_type && array_type->kind == TYPE_SLICE);

            if (is_ptr_to_array) {
                writeString("(*");
            }

            bool need_parens = requiresParentheses(array_node);
            if (need_parens) writeString("(");
            emitExpression(array_node);
            if (need_parens) writeString(")");

            if (is_ptr_to_array) {
                writeString(")");
            }

            if (is_slice) {
                writeString(".ptr");
            }

            writeString("[");
            emitExpression(node->as.array_access->index);
            writeString("]");
            break;
        }
        case NODE_MEMBER_ACCESS: {
            const ASTMemberAccessNode* member = node->as.member_access;
            Type* base_type = member->base->resolved_type;
            Type* effective_base = base_type;
            if (effective_base && effective_base->kind == TYPE_POINTER) {
                effective_base = effective_base->as.pointer.base;
            }

            // Handle tagged union instance access
            if (effective_base && isTaggedUnion(effective_base) && effective_base->kind != TYPE_TYPE) {
                const char* field_name = member->field_name;

                // 1. Tag access
                if (plat_strcmp(field_name, "tag") == 0) {
                    emitBaseWithParens(member->base);
                    writeString(base_type->kind == TYPE_POINTER ? "->" : ".");
                    writeString("tag");
                    return;
                }

                // 2. Variant access (e.g., v.Cons)
                // (We don't need to check existence; the type checker already did)
                emitBaseWithParens(member->base);
                writeString(base_type->kind == TYPE_POINTER ? "->" : ".");
                writeString("data.");
                writeString(getSafeFieldName(field_name));
                return;
            }

            const ASTNode* base = node->as.member_access->base;
            if (base->resolved_type) {
                Type* actual_type = base->resolved_type;

                if (actual_type->kind == TYPE_ERROR_SET) {
                    writeString("ERROR_");
                    writeString(node->as.member_access->field_name);
                    return;
                }

                if (actual_type->kind == TYPE_ENUM) {
                    if (actual_type->c_name) {
                        writeString(actual_type->c_name);
                    } else if (actual_type->as.enum_details.name) {
                        writeString(unit_.getNameMangler().mangleType(actual_type));
                    } else {
                        writeString("/* anonymous enum */");
                    }
                    writeString("_");
                    writeString(node->as.member_access->field_name);
                    return;
                }

                if (actual_type->kind == TYPE_MODULE || actual_type->kind == TYPE_ANYTYPE) {
                    if (node->as.member_access->symbol && node->as.member_access->symbol->mangled_name) {
                        writeString(node->as.member_access->symbol->mangled_name);
                    } else {
                        const char* mod_name = (actual_type->kind == TYPE_MODULE) ?
                                              actual_type->as.module.name :
                                              (base->type == NODE_IDENTIFIER ? base->as.identifier.name : NULL);
                        if (mod_name) {
                            writeString(unit_.getNameMangler().mangle('V', mod_name, node->as.member_access->field_name));
                        } else {
                            writeString(node->as.member_access->field_name);
                        }
                    }
                    return;
                }
            }

            if (base->type == NODE_UNARY_OP &&
                (base->as.unary_op.op == TOKEN_STAR || base->as.unary_op.op == TOKEN_DOT_ASTERISK)) {
                plat_printf_debug("[emitAccess] Wrapping dereference base\n");
                writeString("(");
                emitExpression(base);
                writeString(")");
            } else {
                bool need_parens = requiresParentheses(base);
                if (need_parens) writeString("(");
                emitExpression(base);
                if (need_parens) writeString(")");
            }

            if (base->resolved_type && base->resolved_type->kind == TYPE_POINTER) {
                writeString("->");
            } else {
                writeString(".");
            }
            writeString(node->as.member_access->field_name);
            break;
        }
        case NODE_ARRAY_SLICE:
            emitArraySlice(node);
            break;
        default: break;
    }
}

void C89Emitter::emitControlFlow(const ASTNode* node) {
    const char* kind = "unknown control flow";
    switch (node->type) {
        case NODE_SWITCH_EXPR: kind = "Switch expression"; break;
        case NODE_IF_EXPR:     kind = "If expression"; break;
        case NODE_TRY_EXPR:    kind = "Try expression"; break;
        case NODE_CATCH_EXPR:  kind = "Catch expression"; break;
        case NODE_ORELSE_EXPR: kind = "Orelse expression"; break;
        default: break;
    }
    error_handler_.report(ERR_UNSUPPORTED_FEATURE, node->loc, ErrorHandler::getMessage(ERR_UNSUPPORTED_FEATURE), kind);
}

void C89Emitter::emitArraySlice(const ASTNode* node) {
    if (!node || node->type != NODE_ARRAY_SLICE) return;
    const ASTArraySliceNode* slice = node->as.array_slice;
    if (!slice || !slice->base_ptr || !slice->len) return;

    Type* result_type = node->resolved_type;
    if (!result_type || result_type->kind != TYPE_SLICE) return;

    Type* elem_type = result_type->as.slice.element_type;

    ensureSliceType(result_type);

    writeString("__make_slice_");
    writeString(getMangledTypeName(elem_type));
    writeString("(");
    emitExpression(slice->base_ptr);
    writeString(", ");
    emitExpression(slice->len);
    writeString(")");
}

void C89Emitter::ensureOptionalType(Type* type) {
    if (!type || type->kind != TYPE_OPTIONAL) return;

    Type* payload = type->as.optional.payload;
    ensureForwardDeclaration(payload);

    const char* mangled_name = unit_.getNameMangler().mangleType(type);

    /* Check per-module cache first */
    for (size_t i = 0; i < emitted_optionals_.length(); ++i) {
        if (plat_strcmp(emitted_optionals_[i], mangled_name) == 0) return;
    }

    /* Check external cache (global) only if not in header mode.
       Headers must always emit their own guarded definitions to be self-contained. */
    if (!is_header_ && external_cache_) {
        for (size_t j = 0; j < external_cache_->length(); ++j) {
            if (plat_strcmp((*external_cache_)[j], mangled_name) == 0) return;
        }
    }

    emitted_optionals_.append(mangled_name);
    if (external_cache_) {
        bool already_in_external = false;
        for (size_t k = 0; k < external_cache_->length(); ++k) {
            if (plat_strcmp((*external_cache_)[k], mangled_name) == 0) {
                already_in_external = true;
                break;
            }
        }
        if (!already_in_external) {
            external_cache_->append(mangled_name);
        }
    }

    bool was_in_type_def = in_type_def_mode_;
    in_type_def_mode_ = true;

    writeString("#ifndef ZIG_OPTIONAL_");
    writeString(mangled_name);
    writeString("\n#define ZIG_OPTIONAL_");
    writeString(mangled_name);
    writeLine();

    writeIndent();
    writeKeyword(KW_STRUCT);
    writeString(mangled_name);
    writeString(" ");
    {
        writeString("{\n");
        IndentScope struct_indent(*this);
        if (payload->kind != TYPE_VOID) {
            writeIndent();
            emitType(payload, "value");
            endStmt();
        }
        writeIndent();
        writeString("int has_value;\n");
        dedent();
        writeIndent();
        writeString("};\n");
    }
    writeIndent();
    writeKeyword(KW_TYPEDEF); writeKeyword(KW_STRUCT);
    writeString(mangled_name);
    writeString(" ");
    writeString(mangled_name);
    writeString(";\n#endif\n\n");

    in_type_def_mode_ = was_in_type_def;
}

void C89Emitter::ensureErrorUnionType(Type* type) {
    if (!type || type->kind != TYPE_ERROR_UNION) return;

    Type* payload = type->as.error_union.payload;
    ensureForwardDeclaration(payload);

    const char* mangled_name = unit_.getNameMangler().mangleType(type);

    /* Check per-module cache first */
    for (size_t i = 0; i < emitted_error_unions_.length(); ++i) {
        if (plat_strcmp(emitted_error_unions_[i], mangled_name) == 0) return;
    }

    /* Check external cache (global) only if not in header mode.
       Headers must always emit their own guarded definitions to be self-contained. */
    if (!is_header_ && external_cache_) {
        for (size_t j = 0; j < external_cache_->length(); ++j) {
            if (plat_strcmp((*external_cache_)[j], mangled_name) == 0) return;
        }
    }

    emitted_error_unions_.append(mangled_name);
    if (external_cache_) {
        bool already_in_external = false;
        for (size_t k = 0; k < external_cache_->length(); ++k) {
            if (plat_strcmp((*external_cache_)[k], mangled_name) == 0) {
                already_in_external = true;
                break;
            }
        }
        if (!already_in_external) {
            external_cache_->append(mangled_name);
        }
    }

    bool was_in_type_def = in_type_def_mode_;
    in_type_def_mode_ = true;

    writeString("#ifndef ZIG_ERRORUNION_");
    writeString(mangled_name);
    writeString("\n#define ZIG_ERRORUNION_");
    writeString(mangled_name);
    writeLine();

    writeIndent();
    writeKeyword(KW_STRUCT);
    writeString(mangled_name);
    writeString(" ");
    {
        writeString("{\n");
        IndentScope struct_indent(*this);
        if (payload->kind != TYPE_VOID) {
            writeIndent();
            writeString("union {\n");
            {
                IndentScope union_indent(*this);
                writeIndent();
                emitType(payload, "payload");
                endStmt();
                writeIndent();
                writeString("int err;\n");
            }
            writeIndent();
            writeString("} data;\n");
        } else {
            writeIndent();
            writeString("int err;\n");
        }
        writeIndent();
        writeString("int is_error;\n");
        dedent();
        writeIndent();
        writeString("};\n");
    }
    writeIndent();
    writeKeyword(KW_TYPEDEF); writeKeyword(KW_STRUCT);
    writeString(mangled_name);
    writeString(" ");
    writeString(mangled_name);
    writeString(";\n#endif\n\n");

    in_type_def_mode_ = was_in_type_def;
}

void C89Emitter::ensureSliceType(Type* type) {
    if (!type || type->kind != TYPE_SLICE) return;

    Type* elem_type = type->as.slice.element_type;
    ensureForwardDeclaration(elem_type);

    const char* mangled_name = unit_.getNameMangler().mangleType(type);

    /* Check per-module cache first */
    for (size_t i = 0; i < emitted_slices_.length(); ++i) {
        if (plat_strcmp(emitted_slices_[i], mangled_name) == 0) return;
    }

    /* Not emitted in this context, register it globally for central header emission */
    unit_.registerSliceType(type);
    emitted_slices_.append(mangled_name);

    if (external_cache_) {
        bool already_in_external = false;
        for (size_t k = 0; k < external_cache_->length(); ++k) {
            if (plat_strcmp((*external_cache_)[k], mangled_name) == 0) {
                already_in_external = true;
                break;
            }
        }
        if (!already_in_external) {
            external_cache_->append(mangled_name);
        }
    }
}

void C89Emitter::emitBufferedTypeDefinitions() {
    if (type_def_pos_ > 0) {
        write(type_def_buffer_, type_def_pos_);
        type_def_pos_ = 0;
    }
}

void C89Emitter::emitBufferedSlices() {
    emitBufferedTypeDefinitions();
}

void C89Emitter::emitBufferedErrorUnions() {
    emitBufferedTypeDefinitions();
}

void C89Emitter::emitBufferedOptionals() {
    emitBufferedTypeDefinitions();
}

void C89Emitter::emitTypeDefinition(const ASTNode* node) {
    if (!node) return;

    if (node->type == NODE_VAR_DECL) {
        const ASTVarDeclNode* decl = node->as.var_decl;
        if (!decl || !decl->initializer) return;

        Type* type = decl->initializer->resolved_type;
        if (!type) return;

        /* Only emit definition if this is a type declaration (e.g. const T = struct { ... }) */
        if (!decl->is_const || (type->kind != TYPE_STRUCT && type->kind != TYPE_UNION &&
                                type->kind != TYPE_TAGGED_UNION && type->kind != TYPE_ENUM)) {
            return;
        }

        emitTypeDefinition(type);
    }
}

void C89Emitter::emitStructBody(Type* type) {
    if (!type || type->kind != TYPE_STRUCT) return;

    writeString("{\n");
    {
        IndentScope struct_indent(*this);
        DynamicArray<StructField>* fields = type->as.struct_details.fields;
        if (fields) {
            for (size_t i = 0; i < fields->length(); ++i) {
                /* Skip void fields in C */
                if ((*fields)[i].type->kind == TYPE_VOID) continue;
                writeIndent();

                Type* field_type = (*fields)[i].type;
                const char* field_name = getSafeFieldName((*fields)[i].name);

                emitType(field_type, field_name);
                endStmt();
            }
        }
    }
    writeIndent();
    writeString("}");
}

void C89Emitter::emitUnionBody(Type* type) {
    if (!type || type->kind != TYPE_UNION) return;

    writeString("{\n");
    {
        IndentScope union_indent(*this);
        DynamicArray<StructField>* fields = type->as.struct_details.fields;
        int emitted_fields = 0;
        if (fields) {
            for (size_t i = 0; i < fields->length(); ++i) {
                Type* field_type = (*fields)[i].type;

                /* Robustly check for void fields, including placeholders that resolve to void. */
                if (field_type->kind == TYPE_PLACEHOLDER) {
                    /* We don't want to mutate here, but we need the real kind. */
                    /* TypeChecker::resolvePlaceholder is not available here. */
                }

                if (field_type->kind == TYPE_VOID) continue;
                writeIndent();

                const char* field_name = getSafeFieldName((*fields)[i].name);

                emitType(field_type, field_name);
                endStmt();
                emitted_fields++;
            }
        }
        if (emitted_fields == 0) {
            writeIndent();
            writeString("char __dummy;\n");
        }
    }
    writeIndent();
    writeString("}");
}

void C89Emitter::emitTaggedUnionBody(Type* type) {
    if (!isTaggedUnion(type)) return;

    writeString("{\n");
    {
        IndentScope struct_indent(*this);

        /* tag */
        writeIndent();
        Type* tag_type = (type->kind == TYPE_TAGGED_UNION) ? type->as.tagged_union.tag_type : type->as.struct_details.tag_type;
        emitType(tag_type, "tag");
        endStmt();

        /* union of payloads */
        writeIndent();
        writeKeyword(KW_UNION);
        emitTaggedUnionPayloadBody(type);
        writeString(" data;\n");
    }
    writeIndent();
    writeString("}");
}

void C89Emitter::emitTaggedUnionPayloadBody(Type* type) {
    if (!isTaggedUnion(type)) return;

    writeString("{\n");
    {
        IndentScope union_indent(*this);
        DynamicArray<StructField>* fields = (type->kind == TYPE_TAGGED_UNION) ? type->as.tagged_union.payload_fields : type->as.struct_details.fields;
        int emitted_fields = 0;
        if (fields) {
            for (size_t i = 0; i < fields->length(); ++i) {
                /* Skip void fields in C */
                if ((*fields)[i].type->kind == TYPE_VOID) continue;
                writeIndent();

                Type* field_type = (*fields)[i].type;
                const char* field_name = getSafeFieldName((*fields)[i].name);

                emitType(field_type, field_name);
                endStmt();
                emitted_fields++;
            }
        }
        if (emitted_fields == 0) {
            writeIndent();
            writeString("char __dummy;\n");
        }
    }
    writeIndent();
    writeString("}");
}

void C89Emitter::emitTaggedUnionDefinition(Type* type) {
    if (!isTaggedUnion(type)) return;

    /* Ensure tag enum is emitted first */
    Type* tag_type = (type->kind == TYPE_TAGGED_UNION) ? type->as.tagged_union.tag_type : type->as.struct_details.tag_type;
    if (tag_type && tag_type->kind == TYPE_ENUM) {
        emitTypeDefinition(tag_type);
    }

    ensureForwardDeclaration(type);

    writeIndent();
    writeKeyword(KW_STRUCT);
    writeString(type->c_name ? type->c_name : "/* unknown */");
    writeString(" ");
    emitTaggedUnionBody(type);
    writeString(";\n\n");
}

void C89Emitter::emitTypeDefinition(Type* type) {
    if (!type) return;

    static int depth = 0;
    if (++depth > 100) {
        error_handler_.report(ERR_INTERNAL_ERROR, SourceLocation(), "Recursion depth exceeded in type emission");
        plat_abort();
    }

    const char* mangled = type->c_name;
    if (!mangled) mangled = unit_.getNameMangler().mangleType(type);

    /* Guard prefix */
    const char* prefix = NULL;
    if (type->kind == TYPE_STRUCT || type->kind == TYPE_TAGGED_UNION) prefix = "ZIG_STRUCT_";
    else if (type->kind == TYPE_UNION) prefix = "ZIG_UNION_";
    else if (type->kind == TYPE_ENUM) prefix = "ZIG_ENUM_";

    /* Check cache for enums BEFORE writing guard */
    if (type->kind == TYPE_ENUM) {
        for (size_t i = 0; i < emitted_enums_.length(); ++i) {
            if (plat_strcmp(emitted_enums_[i], mangled) == 0) {
                depth--;
                return;
            }
        }
    }

    if (prefix) {
        writeString("#ifndef ");
        writeString(prefix);
        writeString(mangled);
        writeString("\n#define ");
        writeString(prefix);
        writeString(mangled);
        writeLine();
    }

    /* Emit definitions for anonymous payload structs/unions used as fields */
    DynamicArray<StructField>* fields = NULL;
    if (type->kind == TYPE_TAGGED_UNION) {
        fields = type->as.tagged_union.payload_fields;
    } else if (type->kind == TYPE_STRUCT || type->kind == TYPE_UNION) {
        fields = type->as.struct_details.fields;
    }

    if (fields) {
        for (size_t i = 0; i < fields->length(); ++i) {
            Type* field_type = (*fields)[i].type;
            if (field_type && (field_type->kind == TYPE_STRUCT || field_type->kind == TYPE_UNION || field_type->kind == TYPE_TAGGED_UNION)) {
                const char* name = (field_type->kind == TYPE_TAGGED_UNION) ? field_type->as.tagged_union.name : field_type->as.struct_details.name;
                if (!name) {
                    emitTypeDefinition(field_type);
                }
            }
        }
    }

    if (isTaggedUnion(type)) {
        emitTaggedUnionDefinition(type);
        if (prefix) {
            writeString("#endif /* ");
            writeString(prefix);
            writeString(mangled);
            writeString(" */\n\n");
        }
        depth--;
        return;
    }

    if (type->kind == TYPE_ENUM) {
        const char* enum_name = mangled;
        emitted_enums_.append(enum_name);

        writeIndent();
        writeKeyword(KW_ENUM);
        writeString(enum_name);
        writeString(" {\n");
        {
            IndentScope enum_indent(*this);
            DynamicArray<EnumMember>* members = type->as.enum_details.members;
            if (members) {
                for (size_t i = 0; i < members->length(); ++i) {
                    writeIndent();
                    writeString(enum_name);
                    writeString("_");
                    writeString((*members)[i].name);
                    writeString(" = ");
                    char buf[32];
                    plat_i64_to_string((*members)[i].value, buf, sizeof(buf));
                    writeString(buf);
                    if (i < members->length() - 1) {
                        writeString(",");
                    }
                    writeLine();
                }
            }
        }
        writeIndent();
        writeString("};\n");
        writeIndent();
        writeKeyword(KW_TYPEDEF); writeKeyword(KW_ENUM);
        writeString(enum_name);
        writeString(" ");
        writeString(enum_name);
        writeString(";\n\n");

        if (prefix) {
            writeString("#endif /* ");
            writeString(prefix);
            writeString(mangled);
            writeString(" */\n\n");
        }

        depth--;
        return;
    }

    ensureForwardDeclaration(type);

    if (type->kind == TYPE_STRUCT) {
        writeIndent();
        writeKeyword(KW_STRUCT);
        writeString(type->c_name ? type->c_name : "/* unknown */");
        if (type->as.struct_details.fields) {
            writeString(" ");
            emitStructBody(type);
            writeString(";\n\n");
        } else {
            writeString("; /* opaque */\n\n");
        }
    } else if (type->kind == TYPE_UNION) {
        writeIndent();
        writeKeyword(KW_UNION);
        writeString(type->c_name ? type->c_name : "/* unknown */");
        if (type->as.struct_details.fields) {
            writeString(" ");
            emitUnionBody(type);
            writeString(";\n\n");
        } else {
            writeString("; /* opaque union */\n\n");
        }
    } else if (type->kind == TYPE_SLICE) {
        ensureSliceType(type);
    } else if (type->kind == TYPE_ERROR_UNION) {
        ensureErrorUnionType(type);
    } else if (type->kind == TYPE_OPTIONAL) {
        ensureOptionalType(type);
    }

    if (prefix) {
        writeString("#endif /* ");
        writeString(prefix);
        writeString(mangled);
        writeString(" */\n\n");
    }

    depth--;
}

void C89Emitter::emitIntCast(const ASTNumericCastNode* node) {
    if (!node || !node->expr || !node->target_type) return;

    Type* src_type = node->expr->resolved_type;
    Type* dest_type = node->target_type->resolved_type;

    if (!src_type || !dest_type) {
        plat_print_debug("Error: Missing type info in @intCast\n");
        plat_abort();
    }

    if (isSafeWidening(src_type, dest_type)) {
        writeString("(");
        emitType(dest_type);
        writeString(")");
        emitExpression(node->expr);
    } else {
        writeString("__bootstrap_");
        writeString(getZigTypeName(dest_type));
        writeString("_from_");
        writeString(getZigTypeName(src_type));
        writeString("(");
        emitExpression(node->expr);
        writeString(")");
    }
}

void C89Emitter::emitFloatCast(const ASTNumericCastNode* node) {
    if (!node || !node->expr || !node->target_type) return;

    Type* src_type = node->expr->resolved_type;
    Type* dest_type = node->target_type->resolved_type;

    if (!src_type || !dest_type) {
        plat_print_debug("Error: Missing type info in @floatCast\n");
        plat_abort();
    }

    if (isSafeWidening(src_type, dest_type)) {
        writeString("(");
        emitType(dest_type);
        writeString(")");
        emitExpression(node->expr);
    } else {
        writeString("__bootstrap_");
        writeString(getZigTypeName(dest_type));
        writeString("_from_");
        writeString(getZigTypeName(src_type));
        writeString("(");
        emitExpression(node->expr);
        writeString(")");
    }
}

void C89Emitter::emitIntegerLiteral(const ASTIntegerLiteralNode* node) {
    if (node->original_name && node->resolved_type && node->resolved_type->kind == TYPE_ENUM) {
        if (node->resolved_type->c_name) {
            writeString(node->resolved_type->c_name);
        } else if (node->resolved_type->as.enum_details.name) {
            writeString(unit_.getNameMangler().mangleType(node->resolved_type));
        } else {
            writeString("/* anonymous enum */");
        }
        writeString("_");
        writeString(node->original_name);
        return;
    }

    char buf[32];
    plat_u64_to_string(node->value, buf, sizeof(buf));
    writeString(buf);

    if (node->resolved_type) {
        switch (node->resolved_type->kind) {
            case TYPE_U32:
                writeString("U");
                break;
            case TYPE_I64:
#ifdef ZIG_COMPILER_OPENWATCOM
                writeString("LL");
#else
                writeString(ZIG_I64_SUFFIX);
#endif
                break;
            case TYPE_U64:
#ifdef ZIG_COMPILER_OPENWATCOM
                writeString("ULL");
#else
                writeString(ZIG_UI64_SUFFIX);
#endif
                break;
            default:
                /* i32, u8, i8, u16, i16, usize, isize get no suffix */
                break;
        }
    }
}

void C89Emitter::emitFloatLiteral(const ASTFloatLiteralNode* node) {
    char buffer[64];
    plat_float_to_string(node->value, buffer, sizeof(buffer));

    /* Ensure it's treated as a float by C (add .0 if no '.' or 'e') */
    bool has_dot = false;
    bool has_exp = false;
    for (char* p = buffer; *p; ++p) {
        if (*p == '.') has_dot = true;
        if (*p == 'e' || *p == 'E') has_exp = true;
    }

    writeString(buffer);
    if (!has_dot && !has_exp) {
        writeString(".0");
    }

    if (node->resolved_type && node->resolved_type->kind == TYPE_F32) {
        writeString("f");
    }
}

void C89Emitter::emitStringLiteral(const ASTStringLiteralNode* node) {
    if (!node || !node->value) return;

    size_t chunk_chars = 0;

    write("\"", 1);
    const char* p = node->value;
    while (*p) {
        if (chunk_chars >= max_string_literal_chunk_) {
            write("\" \"", 3);
            chunk_chars = 0;
        }
        emitEscapedByte((unsigned char)*p, false);
        p++;
        chunk_chars++;
    }
    write("\"", 1);
}

void C89Emitter::emitCharLiteral(const ASTCharLiteralNode* node) {
    if (!node) return;
    write("'", 1);
    emitEscapedByte((unsigned char)node->value, true);
    write("'", 1);
}

const char* C89Emitter::getC89GlobalName(const char* zig_name) {
    if (!zig_name) return "z_anonymous";

    if (isInternalCompilerIdentifier(zig_name)) {
        /* Truncate if needed, then return directly (no prefix, no uniquification) */
        char buf[256];
        plat_strcpy(buf, zig_name);
        if (plat_strlen(buf) > 31) buf[31] = '\0';
        return unit_.getStringInterner().intern(buf);
    }

    /* Check cache first */
    for (size_t i = 0; i < global_names_.length(); ++i) {
        if (plat_strcmp(global_names_[i].zig_name, zig_name) == 0) {
            return global_names_[i].c89_name;
        }
    }

    char final_buf[256];
    bool is_extern = false;
    const char* location = NULL;
    const char* kind = "variable";

    SymbolTable& table = unit_.getSymbolTable(module_name_);
    Symbol* sym = table.lookup(zig_name);
    bool is_local = false;
    if (sym) {
        if (sym->flags & SYMBOL_FLAG_EXTERN) is_extern = true;
        if (sym->flags & SYMBOL_FLAG_LOCAL) is_local = true;
        
        Module* mod = unit_.getModule(sym->module_name);
        if (mod) {
            char rel_path[1024];
            get_relative_path(mod->filename, ".", rel_path, sizeof(rel_path));
            location = unit_.getStringInterner().intern(rel_path);
        }

        if (sym->kind == SYMBOL_FUNCTION) kind = "function";
        else if (sym->kind == SYMBOL_TYPE) kind = "type";
        else if (sym->kind == SYMBOL_MODULE) kind = "module";
    }

    /* Check if it's a known runtime intrinsic that should never be mangled */
    if (plat_strcmp(zig_name, "__bootstrap_print") == 0 ||
        plat_strcmp(zig_name, "__bootstrap_print_int") == 0 ||
        plat_strcmp(zig_name, "__bootstrap_panic") == 0) {
        is_extern = true;
    }

    if (is_extern || is_local) {
        plat_strcpy(final_buf, zig_name);
        if (plat_strlen(final_buf) > 31) final_buf[31] = '\0';
        ::sanitizeForC89(final_buf);
    } else {
        char k_char = 'V';
        if (sym) {
            if (sym->kind == SYMBOL_FUNCTION) k_char = 'F';
            else if (sym->kind == SYMBOL_TYPE) k_char = 'S';
        }
        
        const char* module_path = location;
        const char* mangled = unit_.getNameMangler().mangle(k_char, module_path, zig_name);
        plat_strcpy(final_buf, mangled);
    }

    /* Ensure uniqueness within this translation unit */
    char base_buf[256];
    plat_strcpy(base_buf, final_buf);
    int suffix = 0;
    bool unique = false;

    while (!unique) {
        unique = true;
        // Check against used names in this file
        for (size_t i = 0; i < used_names_.length(); ++i) {
            if (plat_strcmp(used_names_[i], final_buf) == 0) {
                unique = false;
                break;
            }
        }
        // Also check against already registered global names (unlikely to mismatch but good for safety)
        if (unique) {
            for (size_t i = 0; i < global_names_.length(); ++i) {
                if (plat_strcmp(global_names_[i].c89_name, final_buf) == 0) {
                    unique = false;
                    break;
                }
            }
        }

        if (!unique) {
            suffix++;
            char suffix_str[16];
            plat_i64_to_string(suffix, suffix_str, sizeof(suffix_str));
            size_t suffix_len = plat_strlen(suffix_str) + 1; // +1 for underscore
            size_t base_len = plat_strlen(base_buf);

            if (base_len + suffix_len > 31) {
                size_t truncate_at = 31 - suffix_len;
                plat_strncpy(final_buf, base_buf, truncate_at);
                final_buf[truncate_at] = '\0';
                plat_strcat(final_buf, "_");
                plat_strcat(final_buf, suffix_str);
            } else {
                plat_strcpy(final_buf, base_buf);
                plat_strcat(final_buf, "_");
                plat_strcat(final_buf, suffix_str);
            }
        }
    }

    const char* interned = unit_.getStringInterner().intern(final_buf);
    used_names_.append(interned);

    GlobalNameEntry entry;
    entry.zig_name = zig_name;
    entry.c89_name = interned;
    entry.location = location;
    entry.kind = kind;
    global_names_.append(entry);

    return interned;
}

bool C89Emitter::requiresParentheses(const ASTNode* node) const {
    if (!node) return false;
    switch (node->type) {
        /* Postfix and primary expressions (Level 1 in C) */
        case NODE_IDENTIFIER:
        case NODE_INTEGER_LITERAL:
        case NODE_FLOAT_LITERAL:
        case NODE_STRING_LITERAL:
        case NODE_CHAR_LITERAL:
        case NODE_BOOL_LITERAL:
        case NODE_NULL_LITERAL:
        case NODE_PAREN_EXPR:
        case NODE_FUNCTION_CALL:
        case NODE_ARRAY_ACCESS:
        case NODE_MEMBER_ACCESS:
            return false;

        /* Everything else has lower precedence than postfix operators */
        default:
            return true;
    }
}

bool C89Emitter::isSafeWidening(Type* src, Type* dest) const {
    if (!src || !dest) return false;

    /* Integer widening */
    bool src_is_int = (src->kind >= TYPE_I8 && src->kind <= TYPE_U64) || src->kind == TYPE_ISIZE || src->kind == TYPE_USIZE;
    bool dest_is_int = (dest->kind >= TYPE_I8 && dest->kind <= TYPE_U64) || dest->kind == TYPE_ISIZE || dest->kind == TYPE_USIZE;

    if (src_is_int && dest_is_int) {
        bool src_signed = (src->kind == TYPE_I8 || src->kind == TYPE_I16 || src->kind == TYPE_I32 || src->kind == TYPE_I64 || src->kind == TYPE_ISIZE);
        bool dest_signed = (dest->kind == TYPE_I8 || dest->kind == TYPE_I16 || dest->kind == TYPE_I32 || dest->kind == TYPE_I64 || dest->kind == TYPE_ISIZE);

        if (src_signed == dest_signed) {
            /* Size must be non-decreasing */
            return dest->size >= src->size;
        }

        if (!src_signed && dest_signed) {
            /* Unsigned to signed: safe if dest is strictly larger */
            return dest->size > src->size;
        }

        return false;
    }

    /* Float widening */
    if (src->kind == TYPE_F32 || src->kind == TYPE_F64) {
        if (dest->kind == TYPE_F32 || dest->kind == TYPE_F64) {
            return dest->size >= src->size;
        }
    }

    /* Integer to Float conversion */
    if (src_is_int && (dest->kind == TYPE_F32 || dest->kind == TYPE_F64)) {
        return true;
    }

    return false;
}

const char* C89Emitter::getZigTypeName(Type* type) const {
    if (!type) return "unknown";
    switch (type->kind) {
        case TYPE_VOID: return "void";
        case TYPE_BOOL: return "bool";
        case TYPE_I8:   return "i8";
        case TYPE_U8:   return "u8";
        case TYPE_I16:  return "i16";
        case TYPE_U16:  return "u16";
        case TYPE_I32:  return "i32";
        case TYPE_U32:  return "u32";
        case TYPE_I64:  return "i64";
        case TYPE_U64:  return "u64";
        case TYPE_F32:  return "f32";
        case TYPE_F64:  return "f64";
        case TYPE_ISIZE: return "isize";
        case TYPE_USIZE: return "usize";
        case TYPE_C_CHAR: return "c_char";
        default: return "unknown";
    }
}

const char* C89Emitter::getSafeFieldName(const char* name) {
    if (!name) return "z_anon";
    if (isCKeyword(name)) {
        char buf[256];
        plat_strcpy(buf, "z_");
        plat_strcat(buf, name);
        return unit_.getStringInterner().intern(buf);
    }
    return name;
}

const char* C89Emitter::getLoopLabel(int id, const char* suffix) {
    char buf[64];
    char num_buf[16];
    plat_i64_to_string(id, num_buf, sizeof(num_buf));
    plat_strcpy(buf, "__loop_");
    plat_strcat(buf, num_buf);
    plat_strcat(buf, "_");
    plat_strcat(buf, suffix);
    return unit_.getStringInterner().intern(buf);
}

const char* C89Emitter::getLoopStartLabel(int id) {
    return getLoopLabel(id, "start");
}

const char* C89Emitter::getLoopContinueLabel(int id) {
    return getLoopLabel(id, "continue");
}

const char* C89Emitter::getLoopEndLabel(int id) {
    return getLoopLabel(id, "end");
}

bool C89Emitter::captureExpression(const ASTNode* node, char* buf, size_t buf_size) {
    if (!node || !buf || buf_size == 0) return false;

    /* Save current state */
    PlatFile saved_file = output_file_;
    size_t saved_pos = buffer_pos_;
    char saved_last_char = last_char_;
    bool saved_in_type_def = in_type_def_mode_;
    size_t saved_type_def_pos = type_def_pos_;

    /* Redirect to type_def_buffer_ */
    output_file_ = PLAT_INVALID_FILE;
    in_type_def_mode_ = true;
    type_def_pos_ = 0;
    last_char_ = '\0';

    emitExpression(node);

    bool success = true;
    size_t len = type_def_pos_;
    if (len >= buf_size) {
        len = buf_size - 1;
        success = false;
    }
    plat_memcpy(buf, type_def_buffer_, len);
    buf[len] = '\0';

    /* Restore state */
    in_type_def_mode_ = saved_in_type_def;
    type_def_pos_ = saved_type_def_pos;
    buffer_pos_ = saved_pos;
    last_char_ = saved_last_char;
    output_file_ = saved_file;

    return success;
}

C89Emitter::GuardScope::GuardScope(C89Emitter& emitter, const char* guard_name)
    : emitter_(emitter), name_(guard_name), started_(false) {
    emitter_.writeString("#ifndef ");
    emitter_.writeLine(name_);
    emitter_.writeString("#define ");
    emitter_.writeLine(name_);
    started_ = true;
}

C89Emitter::GuardScope::~GuardScope() {
    if (started_) {
        emitter_.writeString("#endif /* ");
        emitter_.writeString(name_);
        emitter_.writeString(" */");
        emitter_.writeLine();
    }
}

const char* C89Emitter::makeTempVarForType(Type* type, const char* prefix, bool emit_decl) {
    const char* name = var_alloc_.generate(prefix);
    if (emit_decl) {
        writeIndent();
        writeDecl(type, name);
    }
    return name;
}

bool C89Emitter::isSimpleLValue(const ASTNode* node) const {
    if (!node) return false;

    /* Unwrap parentheses */
    while (node && node->type == NODE_PAREN_EXPR) {
        node = node->as.paren_expr.expr;
    }

    if (!node) return false;

    return node->type == NODE_IDENTIFIER || node->type == NODE_VAR_DECL;
}

const char* C89Emitter::getMangledTypeName(Type* type) {
    if (!type) return "void";

    char buf[1024];
    char* cur = buf;
    size_t rem = sizeof(buf);

    switch (type->kind) {
        case TYPE_VOID: safe_append(cur, rem, "void"); break;
        case TYPE_BOOL: safe_append(cur, rem, "bool"); break;
        case TYPE_I8:   safe_append(cur, rem, "i8"); break;
        case TYPE_U8:   safe_append(cur, rem, "u8"); break;
        case TYPE_I16:  safe_append(cur, rem, "i16"); break;
        case TYPE_U16:  safe_append(cur, rem, "u16"); break;
        case TYPE_I32:  safe_append(cur, rem, "i32"); break;
        case TYPE_U32:  safe_append(cur, rem, "u32"); break;
        case TYPE_I64:  safe_append(cur, rem, "i64"); break;
        case TYPE_U64:  safe_append(cur, rem, "u64"); break;
        case TYPE_F32:  safe_append(cur, rem, "f32"); break;
        case TYPE_F64:  safe_append(cur, rem, "f64"); break;
        case TYPE_ISIZE: safe_append(cur, rem, "isize"); break;
        case TYPE_USIZE: safe_append(cur, rem, "usize"); break;
        case TYPE_C_CHAR: safe_append(cur, rem, "c_char"); break;
        case TYPE_POINTER:
            safe_append(cur, rem, "Ptr_");
            safe_append(cur, rem, getMangledTypeName(type->as.pointer.base));
            break;
        case TYPE_SLICE:
            safe_append(cur, rem, "Slice_");
            safe_append(cur, rem, getMangledTypeName(type->as.slice.element_type));
            break;
        case TYPE_ERROR_UNION:
            safe_append(cur, rem, "ErrorUnion_");
            safe_append(cur, rem, getMangledTypeName(type->as.error_union.payload));
            break;
        case TYPE_OPTIONAL:
            safe_append(cur, rem, "Optional_");
            safe_append(cur, rem, getMangledTypeName(type->as.optional.payload));
            break;
        case TYPE_ERROR_SET:
            safe_append(cur, rem, "ErrorSet");
            break;
        case TYPE_ARRAY: {
            safe_append(cur, rem, "Arr_");
            char size_buf[32];
            plat_u64_to_string(type->as.array.size, size_buf, sizeof(size_buf));
            safe_append(cur, rem, size_buf);
            safe_append(cur, rem, "_");
            safe_append(cur, rem, getMangledTypeName(type->as.array.element_type));
            break;
        }
        case TYPE_FUNCTION:
        case TYPE_FUNCTION_POINTER: {
            safe_append(cur, rem, "Fn_");
            Type* ret = (type->kind == TYPE_FUNCTION) ? type->as.function.return_type : type->as.function_pointer.return_type;
            safe_append(cur, rem, getMangledTypeName(ret));
            DynamicArray<Type*>* params = (type->kind == TYPE_FUNCTION) ? type->as.function.params : type->as.function_pointer.param_types;
            if (params) {
                for (size_t i = 0; i < params->length(); ++i) {
                    safe_append(cur, rem, "_");
                    safe_append(cur, rem, getMangledTypeName((*params)[i]));
                }
            }
            break;
        }
        case TYPE_PLACEHOLDER:
            if (type->c_name) {
                safe_append(cur, rem, type->c_name);
            } else {
                safe_append(cur, rem, type->as.placeholder.name);
            }
            break;
        case TYPE_STRUCT:
        case TYPE_UNION:
        case TYPE_ENUM: {
            if (type->c_name) {
                safe_append(cur, rem, type->c_name);
            } else {
                safe_append(cur, rem, unit_.getNameMangler().mangleType(type));
            }
            break;
        }
        default:
            safe_append(cur, rem, "unknown");
            break;
    }

    return unit_.getStringInterner().intern(buf);
}

void C89Emitter::emitEscapedByte(unsigned char c, bool is_char_literal) {
    switch (c) {
        case '\a': write("\\a", 2); return;
        case '\b': write("\\b", 2); return;
        case '\f': write("\\f", 2); return;
        case '\n': write("\\n", 2); return;
        case '\r': write("\\r", 2); return;
        case '\t': write("\\t", 2); return;
        case '\v': write("\\v", 2); return;
        case '\\': write("\\\\", 2); return;
        case '\'':
            if (is_char_literal) write("\\'", 2);
            else write("'", 1);
            return;
        case '\"':
            if (!is_char_literal) write("\\\"", 2);
            else write("\"", 1);
            return;
        default:
            if (c >= 32 && c <= 126) {
                char ch = (char)c;
                write(&ch, 1);
            } else {
                char buf[8];
                /* Use octal escape \ooo (three digits zero-padded) */
                buf[0] = '\\';
                buf[1] = (char)((c >> 6) & 7) + '0';
                buf[2] = (char)((c >> 3) & 7) + '0';
                buf[3] = (char)(c & 7) + '0';
                buf[4] = '\0';
                writeString(buf);
            }
    }
}

void C89Emitter::emitOptionalWrapping(const char* target_name, const ASTNode* target_node, Type* target_type, const ASTNode* rvalue) {
    if (!target_type) target_type = target_node ? target_node->resolved_type : NULL;
    Type* source_type = rvalue->resolved_type;

    if (allPathsExit(rvalue)) {
        emitStatement(rvalue);
        return;
    }

    bool needs_temporary = target_node && !isSimpleLValue(target_node);
    const char* lval_ptr = NULL;

    if (needs_temporary) {
        lval_ptr = var_alloc_.generate("opt_lval_tmp");
        writeIndent();
        writeString("{\n");
        indent();
        writeIndent();
        Type* ptr_type = createPointerType(arena_, target_type, false, false, &unit_.getTypeInterner());
        emitType(ptr_type, lval_ptr);
        writeString(" = &(");
        emitExpression(target_node);
        writeString(");\n");
    }

    if (source_type->kind == TYPE_NULL) {
        writeIndent();
        if (needs_temporary) {
            writeString(lval_ptr);
            writeString("->has_value = 0;\n");
        } else {
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            writeString(".has_value = 0;\n");
        }
    } else {
        if (target_type->as.optional.payload->kind != TYPE_VOID) {
            if (needs_temporary) {
                char payload_lval[512];
                plat_strcpy(payload_lval, lval_ptr);
                plat_strcat(payload_lval, "->value");
                emitAssignmentWithLifting(payload_lval, NULL, rvalue, target_type->as.optional.payload);
            } else {
                char lval_buf[512];
                if (target_name) {
                    plat_strcpy(lval_buf, target_name);
                } else {
                    captureExpression(target_node, lval_buf, sizeof(lval_buf));
                }

                char payload_lval[512];
                char* cur = payload_lval;
                size_t rem = sizeof(payload_lval);
                safe_append(cur, rem, lval_buf);
                safe_append(cur, rem, ".value");
                emitAssignmentWithLifting(payload_lval, NULL, rvalue, target_type->as.optional.payload);
            }
        } else {
            emitAssignmentWithLifting(NULL, NULL, rvalue, NULL);
        }

        writeIndent();
        if (needs_temporary) {
            writeString(lval_ptr);
            writeString("->has_value = 1;\n");
        } else {
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            writeString(".has_value = 1;\n");
        }
    }

    if (needs_temporary) {
        dedent();
        writeIndent();
        writeString("}\n");
    }
}

void C89Emitter::emitOptionalWrapping(const char* target_name, const ASTNode* target_node, Type* target_type, const char* source_expr, Type* source_type) {
    if (!target_type) target_type = target_node ? target_node->resolved_type : NULL;

    bool needs_temporary = target_node && !isSimpleLValue(target_node);
    const char* lval_ptr = NULL;

    if (needs_temporary) {
        lval_ptr = var_alloc_.generate("opt_lval_tmp");
        writeIndent();
        writeString("{\n");
        indent();
        writeIndent();
        Type* ptr_type = createPointerType(arena_, target_type, false, false, &unit_.getTypeInterner());
        emitType(ptr_type, lval_ptr);
        writeString(" = &(");
        emitExpression(target_node);
        writeString(");\n");
    }

    if (source_type->kind == TYPE_NULL) {
        writeIndent();
        if (needs_temporary) {
            writeString(lval_ptr);
            writeString("->has_value = 0;\n");
        } else {
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            writeString(".has_value = 0;\n");
        }
    } else {
        writeIndent();
        if (needs_temporary) {
            writeString(lval_ptr);
            if (target_type->as.optional.payload->kind != TYPE_VOID) {
                writeString("->value = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            }
            writeIndent();
            writeString(lval_ptr);
            writeString("->has_value = 1;\n");
        } else {
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            if (target_type->as.optional.payload->kind != TYPE_VOID) {
                writeString(".value = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            }
            writeIndent();
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            writeString(".has_value = 1;\n");
        }
    }

    if (needs_temporary) {
        dedent();
        writeIndent();
        writeString("}\n");
    }
}

void C89Emitter::emitErrorUnionWrapping(const char* target_name, const ASTNode* target_node, Type* target_type, const ASTNode* rvalue) {
    if (!target_type) target_type = target_node ? target_node->resolved_type : NULL;
    Type* source_type = rvalue->resolved_type;

    if (allPathsExit(rvalue)) {
        emitStatement(rvalue);
        return;
    }

    bool needs_temporary = target_node && !isSimpleLValue(target_node);
    const char* lval_ptr = NULL;

    if (needs_temporary) {
        lval_ptr = var_alloc_.generate("err_lval_tmp");
        writeIndent();
        writeString("{\n");
        indent();
        writeIndent();
        Type* ptr_type = createPointerType(arena_, target_type, false, false, &unit_.getTypeInterner());
        emitType(ptr_type, lval_ptr);
        writeString(" = &(");
        emitExpression(target_node);
        writeString(");\n");
    }

    if (source_type->kind == TYPE_ERROR_SET) {
        writeIndent();
        if (target_type->as.error_union.payload->kind != TYPE_VOID) {
            if (needs_temporary) {
                writeString(lval_ptr);
                writeString("->is_error = 1; ");
                writeString(lval_ptr);
                writeString("->data.err = ");
                emitExpression(rvalue);
                endStmt();
            } else {
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".is_error = 1; ");
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".data.err = ");
                emitExpression(rvalue);
                endStmt();
            }
        } else {
            if (needs_temporary) {
                writeString(lval_ptr);
                writeString("->is_error = 1; ");
                writeString(lval_ptr);
                writeString("->err = ");
                emitExpression(rvalue);
                endStmt();
            } else {
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".is_error = 1; ");
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".err = ");
                emitExpression(rvalue);
                endStmt();
            }
        }
    } else {
        if (target_type->as.error_union.payload->kind != TYPE_VOID) {
            if (needs_temporary) {
                char payload_lval[512];
                plat_strcpy(payload_lval, lval_ptr);
                plat_strcat(payload_lval, "->data.payload");
                emitAssignmentWithLifting(payload_lval, NULL, rvalue, target_type->as.error_union.payload);
            } else {
                char lval_buf[512];
                if (target_name) {
                    plat_strcpy(lval_buf, target_name);
                } else {
                    captureExpression(target_node, lval_buf, sizeof(lval_buf));
                }
                char payload_lval[512];
                char* cur = payload_lval;
                size_t rem = sizeof(payload_lval);
                safe_append(cur, rem, lval_buf);
                safe_append(cur, rem, ".data.payload");
                emitAssignmentWithLifting(payload_lval, NULL, rvalue, target_type->as.error_union.payload);
            }
        } else {
            emitAssignmentWithLifting(NULL, NULL, rvalue, NULL);
        }
        writeIndent();
        if (needs_temporary) {
            writeString(lval_ptr);
            writeString("->is_error = 0;\n");
        } else {
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            writeString(".is_error = 0;\n");
        }
    }

    if (needs_temporary) {
        dedent();
        writeIndent();
        writeString("}\n");
    }
}

void C89Emitter::emitErrorUnionWrapping(const char* target_name, const ASTNode* target_node, Type* target_type, const char* source_expr, Type* source_type) {
    if (!target_type) target_type = target_node ? target_node->resolved_type : NULL;

    bool needs_temporary = target_node && !isSimpleLValue(target_node);
    const char* lval_ptr = NULL;

    if (needs_temporary) {
        lval_ptr = var_alloc_.generate("err_lval_tmp");
        writeIndent();
        writeString("{\n");
        indent();
        writeIndent();
        Type* ptr_type = createPointerType(arena_, target_type, false, false, &unit_.getTypeInterner());
        emitType(ptr_type, lval_ptr);
        writeString(" = &(");
        emitExpression(target_node);
        writeString(");\n");
    }

    if (source_type->kind == TYPE_ERROR_SET) {
        writeIndent();
        if (target_type->as.error_union.payload->kind != TYPE_VOID) {
            if (needs_temporary) {
                writeString(lval_ptr);
                writeString("->is_error = 1; ");
                writeString(lval_ptr);
                writeString("->data.err = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            } else {
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".is_error = 1; ");
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".data.err = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            }
        } else {
            if (needs_temporary) {
                writeString(lval_ptr);
                writeString("->is_error = 1; ");
                writeString(lval_ptr);
                writeString("->err = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            } else {
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".is_error = 1; ");
                if (target_name) {
                    writeString(target_name);
                } else {
                    emitExpression(target_node);
                }
                writeString(".err = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            }
        }
    } else {
        writeIndent();
        if (needs_temporary) {
            writeString(lval_ptr);
            if (target_type->as.error_union.payload->kind != TYPE_VOID) {
                writeString("->data.payload = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            }
            writeIndent();
            writeString(lval_ptr);
            writeString("->is_error = 0;\n");
        } else {
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            if (target_type->as.error_union.payload->kind != TYPE_VOID) {
                writeString(".data.payload = ");
                if (source_expr) writeString(source_expr); else writeString("0");
                endStmt();
            }
            writeIndent();
            if (target_name) {
                writeString(target_name);
            } else {
                emitExpression(target_node);
            }
            writeString(".is_error = 0;\n");
        }
    }

    if (needs_temporary) {
        dedent();
        writeIndent();
        writeString("}\n");
    }
}

void C89Emitter::emitDefersForScopeExit(int target_label_id) {
    for (int i = (int)defer_stack_.length() - 1; i >= 0; --i) {
        DeferScope* scope = defer_stack_[i];
        if (!scope) continue;

        /* Regular defers */
        for (int j = (int)scope->defers.length() - 1; j >= 0; --j) {
            if (scope->defers[j] && scope->defers[j]->statement) {
                emitStatement(scope->defers[j]->statement);
            }
        }

        /* Errdefers */
        if (scope->err_defers.length() > 0 && current_err_flag_) {
            writeIndent();
            writeString("if (");
            writeString(current_err_flag_);
            writeString(") {\n");
            {
                IndentScope errdefer_indent(*this);
                for (int j = (int)scope->err_defers.length() - 1; j >= 0; --j) {
                    if (scope->err_defers[j] && scope->err_defers[j]->statement) {
                        emitStatement(scope->err_defers[j]->statement);
                    }
                }
            }
            writeIndent();
            writeString("}\n");
        }

        if (target_label_id != -1 && scope->label_id == target_label_id) {
            break;
        }
    }
}

void C89Emitter::emitBreak(const ASTBreakStmtNode* node) {
    writeIndent();
    if (defer_stack_.length() > 0) {
        writeString("/* defers for break */\n");
        emitDefersForScopeExit(node->target_label_id);
        writeIndent();
    }

    int target_id = node->target_label_id;
    if (target_id == -1 && loop_id_stack_.length() > 0) {
        target_id = loop_id_stack_.back();
    }

    bool uses_labels = false;
    if (target_id >= 0 && target_id < 1024) {
        uses_labels = loop_uses_labels_[target_id];
    }

    if (node->label || uses_labels) {
        writeKeyword(KW_GOTO);
        writeString(getLoopEndLabel(target_id));
        endStmt();
    } else {
        writeString("break;\n");
    }
}

void C89Emitter::emitContinue(const ASTContinueStmtNode* node) {
    writeIndent();
    if (defer_stack_.length() > 0) {
        writeString("/* defers for continue */\n");
        emitDefersForScopeExit(node->target_label_id);
        writeIndent();
    }

    int target_id = node->target_label_id;
    if (target_id == -1 && loop_id_stack_.length() > 0) {
        target_id = loop_id_stack_.back();
    }

    bool uses_labels = false;
    if (target_id >= 0 && target_id < 1024) {
        uses_labels = loop_uses_labels_[target_id];
    }

    if (node->label || uses_labels) {
        /* Set has_continue flag for the target loop */
        if (target_id >= 0 && loop_id_stack_.length() > 0) {
            for (int i = (int)loop_id_stack_.length() - 1; i >= 0; --i) {
                if (loop_id_stack_[i] == target_id) {
                    loop_has_continue_[i] = true;
                    break;
                }
            }
        }
        writeKeyword(KW_GOTO);
        writeString(getLoopContinueLabel(target_id));
        endStmt();
    } else {
        writeString("continue;\n");
    }
}

void C89Emitter::validateEmission() {
    if (!debug_trace_) return;
    plat_printf_debug("[CODEGEN] Validation: %d declarations emitted in function %s\n",
                     (int)emitted_decls_.length(), current_fn_name_ ? current_fn_name_ : "unknown");
}

void C89Emitter::emitReturn(const ASTReturnStmtNode* node) {
    if (!node) return;

    bool has_defers = false;
    for (size_t i = 0; i < defer_stack_.length(); ++i) {
        if (defer_stack_[i]->defers.length() > 0 || defer_stack_[i]->err_defers.length() > 0) {
            has_defers = true;
            break;
        }
    }

    Type* source_type = (node->expression && node->expression->resolved_type) ? node->expression->resolved_type : get_g_type_void();
    bool needs_wrapping = (current_fn_ret_type_ && current_fn_ret_type_->kind == TYPE_ERROR_UNION &&
                           source_type && source_type->kind != TYPE_ERROR_UNION);
    bool needs_opt_wrapping = (current_fn_ret_type_ && current_fn_ret_type_->kind == TYPE_OPTIONAL &&
                               source_type && source_type->kind != TYPE_OPTIONAL);
    if (has_defers || needs_wrapping || needs_opt_wrapping || is_main_function_ ||
        (node->expression && node->expression->type == NODE_STRUCT_INITIALIZER)) {
        writeIndent();
        writeString("{\n");
        {
            IndentScope scope_indent(*this);

            if (current_fn_ret_type_->kind != TYPE_VOID) {
                writeIndent();
                emitType(current_fn_ret_type_, "__return_val");
                writeString(" = {0};\n");

                if (node->expression) {
                    emitAssignmentWithLifting("__return_val", NULL, node->expression, current_fn_ret_type_);
                }

                if (current_err_flag_) {
                    writeIndent();
                    writeString("if (__return_val.is_error) ");
                    writeString(current_err_flag_);
                    writeString(" = 1;\n");
                }

                emitDefersForScopeExit(-1);

                writeIndent();
                if (is_main_function_) {
                    if (current_fn_ret_type_->kind == TYPE_ERROR_UNION) {
                        writeString("return __return_val.is_error ? __return_val.err : 0;\n");
                    } else if (current_fn_ret_type_->kind == TYPE_OPTIONAL) {
                        writeString("return __return_val.has_value ? 0 : 1;\n");
                    } else {
                        writeString("return (int)__return_val;\n");
                    }
                } else {
                    writeString("return __return_val;\n");
                }
            } else {
                if (node->expression) {
                    emitAssignmentWithLifting(NULL, NULL, node->expression, NULL);
                }
                emitDefersForScopeExit(-1);
                writeIndent();
                if (is_main_function_) {
                    writeString("return 0;\n");
                } else {
                    writeString("return;\n");
                }
            }
        }
        writeIndent();
        writeString("}\n");
    } else {
        writeIndent();
        if (node->expression) {
            writeKeyword(KW_RETURN);
            emitExpression(node->expression);
            endStmt();
        } else {
            if (is_main_function_) {
                writeString("return 0;\n");
            } else {
                writeString("return;\n");
            }
        }
    }
}
