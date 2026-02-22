#include "c89_feature_validator.hpp"
#include "ast.hpp"
#include "ast_utils.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"
#include "utils.hpp"
#include "platform.hpp"

C89FeatureValidator::C89FeatureValidator(CompilationUnit& unit)
    : unit(unit), error_found_(false), try_expression_depth_(0),
      catch_chain_index_(0), catch_chain_total_(0), in_catch_chain_(false),
      current_nesting_depth_(0), current_parent_(NULL) {}

bool C89FeatureValidator::validate(ASTNode* node) {
    visit(node);

    // Generate extraction analysis report even if error found,
    // as it's useful for Milestone 5 planning.
    unit.getExtractionAnalysisCatalogue().generateReport(&unit);
    unit.getErrorHandler().printInfos();

    return !error_found_;
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

static bool hasGenericParams(ASTFnDeclNode* node) {
    if (!node->params) return false;
    for (size_t i = 0; i < node->params->length(); ++i) {
        ASTParamDeclNode* p = (*node->params)[i];
        if (p->is_comptime || p->is_anytype || p->is_type_param) return true;
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
        case NODE_ERROR_LITERAL:
            // Error literals are now supported
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
            if (node->as.binary_op) {
                visit(node->as.binary_op->left);
                visit(node->as.binary_op->right);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_UNARY_OP:
            current_parent_ = node;
            visit(node->as.unary_op.operand);
            current_parent_ = prev_parent;
            break;
        case NODE_BLOCK_STMT:
            visitBlockStmt(node);
            break;
        case NODE_IF_STMT:
            current_parent_ = node;
            if (node->as.if_stmt) {
                visit(node->as.if_stmt->condition);
                visit(node->as.if_stmt->then_block);
                if (node->as.if_stmt->else_block) {
                    visit(node->as.if_stmt->else_block);
                }
            }
            current_parent_ = prev_parent;
            break;
        case NODE_WHILE_STMT:
            current_parent_ = node;
            visit(node->as.while_stmt->condition);
            visit(node->as.while_stmt->body);
            current_parent_ = prev_parent;
            break;
        case NODE_BREAK_STMT:
        case NODE_CONTINUE_STMT:
            // Allowed in standard C89
            break;
        case NODE_DEFER_STMT:
            current_parent_ = node;
            visit(node->as.defer_stmt.statement);
            current_parent_ = prev_parent;
            break;
        case NODE_PARAM_DECL:
            current_parent_ = node;
            if (node->as.param_decl.is_comptime) {
                reportNonC89Feature(node->loc, "comptime parameters are not supported in C89 mode");
            }
            if (node->as.param_decl.is_anytype) {
                bool is_exception = false;
                if (current_parent_ && current_parent_->type == NODE_FN_DECL &&
                    current_parent_->as.fn_decl->name &&
                    plat_strcmp(current_parent_->as.fn_decl->name, "print") == 0) {
                    is_exception = true;
                }
                if (!is_exception) {
                    reportNonC89Feature(node->loc, "anytype parameters are not supported in C89 mode");
                }
            }
            if (node->as.param_decl.is_type_param) {
                reportNonC89Feature(node->loc, "type parameters are not supported in C89 mode");
            }
            visit(node->as.param_decl.type);
            current_parent_ = prev_parent;
            break;
        case NODE_MEMBER_ACCESS:
            current_parent_ = node;
            if (node->as.member_access) {
                visit(node->as.member_access->base);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_STRUCT_INITIALIZER:
            current_parent_ = node;
            if (node->as.struct_initializer) {
                visit(node->as.struct_initializer->type_expr);
                if (node->as.struct_initializer->fields) {
                    for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                        visit((*node->as.struct_initializer->fields)[i]->value);
                    }
                }
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ARRAY_ACCESS:
            current_parent_ = node;
            if (node->as.array_access) {
                visit(node->as.array_access->array);
                visit(node->as.array_access->index);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ARRAY_SLICE:
            // Slices are now supported as a language extension for bootstrap
            current_parent_ = node;
            if (node->as.array_slice) {
                visit(node->as.array_slice->array);
                if (node->as.array_slice->start) visit(node->as.array_slice->start);
                if (node->as.array_slice->end) visit(node->as.array_slice->end);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ERRDEFER_STMT:
            unit.getErrDeferCatalogue().addErrDefer(node->loc);
            reportNonC89Feature(node->loc, "errdefer statements are not supported in C89 mode");
            current_parent_ = node;
            visit(node->as.errdefer_stmt.statement);
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
            if (node->as.var_decl) {
                visit(node->as.var_decl->type);
                if (node->as.var_decl->initializer) {
                    visit(node->as.var_decl->initializer);
                }
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ASSIGNMENT:
            current_parent_ = node;
            if (node->as.assignment) {
                visit(node->as.assignment->lvalue);
                visit(node->as.assignment->rvalue);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            current_parent_ = node;
            if (node->as.compound_assignment) {
                visit(node->as.compound_assignment->lvalue);
                visit(node->as.compound_assignment->rvalue);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_FN_DECL:
            visitFnDecl(node);
            break;
        case NODE_STRUCT_DECL:
            current_parent_ = node;
            if (node->as.struct_decl && node->as.struct_decl->fields) {
                for (size_t i = 0; i < node->as.struct_decl->fields->length(); ++i) {
                    visit((*node->as.struct_decl->fields)[i]);
                }
            }
            current_parent_ = prev_parent;
            break;
        case NODE_UNION_DECL:
            current_parent_ = node;
            if (node->as.union_decl && node->as.union_decl->fields) {
                for (size_t i = 0; i < node->as.union_decl->fields->length(); ++i) {
                    visit((*node->as.union_decl->fields)[i]);
                }
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ENUM_DECL:
            current_parent_ = node;
            if (node->as.enum_decl) {
                if (node->as.enum_decl->backing_type) {
                    visit(node->as.enum_decl->backing_type);
                }
                if (node->as.enum_decl->fields) {
                    for (size_t i = 0; i < node->as.enum_decl->fields->length(); ++i) {
                        visit((*node->as.enum_decl->fields)[i]);
                    }
                }
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
            if (node->as.for_stmt) {
                visit(node->as.for_stmt->iterable_expr);
                visit(node->as.for_stmt->body);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_PTR_CAST:
            current_parent_ = node;
            if (node->as.ptr_cast) {
                visit(node->as.ptr_cast->target_type);
                visit(node->as.ptr_cast->expr);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_SWITCH_EXPR:
            current_parent_ = node;
            if (node->as.switch_expr) {
                visit(node->as.switch_expr->expression);
                if (node->as.switch_expr->prongs) {
                    for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                        ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                        if (prong) {
                            if (!prong->is_else && prong->items) {
                                for (size_t j = 0; j < prong->items->length(); ++j) {
                                    visit((*prong->items)[j]);
                                }
                            }
                            visit(prong->body);
                        }
                    }
                }
            }
            current_parent_ = prev_parent;
            break;
        case NODE_COMPTIME_BLOCK:
            current_parent_ = node;
            visit(node->as.comptime_block.expression);
            current_parent_ = prev_parent;
            break;
        case NODE_PAREN_EXPR:
            visit(node->as.paren_expr.expr);
            break;
        case NODE_FUNCTION_TYPE:
            current_parent_ = node;
            if (node->as.function_type) {
                if (node->as.function_type->params) {
                    for (size_t i = 0; i < node->as.function_type->params->length(); ++i) {
                        visit((*node->as.function_type->params)[i]);
                    }
                }
                visit(node->as.function_type->return_type);
            }
            current_parent_ = prev_parent;
            break;
        case NODE_ASYNC_EXPR:
            reportNonC89Feature(node->loc, "Async expressions are not supported in C89 mode");
            current_parent_ = node;
            visit(node->as.async_expr.expression);
            current_parent_ = prev_parent;
            break;
        case NODE_AWAIT_EXPR:
            reportNonC89Feature(node->loc, "Await expressions are not supported in C89 mode");
            current_parent_ = node;
            visit(node->as.await_expr.expression);
            current_parent_ = prev_parent;
            break;
        case NODE_TYPE_NAME:
            if (plat_strcmp(node->as.type_name.name, "anyerror") == 0) {
                reportNonC89Feature(node->loc, "anyerror type is not supported in bootstrap compiler");
            }
            if (plat_strcmp(node->as.type_name.name, "type") == 0) {
                reportNonC89Feature(node->loc, "Type parameters/variables are not supported in bootstrap compiler");
            }
            if (plat_strcmp(node->as.type_name.name, "anytype") == 0) {
                bool is_exception = false;
                if (current_parent_ && current_parent_->type == NODE_PARAM_DECL) {
                    is_exception = true;
                } else if (current_parent_ && current_parent_->type == NODE_FN_DECL) {
                    if (current_parent_->as.fn_decl->name &&
                        plat_strcmp(current_parent_->as.fn_decl->name, "print") == 0) {
                        is_exception = true;
                    }
                }
                if (!is_exception) {
                    reportNonC89Feature(node->loc, "anytype is not supported in bootstrap compiler");
                }
            }
            break;
        default:
            // No action needed for literals, identifiers, etc.
            break;
    }
}

void C89FeatureValidator::visitArrayType(ASTNode* node) {
    // Slices ([]T) are now supported as a language extension for bootstrap
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(node->as.array_type.element_type);
    current_parent_ = prev_parent;
}

void C89FeatureValidator::visitErrorUnionType(ASTNode* node) {
    // Error union types are now supported as a language extension for bootstrap
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    if (node->as.error_union_type->error_set) {
        visit(node->as.error_union_type->error_set);
    }
    visit(node->as.error_union_type->payload_type);
    current_parent_ = prev_parent;
}

void C89FeatureValidator::visitOptionalType(ASTNode* node) {
    reportNonC89Feature(node->loc, "Optional types (?T) are not supported in bootstrap compiler. Consider using a nullable pointer (*T) or separate boolean flag.");
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
    int try_idx = unit.getTryExpressionCatalogue().addTryExpression(
        node->loc,
        context,
        inner_type,
        result_type,
        try_expression_depth_
    );

    // Extraction Analysis if it's an error union
    if (inner_type && inner_type->kind == TYPE_ERROR_UNION) {
        Type* payload = inner_type->as.error_union.payload;
        int site_idx = unit.getExtractionAnalysisCatalogue().addExtractionSite(
            node->loc,
            payload,
            "try",
            try_idx,
            -1
        );

        // Link strategy back to TryExpressionCatalogue
        ExtractionSiteInfo& site = unit.getExtractionAnalysisCatalogue().getSite(site_idx);
        TryExpressionInfo& try_info = unit.getTryExpressionCatalogue().getTryExpression(try_idx);
        try_info.extraction_strategy = site.strategy;
        try_info.stack_safe = site.msvc6_safe;
    }

    // Recursive visit with depth tracking
    try_expression_depth_++;
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(node->as.try_expr.expression);
    current_parent_ = prev_parent;
    try_expression_depth_--;
}

void C89FeatureValidator::visitCatchExpr(ASTNode* node) {
    bool is_outermost = !in_catch_chain_;

    if (is_outermost) {
        // Calculate chain total
        int count = 0;
        ASTNode* curr = node;
        while (curr && curr->type == NODE_CATCH_EXPR) {
            count++;
            curr = curr->as.catch_expr->payload;
        }
        catch_chain_total_ = count;
        catch_chain_index_ = 0;
        in_catch_chain_ = true;
    }

    ASTNode* payload = node->as.catch_expr->payload;
    ASTNode* else_expr = node->as.catch_expr->else_expr;

    // Recursive visit payload (inner catches first in source order)
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(payload);
    current_parent_ = prev_parent;

    // Now log THIS catch expression
    int my_index = catch_chain_index_++;
    bool is_chained = (catch_chain_total_ > 1);

    Type* error_type = (payload ? payload->resolved_type : NULL);
    Type* handler_type = (else_expr ? else_expr->resolved_type : NULL);
    Type* result_type = node->resolved_type;

    int catch_idx = unit.getCatchExpressionCatalogue().addCatchExpression(
        node->loc,
        getExpressionContext(node),
        error_type,
        handler_type,
        result_type,
        node->as.catch_expr->error_name,
        my_index,
        is_chained
    );

    // Extraction Analysis
    if (error_type && error_type->kind == TYPE_ERROR_UNION) {
        Type* payload = error_type->as.error_union.payload;
        int site_idx = unit.getExtractionAnalysisCatalogue().addExtractionSite(
            node->loc,
            payload,
            "catch",
            -1,
            catch_idx
        );

        // Link strategy back to CatchExpressionCatalogue
        ExtractionSiteInfo& site = unit.getExtractionAnalysisCatalogue().getSite(site_idx);
        CatchExpressionInfo& catch_info = unit.getCatchExpressionCatalogue().getCatchExpression(catch_idx);
        catch_info.extraction_strategy = site.strategy;
        catch_info.stack_safe = site.msvc6_safe;
    }

    // Visit else_expr (handler)
    bool prev_in_chain = in_catch_chain_;
    in_catch_chain_ = false; // Handler is not part of the chain
    current_parent_ = node;
    visit(else_expr);
    current_parent_ = prev_parent;
    in_catch_chain_ = prev_in_chain;

    if (is_outermost) {
        in_catch_chain_ = false;
    }
}

void C89FeatureValidator::visitOrelseExpr(ASTNode* node) {
    ASTOrelseExprNode* orelse = node->as.orelse_expr;
    if (!orelse) return;

    Type* left_type = (orelse->payload ? orelse->payload->resolved_type : NULL);
    Type* right_type = (orelse->else_expr ? orelse->else_expr->resolved_type : NULL);
    Type* result_type = node->resolved_type;

    unit.getOrelseExpressionCatalogue().addOrelseExpression(
        node->loc,
        getExpressionContext(node),
        left_type,
        right_type,
        result_type
    );

    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(orelse->payload);
    visit(orelse->else_expr);
    current_parent_ = prev_parent;
}

void C89FeatureValidator::visitErrorSetDefinition(ASTNode* node) {
    // Error sets are now supported
    RETR_UNUSED(node);
}

void C89FeatureValidator::visitErrorSetMerge(ASTNode* node) {
    // Error set merging is now supported (handled as a type)
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    visit(node->as.error_set_merge->left);
    visit(node->as.error_set_merge->right);
    current_parent_ = prev_parent;
}

void C89FeatureValidator::visitImportStmt(ASTNode* node) {
    RETR_UNUSED(node);
    // Basic @import support is now implemented for multi-file loading.
}

void C89FeatureValidator::visitFunctionCall(ASTNode* node) {
    if (!node || node->type != NODE_FUNCTION_CALL || !node->as.function_call) return;
    ASTFunctionCallNode* call = node->as.function_call;
    ASTNode* prev_parent = current_parent_;

    // Handle built-ins (Task 168/186)
    if (call->callee->type == NODE_IDENTIFIER) {
        const char* name = call->callee->as.identifier.name;
        if (name[0] == '@') {
            // Allow basic built-ins as they are now partially supported for bootstrap
            if (plat_strcmp(name, "@sizeOf") == 0 || plat_strcmp(name, "@alignOf") == 0 ||
                plat_strcmp(name, "@ptrCast") == 0 || plat_strcmp(name, "@intCast") == 0 ||
                plat_strcmp(name, "@floatCast") == 0 || plat_strcmp(name, "@offsetOf") == 0) {
                return;
            }
            reportNonC89Feature(node->loc, "Built-in functions (@) are not supported in the bootstrap phase.");
            return;
        }
    }

    // Indirect calls are now supported (Task 221)

    // 1. Detect explicit generic call (type expression as argument)
    if (call->args) {
        for (size_t i = 0; i < call->args->length(); ++i) {
            if (isTypeExpression((*call->args)[i], unit.getSymbolTable())) {
                reportNonC89Feature(node->loc, "Generic function calls (with type arguments) are not C89-compatible.");
                break;
            }
        }
    }

    // 2. Detect implicit generic call (call to generic function)
    if (call->callee->type == NODE_IDENTIFIER) {
        const char* name = call->callee->as.identifier.name;
        const GenericInstantiation* inst = unit.getGenericCatalogue().findInstantiation(name, call->callee->loc);

        if (inst && !inst->is_explicit) {
            char msg[512];
            char* cur = msg;
            size_t rem = sizeof(msg);
            safe_append(cur, rem, "Implicit generic instantiation of '");
            safe_append(cur, rem, name);
            if (inst->mangled_name) {
                safe_append(cur, rem, "' (mangled: ");
                safe_append(cur, rem, inst->mangled_name);
                safe_append(cur, rem, ")");
            }
            safe_append(cur, rem, " with argument types: ");

            for (int i = 0; i < inst->param_count; i++) {
                if (i > 0) safe_append(cur, rem, ", ");
                char type_name[64];
                typeToString((*inst->arg_types)[i], type_name, sizeof(type_name));
                safe_append(cur, rem, type_name);
            }
            safe_append(cur, rem, " (non-C89)");
            reportNonC89Feature(node->loc, msg, true);
        } else {
            Symbol* sym = unit.getSymbolTable().lookup(name);
            if ((sym && sym->is_generic) || unit.getGenericCatalogue().isFunctionGeneric(name)) {
                reportNonC89Feature(node->loc, "Calls to generic functions are not C89-compatible.");
            }
        }
    }

    // Continue traversal
    current_parent_ = node;
    visit(call->callee);
    if (call->args) {
        for (size_t i = 0; i < call->args->length(); ++i) {
            visit((*call->args)[i]);
        }
    }
    current_parent_ = prev_parent;
}

const char* C89FeatureValidator::getExpressionContext(ASTNode* node) {
    RETR_UNUSED(node);
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
    if (!node || !node->as.fn_decl) return;
    ASTFnDeclNode* fn = node->as.fn_decl;

    // Nesting tracking
    unit.getExtractionAnalysisCatalogue().enterFunction(fn->name ? fn->name : "<anonymous>");

    // Resolve return type from symbol table (populated by TypeChecker)
    Symbol* symbol = fn->name ? unit.getSymbolTable().lookup(fn->name) : NULL;
    Type* return_type = NULL;
    if (symbol && symbol->symbol_type && symbol->symbol_type->kind == TYPE_FUNCTION) {
        return_type = symbol->symbol_type->as.function.return_type;
    }

    bool is_generic = hasGenericParams(fn);
    bool returns_error = isErrorType(return_type);

    if (is_generic || (fn->name && unit.getGenericCatalogue().isFunctionGeneric(fn->name))) {
        bool is_exception = (fn->name && plat_strcmp(fn->name, "print") == 0);
        if (!is_exception) {
            reportNonC89Feature(node->loc, "Generic functions are not supported in C89 mode.");
        }
    }

    // Catalogue BEFORE rejection
    if (returns_error) {
        Type* payload = (return_type->kind == TYPE_ERROR_UNION) ? return_type->as.error_union.payload : NULL;
        size_t size = payload ? payload->size : 0;
        bool safe = payload ? unit.getExtractionAnalysisCatalogue().isStackSafe(payload) : true;

        unit.getErrorFunctionCatalogue().addErrorFunction(
            fn->name ? fn->name : "<anonymous>",
            return_type,
            payload,
            node->loc,
            is_generic,
            (int)(fn->params ? fn->params->length() : 0),
            size,
            safe
        );
    }


    // Continue traversal
    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    if (fn->params) {
        for (size_t i = 0; i < fn->params->length(); ++i) {
            if ((*fn->params)[i]) {
                visit((*fn->params)[i]->type);
            }
        }
    }
    if (fn->return_type) {
        visit(fn->return_type);
    }
    visit(fn->body);
    current_parent_ = prev_parent;

    unit.getExtractionAnalysisCatalogue().exitFunction();
}

void C89FeatureValidator::visitBlockStmt(ASTNode* node) {
    unit.getExtractionAnalysisCatalogue().enterBlock();

    ASTNode* prev_parent = current_parent_;
    current_parent_ = node;
    if (node->as.block_stmt.statements) {
        for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
            visit((*node->as.block_stmt.statements)[i]);
        }
    }
    current_parent_ = prev_parent;

    unit.getExtractionAnalysisCatalogue().exitBlock();
}
