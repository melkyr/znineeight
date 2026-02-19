#include "signature_analyzer.hpp"
#include "compilation_unit.hpp"
#include "error_handler.hpp"
#include "type_system.hpp"
#include "utils.hpp"

SignatureAnalyzer::SignatureAnalyzer(CompilationUnit& unit)
    : unit_(unit), error_handler_(unit.getErrorHandler()), invalid_count_(0) {
}

void SignatureAnalyzer::analyze(ASTNode* root) {
    visit(root);
}

void SignatureAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_BLOCK_STMT: {
            DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
            if (stmts) {
                for (size_t i = 0; i < stmts->length(); ++i) {
                    visit((*stmts)[i]);
                }
            }
            break;
        }

        case NODE_FN_DECL:
            if (node->as.fn_decl) {
                visitFnDecl(node->as.fn_decl);
                // Also visit the body in case there are nested functions
                visit(node->as.fn_decl->body);
            }
            break;

        case NODE_IF_STMT:
            if (node->as.if_stmt) {
                visit(node->as.if_stmt->then_block);
                if (node->as.if_stmt->else_block) {
                    visit(node->as.if_stmt->else_block);
                }
            }
            break;

        case NODE_WHILE_STMT:
            visit(node->as.while_stmt.body);
            break;

        case NODE_FOR_STMT:
            if (node->as.for_stmt) {
                visit(node->as.for_stmt->body);
            }
            break;

        case NODE_STRUCT_DECL:
            if (node->as.struct_decl) {
                DynamicArray<ASTNode*>* fields = node->as.struct_decl->fields;
                if (fields) {
                    for (size_t i = 0; i < fields->length(); ++i) {
                        visit((*fields)[i]);
                    }
                }
            }
            break;

        case NODE_UNION_DECL:
            if (node->as.union_decl) {
                DynamicArray<ASTNode*>* fields = node->as.union_decl->fields;
                if (fields) {
                    for (size_t i = 0; i < fields->length(); ++i) {
                        visit((*fields)[i]);
                    }
                }
            }
            break;

        case NODE_ENUM_DECL:
            if (node->as.enum_decl) {
                DynamicArray<ASTNode*>* fields = node->as.enum_decl->fields;
                if (fields) {
                    for (size_t i = 0; i < fields->length(); ++i) {
                        visit((*fields)[i]);
                    }
                }
            }
            break;

        case NODE_VAR_DECL:
            if (node->as.var_decl && node->as.var_decl->initializer) {
                visit(node->as.var_decl->initializer);
            }
            break;

        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;

        default:
            break;
    }
}

void SignatureAnalyzer::visitFnDecl(ASTFnDeclNode* node) {
    if (!node) return;

    // 1. Check parameter count
    if (node->params && node->params->length() > 4) {
        char buffer[256];
        char num_buf[21];
        plat_i64_to_string(node->params->length(), num_buf, sizeof(num_buf));

        char* cur = buffer;
        size_t rem = sizeof(buffer);
        safe_append(cur, rem, "Function '");
        safe_append(cur, rem, node->name ? node->name : "<anonymous>");
        safe_append(cur, rem, "' has too many parameters (");
        safe_append(cur, rem, num_buf);
        safe_append(cur, rem, "), maximum is 4 for bootstrap compiler compatibility");

        SourceLocation loc = node->body ? node->body->loc : SourceLocation();
        error_handler_.report(ERR_NON_C89_FEATURE, loc, buffer, unit_.getArena());
        invalid_count_++;
    }

    // 2. Check each parameter type
    if (node->params) {
        for (size_t i = 0; i < node->params->length(); ++i) {
            ASTParamDeclNode* param = (*node->params)[i];
            if (param && param->type && param->type->resolved_type) {
                if (!isParameterTypeValid(param->type->resolved_type, param->type->loc)) {
                    invalid_count_++;
                }
            }
        }
    }

    // 3. Check return type
    if (node->return_type && node->return_type->resolved_type) {
        if (!isReturnTypeValid(node->return_type->resolved_type, node->return_type->loc)) {
            invalid_count_++;
        }
    }
}


bool SignatureAnalyzer::isReturnTypeValid(Type* type, SourceLocation loc) {
    if (!type) return true;

    switch (type->kind) {
        case TYPE_VOID:
            return true;

        case TYPE_BOOL:
        case TYPE_I8: case TYPE_I16: case TYPE_I32: case TYPE_I64:
        case TYPE_U8: case TYPE_U16: case TYPE_U32: case TYPE_U64:
        case TYPE_F32: case TYPE_F64:
        case TYPE_ENUM:
            return true;

        case TYPE_ISIZE: case TYPE_USIZE:
            return true;

        case TYPE_POINTER:
        case TYPE_FUNCTION_POINTER:
            return true;

        case TYPE_STRUCT:
        case TYPE_UNION:
            // Check struct/union size for return
            if (type->size > 64) {
                error_handler_.reportWarning(WARN_EXTRACTION_LARGE_PAYLOAD, loc, "Struct return size > 64 bytes may be problematic for MSVC 6.0");
            }
            return true;

        case TYPE_ERROR_UNION:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Error union return type not supported in bootstrap compiler", unit_.getArena());
            return false;

        case TYPE_ERROR_SET:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Error set return type not supported in bootstrap compiler", unit_.getArena());
            return false;

        case TYPE_OPTIONAL:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Optional types (?T) are not supported in bootstrap compiler. Consider using a nullable pointer (*T) or separate boolean flag.", unit_.getArena());
            return false;

        default:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Non-C89 return type not supported", unit_.getArena());
            return false;
    }
}

bool SignatureAnalyzer::isParameterTypeValid(Type* type, SourceLocation loc) {
    if (!type) return true;

    switch (type->kind) {
        case TYPE_VOID:
            error_handler_.report(ERR_TYPE_MISMATCH, loc, "Parameter cannot be 'void'", unit_.getArena());
            return false;

        case TYPE_BOOL:
        case TYPE_I8: case TYPE_I16: case TYPE_I32: case TYPE_I64:
        case TYPE_U8: case TYPE_U16: case TYPE_U32: case TYPE_U64:
        case TYPE_F32: case TYPE_F64:
        case TYPE_ENUM:
            return true;

        case TYPE_ISIZE: case TYPE_USIZE:
            return true;

        case TYPE_POINTER:
        case TYPE_FUNCTION_POINTER:
            return true;

        case TYPE_STRUCT:
        case TYPE_UNION:
            return true;

        case TYPE_ARRAY:
            // Arrays in parameters treated as pointers
            error_handler_.reportWarning(WARN_ARRAY_PARAMETER, loc, "Array parameter will be treated as a pointer in C89");
            return true;

        case TYPE_ERROR_UNION:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Error union type in parameter not supported in bootstrap compiler", unit_.getArena());
            return false;

        case TYPE_ERROR_SET:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Error set type in parameter not supported in bootstrap compiler", unit_.getArena());
            return false;

        case TYPE_OPTIONAL:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Optional types (?T) are not supported in bootstrap compiler. Consider using a nullable pointer (*T) or separate boolean flag.", unit_.getArena());
            return false;

        default:
            error_handler_.report(ERR_NON_C89_FEATURE, loc, "Non-C89 type in parameter not supported", unit_.getArena());
            return false;
    }
}
