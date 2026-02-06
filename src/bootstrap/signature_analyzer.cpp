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
            for (size_t i = 0; i < stmts->length(); ++i) {
                visit((*stmts)[i]);
            }
            break;
        }

        case NODE_FN_DECL:
            visitFnDecl(node->as.fn_decl);
            // Also visit the body in case there are nested functions
            visit(node->as.fn_decl->body);
            break;

        case NODE_IF_STMT:
            visit(node->as.if_stmt->then_block);
            if (node->as.if_stmt->else_block) {
                visit(node->as.if_stmt->else_block);
            }
            break;

        case NODE_WHILE_STMT:
            visit(node->as.while_stmt.body);
            break;

        case NODE_FOR_STMT:
            visit(node->as.for_stmt->body);
            break;

        case NODE_STRUCT_DECL: {
            DynamicArray<ASTNode*>* fields = node->as.struct_decl->fields;
            if (fields) {
                for (size_t i = 0; i < fields->length(); ++i) {
                    visit((*fields)[i]);
                }
            }
            break;
        }

        case NODE_UNION_DECL: {
            DynamicArray<ASTNode*>* fields = node->as.union_decl->fields;
            if (fields) {
                for (size_t i = 0; i < fields->length(); ++i) {
                    visit((*fields)[i]);
                }
            }
            break;
        }

        case NODE_ENUM_DECL: {
            DynamicArray<ASTNode*>* fields = node->as.enum_decl->fields;
            if (fields) {
                for (size_t i = 0; i < fields->length(); ++i) {
                    visit((*fields)[i]);
                }
            }
            break;
        }

        case NODE_VAR_DECL:
            if (node->as.var_decl->initializer) {
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
    if (!isParameterCountValid(node->params->length())) {
        char buffer[256];
        char num_buf[21];
        simple_itoa((long)node->params->length(), num_buf, sizeof(num_buf));

        char* cur = buffer;
        size_t rem = sizeof(buffer);
        safe_append(cur, rem, "Function '");
        safe_append(cur, rem, node->name);
        safe_append(cur, rem, "' has too many parameters (");
        safe_append(cur, rem, num_buf);
        safe_append(cur, rem, "), maximum is 4 for C89 compatibility");

        SourceLocation loc = node->body ? node->body->loc : SourceLocation();
        error_handler_.report(ERR_TYPE_MISMATCH, loc, buffer, unit_.getArena());
        invalid_count_++;
    }

    // 2. Check each parameter type
    for (size_t i = 0; i < node->params->length(); ++i) {
        ASTParamDeclNode* param = (*node->params)[i];
        if (param->type && param->type->resolved_type) {
            if (!isParameterTypeValid(param->type->resolved_type, param->type->loc)) {
                invalid_count_++;
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

bool SignatureAnalyzer::isParameterCountValid(size_t count) {
    return count <= 4;
}

bool SignatureAnalyzer::isReturnTypeValid(Type* type, SourceLocation loc) {
    if (!type) return true;

    switch (type->kind) {
        case TYPE_VOID:
            return true;

        case TYPE_BOOL:
        case TYPE_I8: case TYPE_I16: case TYPE_I32: case TYPE_I64:
        case TYPE_U8: case TYPE_U16: case TYPE_U32: case TYPE_U64:
        case TYPE_ISIZE: case TYPE_USIZE:
        case TYPE_F32: case TYPE_F64:
        case TYPE_ENUM:
            return true;

        case TYPE_POINTER:
            // Check for multi-level pointers
            if (type->as.pointer.base && type->as.pointer.base->kind == TYPE_POINTER) {
                error_handler_.report(ERR_TYPE_MISMATCH, loc, "Multi-level pointers in return types are not supported in C89 mode", unit_.getArena());
                return false;
            }
            return true;

        case TYPE_STRUCT:
            // Check struct size for return
            if (type->size > 64) {
                error_handler_.reportWarning(WARN_EXTRACTION_LARGE_PAYLOAD, loc, "Struct return size > 64 bytes may be problematic for MSVC 6.0");
            }
            return true;

        case TYPE_ERROR_UNION:
            error_handler_.report(ERR_TYPE_MISMATCH, loc, "Error union return type not supported in C89", unit_.getArena());
            return false;

        case TYPE_ERROR_SET:
            error_handler_.report(ERR_TYPE_MISMATCH, loc, "Error set return type not supported in C89", unit_.getArena());
            return false;

        default:
            error_handler_.report(ERR_TYPE_MISMATCH, loc, "Non-C89 return type not supported", unit_.getArena());
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
        case TYPE_ISIZE: case TYPE_USIZE:
        case TYPE_F32: case TYPE_F64:
        case TYPE_ENUM:
            return true;

        case TYPE_POINTER:
            // Check for multi-level pointers
            if (type->as.pointer.base && type->as.pointer.base->kind == TYPE_POINTER) {
                error_handler_.report(ERR_TYPE_MISMATCH, loc, "Multi-level pointers in parameters are not supported in C89 mode", unit_.getArena());
                return false;
            }
            return true;

        case TYPE_STRUCT:
            return true;

        case TYPE_ARRAY:
            // Arrays in parameters treated as pointers
            error_handler_.reportWarning(WARN_ARRAY_PARAMETER, loc, "Array parameter will be treated as a pointer in C89");
            return true;

        case TYPE_ERROR_UNION:
            error_handler_.report(ERR_TYPE_MISMATCH, loc, "Error union type in parameter not supported in C89", unit_.getArena());
            return false;

        case TYPE_ERROR_SET:
            error_handler_.report(ERR_TYPE_MISMATCH, loc, "Error set type in parameter not supported in C89", unit_.getArena());
            return false;

        default:
            error_handler_.report(ERR_TYPE_MISMATCH, loc, "Non-C89 type in parameter not supported", unit_.getArena());
            return false;
    }
}
