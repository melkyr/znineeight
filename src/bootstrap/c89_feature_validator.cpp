#include "c89_feature_validator.hpp"
#include "ast.hpp"
#include "ast_utils.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"
#include "utils.hpp"
#include <cstdlib> // For abort()

C89FeatureValidator::C89FeatureValidator(CompilationUnit& unit)
    : unit(unit), error_found_(false), try_expression_depth_(0), current_parent_(NULL) {}

void C89FeatureValidator::validate(ASTNode* node) {
    visit(node);
    if (error_found_) {
        unit.getErrorHandler().printErrors();
        abort();
    }
}

void C89FeatureValidator::reportNonC89Feature(SourceLocation location, const char* message, bool copy_message) {
    if (copy_message) {
        unit.getErrorHandler().report(ERR_NON_C89_FEATURE, location, message, unit.getArena());
    } else {
        unit.getErrorHandler().report(ERR_NON_C89_FEATURE, location, message);
    }
    error_found_ = true;
}

void C89FeatureValidator::fatalError(SourceLocation location, const char* message) {
    reportNonC89Feature(location, message);
}

static bool isErrorType(Type* type) {
    if (!type) return false;
    return type->kind == TYPE_ERROR_UNION || type->kind == TYPE_ERROR_SET;
}

static bool hasComptimeParams(ASTFnDeclNode* node) {
    if (!node->params) return false;
    for (size_t i = 0; i < node->params->length(); ++i) {
        if ((*node->params)[i]->is_comptime) return true;
    }
    return false;
}

void C89FeatureValidator::visit(ASTNode* node) {
    if (!node) {
        return;
    }

    ASTNode* prev_parent = current_parent_;

    switch (node->type) {
        case NODE_ARRAY_TYPE:
            visitArrayType(node);
            break;
        case NODE_ERROR_UNION_TYPE:
            visitErrorUnionType(node);
            break;
        case NODE_OPTIONAL_TYPE:
            visitOptionalType(node);
            break;
        case NODE_TRY_EXPR:
            visitTryExpr(node);
            break;
        case NODE_CATCH_EXPR:
            visitCatchExpr(node);
            break;
        case NODE_ORELSE_EXPR:
            visitOrelseExpr(node);
            break;
        case NODE_ERROR_SET_DEFINITION:
            visitErrorSetDefinition(node);
            break;
        case NODE_ERROR_SET_MERGE:
            visitErrorSetMerge(node);
            break;
        case NODE_IMPORT_STMT:
            visitImportStmt(node);
            break;
        case NODE_FUNCTION_CALL:
            visitFunctionCall(node);
            break;

        // --- Recursive traversal for other node types ---
        case NODE_BINARY_OP:
            current_parent_ = node;
            visit(node->as.binary_op->left);
            visit(node->as.binary_op->right);
            current_parent_ = prev_parent;
            break;
        case NODE_UNARY_OP:
            current_parent_ = node;
            visit(node->as.unary_op.operand);
            current_parent_ = prev_parent;
            break;
        case NODE_BLOCK_STMT:
            current_parent_ = node;
            for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                visit((*node->as.block_stmt.statements)[i]);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_IF_STMT:
            current_parent_ = node;
            visit(node->as.if_stmt->condition);
            visit(node->as.if_stmt->then_block);
            if (node->as.if_stmt->else_block) {
                visit(node->as.if_stmt->else_block);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_WHILE_STMT:
            current_parent_ = node;
            visit(node->as.while_stmt.condition);
            visit(node->as.while_stmt.body);
            current_parent_ = prev_parent;
            break;
        case NODE_RETURN_STMT:
            current_parent_ = node;
            if (node->as.return_stmt.expression) {
                visit(node->as.return_stmt.expression);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_VAR_DECL:
            current_parent_ = node;
            visit(node->as.var_decl->type);
            if (node->as.var_decl->initializer) {
                visit(node->as.var_decl->initializer);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ASSIGNMENT:
            current_parent_ = node;
            visit(node->as.assignment->lvalue);
            visit(node->as.assignment->rvalue);
            current_parent_ = prev_parent;
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            current_parent_ = node;
            visit(node->as.compound_assignment->lvalue);
            visit(node->as.compound_assignment->rvalue);
            current_parent_ = prev_parent;
            break;
        case NODE_FN_DECL:
            visitFnDecl(node);
            break;
        case NODE_STRUCT_DECL:
            current_parent_ = node;
            for (size_t i = 0; i < node->as.struct_decl->fields->length(); ++i) {
                visit((*node->as.struct_decl->fields)[i]);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_UNION_DECL:
            current_parent_ = node;
            for (size_t i = 0; i < node->as.union_decl->fields->length(); ++i) {
                visit((*node->as.union_decl->fields)[i]);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ENUM_DECL:
            current_parent_ = node;
            if (node->as.enum_decl->backing_type) {
                visit(node->as.enum_decl->backing_type);
            }
            for (size_t i = 0; i < node->as.enum_decl->fields->length(); ++i) {
                visit((*node->as.enum_decl->fields)[i]);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_STRUCT_FIELD:
            current_parent_ = node;
            visit(node->as.struct_field->type);
            current_parent_ = prev_parent;
            break;
        case NODE_POINTER_TYPE:
            current_parent_ = node;
            visit(node->as.pointer_type.base);
            current_parent_ = prev_parent;
            break;
        case NODE_EXPRESSION_STMT:
            current_parent_ = node;
            visit(node->as.expression_stmt.expression);
            current_parent_ = prev_parent;
            break;
        case NODE_FOR_STMT:
            current_parent_ = node;
            visit(node->as.for_stmt->iterable_expr);
            visit(node->as.for_stmt->body);
            current_parent_ = prev_parent;
            break;
        case NODE_SWITCH_EXPR:
            current_parent_ = node;
            visit(node->as.switch_expr->expression);
            for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                if (!prong->is_else) {
                    for (size_t j = 0; j < prong->cases->length(); ++j) {
                        visit((*prong->cases)[j]);
                    }
                }
                visit(prong->body);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_COMPTIME_BLOCK:
            current_parent_ = node;
            visit(node->as.comptime_block.expression);
            current_parent_ = prev_parent;
            break;
        default:
            // No action needed for literals, identifiers, etc.
            break;
    }
}

void C89FeatureValidator::visitArrayType(ASTNode* node) {
    if (node->as.array_type.size == NULL) {
        fatalError(node->loc, "Slices are not supported for C89 compatibility.");
    }
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(node->as.array_type.element_type);
    current_parent_ = prev_parent;
}

void C89FeatureValidator::visitErrorUnionType(ASTNode* node) {
    reportNonC89Feature(node->loc, "Error union types (!T) are not C89-compatible.");
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(node->as.error_union_type->payload_type);
    current_parent_ = prev_parent;
}

void C89FeatureValidator::visitOptionalType(ASTNode* node) {
    reportNonC89Feature(node->loc, "Optional types (?T) are not C89-compatible.");
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(node->as.optional_type->payload_type);
    current_parent_ = prev_parent;
}

void C89FeatureValidator::visitTryExpr(ASTNode* node) {
    const char* context = getExpressionContext(node);

    // Type info
    Type* inner_type = NULL;
    Type* result_type = node->resolved_type;
    if (node->as.try_expr.expression) {
        inner_type = node->as.try_expr.expression->resolved_type;
    }

    // Catalogue before rejecting
    unit.getTryExpressionCatalogue().addTryExpression(
        node->loc,
        context,
        inner_type,
        result_type,
        try_expression_depth_
    );

    // Reject
    char msg[256];
    char* current = msg;
    size_t remaining = sizeof(msg);
    safe_append(current, remaining, "Try expression in ");
    safe_append(current, remaining, context);
    safe_append(current, remaining, " context is not C89-compatible.");
    reportNonC89Feature(node->loc, msg, true);

    // Recursive visit with depth tracking
    try_expression_depth_++;
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(node->as.try_expr.expression);
    current_parent_ = prev_parent;
    try_expression_depth_--;
}

void C89FeatureValidator::visitCatchExpr(ASTNode* node) {
    fatalError(node->loc, "'catch' expressions are not supported for C89 compatibility.");
}

void C89FeatureValidator::visitOrelseExpr(ASTNode* node) {
    fatalError(node->loc, "'orelse' expressions are not supported for C89 compatibility.");
}

void C89FeatureValidator::visitErrorSetDefinition(ASTNode* node) {
    fatalError(node->loc, "Error sets are not supported for C89 compatibility.");
}

void C89FeatureValidator::visitErrorSetMerge(ASTNode* node) {
    fatalError(node->loc, "Error set merging (||) is not supported for C89 compatibility.");
}

void C89FeatureValidator::visitImportStmt(ASTNode* node) {
    fatalError(node->loc, "Imports (@import) are not supported in the bootstrap phase.");
}

void C89FeatureValidator::visitFunctionCall(ASTNode* node) {
    ASTFunctionCallNode* call = node->as.function_call;
    ASTNode* prev_parent = current_parent_;

    // 1. Detect explicit generic call (type expression as argument)
    for (size_t i = 0; i < call->args->length(); ++i) {
        if (isTypeExpression((*call->args)[i], unit.getSymbolTable())) {
            reportNonC89Feature(node->loc, "Generic function calls (with type arguments) are not C89-compatible.");
            break;
        }
    }

    // 2. Detect implicit generic call (call to generic function)
    if (call->callee->type == NODE_IDENTIFIER) {
        Symbol* sym = unit.getSymbolTable().lookup(call->callee->as.identifier.name);
        if (sym && sym->is_generic) {
            reportNonC89Feature(node->loc, "Calls to generic functions are not C89-compatible.");
        }
    }

    // Continue traversal
    current_parent_ = node;
    visit(call->callee);
    for (size_t i = 0; i < call->args->length(); ++i) {
        visit((*call->args)[i]);
    }
    current_parent_ = prev_parent;
}

const char* C89FeatureValidator::getExpressionContext(ASTNode* node) {
    if (!current_parent_) return "expression";

    switch (current_parent_->type) {
        case NODE_RETURN_STMT: return "return";
        case NODE_ASSIGNMENT: return "assignment";
        case NODE_VAR_DECL: return "variable_decl";
        case NODE_FUNCTION_CALL: return "call_argument";
        case NODE_IF_STMT: return "conditional";
        case NODE_TRY_EXPR: return "nested_try";
        case NODE_WHILE_STMT: return "conditional";
        case NODE_BINARY_OP: return "binary_op";
        default: return "expression";
    }
}

void C89FeatureValidator::visitFnDecl(ASTNode* node) {
    ASTFnDeclNode* fn = node->as.fn_decl;
    // Resolve return type from symbol table (populated by TypeChecker)
    Symbol* symbol = unit.getSymbolTable().lookup(fn->name);
    Type* return_type = NULL;
    if (symbol && symbol->symbol_type && symbol->symbol_type->kind == TYPE_FUNCTION) {
        return_type = symbol->symbol_type->as.function.return_type;
    }

    bool is_generic = hasComptimeParams(fn);
    bool returns_error = isErrorType(return_type);

    // Catalogue BEFORE rejection
    if (returns_error) {
        unit.getErrorFunctionCatalogue().addErrorFunction(
            fn->name,
            return_type,
            node->loc,
            is_generic,
            (int)fn->params->length()
        );
    }

    // Report diagnostics
    if (returns_error) {
        char type_str[128];
        typeToString(return_type, type_str, sizeof(type_str));
        char msg_buffer[256];
        char* current = msg_buffer;
        size_t remaining = sizeof(msg_buffer);
        safe_append(current, remaining, "Function '");
        safe_append(current, remaining, fn->name);
        safe_append(current, remaining, "' returns error type '");
        safe_append(current, remaining, type_str);
        safe_append(current, remaining, "' (non-C89)");
        reportNonC89Feature(node->loc, msg_buffer, true);
    }

    // Continue traversal
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    for (size_t i = 0; i < fn->params->length(); ++i) {
        visit((*fn->params)[i]->type);
    }
    if (fn->return_type) {
        visit(fn->return_type);
    }
    visit(fn->body);
    current_parent_ = prev_parent;
}
