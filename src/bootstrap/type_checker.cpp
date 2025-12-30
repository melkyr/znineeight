#include "type_checker.hpp"
#include "type_system.hpp"
#include "error_handler.hpp"
#include <cstdio> // For sprintf

TypeChecker::TypeChecker(CompilationUnit& unit) : unit(unit), current_fn_return_type(NULL) {
}

void TypeChecker::check(ASTNode* root) {
    visit(root);
}

Type* TypeChecker::visit(ASTNode* node) {
    if (!node) {
        return NULL;
    }

    switch (node->type) {
        case NODE_UNARY_OP:         return visitUnaryOp(&node->as.unary_op);
        case NODE_BINARY_OP:        return visitBinaryOp(node->as.binary_op);
        case NODE_FUNCTION_CALL:    return visitFunctionCall(node->as.function_call);
        case NODE_ARRAY_ACCESS:     return visitArrayAccess(node->as.array_access);
        case NODE_ARRAY_SLICE:      return visitArraySlice(node->as.array_slice);
        case NODE_BOOL_LITERAL:     return visitBoolLiteral(&node->as.bool_literal);
        case NODE_INTEGER_LITERAL:  return visitIntegerLiteral(&node->as.integer_literal);
        case NODE_FLOAT_LITERAL:    return visitFloatLiteral(&node->as.float_literal);
        case NODE_CHAR_LITERAL:     return visitCharLiteral(&node->as.char_literal);
        case NODE_STRING_LITERAL:   return visitStringLiteral(&node->as.string_literal);
        case NODE_IDENTIFIER:       return visitIdentifier(node);
        case NODE_BLOCK_STMT:       return visitBlockStmt(&node->as.block_stmt);
        case NODE_EMPTY_STMT:       return visitEmptyStmt(&node->as.empty_stmt);
        case NODE_IF_STMT:          return visitIfStmt(node->as.if_stmt);
        case NODE_WHILE_STMT:       return visitWhileStmt(&node->as.while_stmt);
        case NODE_RETURN_STMT:      return visitReturnStmt(node, &node->as.return_stmt);
        case NODE_DEFER_STMT:       return visitDeferStmt(&node->as.defer_stmt);
        case NODE_FOR_STMT:         return visitForStmt(node->as.for_stmt);
        case NODE_EXPRESSION_STMT:  return visitExpressionStmt(&node->as.expression_stmt);
        case NODE_SWITCH_EXPR:      return visitSwitchExpr(node->as.switch_expr);
        case NODE_VAR_DECL:         return visitVarDecl(node->as.var_decl);
        case NODE_FN_DECL:          return visitFnDecl(node->as.fn_decl);
        case NODE_STRUCT_DECL:      return visitStructDecl(node->as.struct_decl);
        case NODE_UNION_DECL:       return visitUnionDecl(node->as.union_decl);
        case NODE_ENUM_DECL:        return visitEnumDecl(node->as.enum_decl);
        case NODE_TYPE_NAME:        return visitTypeName(node, &node->as.type_name);
        case NODE_POINTER_TYPE:     return visitPointerType(&node->as.pointer_type);
        case NODE_ARRAY_TYPE:       return visitArrayType(&node->as.array_type);
        case NODE_TRY_EXPR:         return visitTryExpr(&node->as.try_expr);
        case NODE_CATCH_EXPR:       return visitCatchExpr(node->as.catch_expr);
        case NODE_ERRDEFER_STMT:    return visitErrdeferStmt(&node->as.errdefer_stmt);
        case NODE_COMPTIME_BLOCK:   return visitComptimeBlock(&node->as.comptime_block);
        default:
            // TODO: Add error handling for unhandled node types.
            return NULL;
    }
}

Type* TypeChecker::visitUnaryOp(ASTUnaryOpNode* node) {
    visit(node->operand);
    return NULL; // Placeholder
}

Type* TypeChecker::visitBinaryOp(ASTBinaryOpNode* node) {
    Type* left_type = visit(node->left);
    Type* right_type = visit(node->right);

    // If either operand is null, an error has already been reported.
    if (!left_type || !right_type) {
        return NULL;
    }

    // Check for compatible types based on the operator
    switch (node->op) {
        // Arithmetic operators
        case TOKEN_PLUS:
        case TOKEN_MINUS:
        case TOKEN_STAR:
        case TOKEN_SLASH:
        case TOKEN_PERCENT:
            if (isNumericType(left_type) && areTypesCompatible(left_type, right_type)) {
                return left_type; // For now, result type is the same as operands
            }
            break;

        // Comparison operators
        case TOKEN_EQUAL_EQUAL:
        case TOKEN_BANG_EQUAL:
        case TOKEN_LESS:
        case TOKEN_LESS_EQUAL:
        case TOKEN_GREATER:
        case TOKEN_GREATER_EQUAL:
            if (isNumericType(left_type) && areTypesCompatible(left_type, right_type)) {
                return resolvePrimitiveTypeName("bool");
            }
            break;

        default:
            // Operator not supported for binary expressions yet
            break;
    }

    // If we fall through, the types were not compatible for the given operator.
    unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->left->loc, "Invalid operands for binary operator");
    return NULL;
}

Type* TypeChecker::visitFunctionCall(ASTFunctionCallNode* node) {
    visit(node->callee);
    for (size_t i = 0; i < node->args->length(); ++i) {
        visit((*node->args)[i]);
    }
    return NULL; // Placeholder
}

Type* TypeChecker::visitArrayAccess(ASTArrayAccessNode* node) {
    visit(node->array);
    visit(node->index);
    return NULL; // Placeholder
}

Type* TypeChecker::visitArraySlice(ASTArraySliceNode* node) {
    visit(node->array);
    if (node->start) visit(node->start);
    if (node->end) visit(node->end);
    return NULL; // Placeholder
}

Type* TypeChecker::visitBoolLiteral(ASTBoolLiteralNode* node) {
    return resolvePrimitiveTypeName("bool");
}

Type* TypeChecker::visitIntegerLiteral(ASTIntegerLiteralNode* node) {
    // This is a simplification. A real type checker would have more sophisticated
    // rules for integer literal types. For now, we'll assume i32 unless the
    // value is too large, in which case we'll assume i64.
    if (node->value > 2147483647 || node->value < -2147483648) {
        return resolvePrimitiveTypeName("i64");
    }
    return resolvePrimitiveTypeName("i32");
}

Type* TypeChecker::visitFloatLiteral(ASTFloatLiteralNode* node) {
    return resolvePrimitiveTypeName("f64");
}

Type* TypeChecker::visitCharLiteral(ASTCharLiteralNode* node) {
    return resolvePrimitiveTypeName("u8");
}

Type* TypeChecker::visitStringLiteral(ASTStringLiteralNode* node) {
    Type* char_type = resolvePrimitiveTypeName("u8");
    // String literals are pointers to constant characters.
    return createPointerType(unit.getArena(), char_type, true);
}

Type* TypeChecker::visitIdentifier(ASTNode* node) {
    Symbol* sym = unit.getSymbolTable().lookup(node->as.identifier.name);
    if (!sym) {
        unit.getErrorHandler().report(ERR_UNDEFINED_VARIABLE, node->loc, "Use of undeclared identifier");
        return NULL;
    }
    return sym->symbol_type;
}

Type* TypeChecker::visitBlockStmt(ASTBlockStmtNode* node) {
    for (size_t i = 0; i < node->statements->length(); ++i) {
        visit((*node->statements)[i]);
    }
    return NULL; // Blocks don't have a type
}

Type* TypeChecker::visitEmptyStmt(ASTEmptyStmtNode* node) {
    return NULL;
}

Type* TypeChecker::visitIfStmt(ASTIfStmtNode* node) {
    visit(node->condition);
    visit(node->then_block);
    if (node->else_block) {
        visit(node->else_block);
    }
    return NULL;
}

Type* TypeChecker::visitWhileStmt(ASTWhileStmtNode* node) {
    visit(node->condition);
    visit(node->body);
    return NULL;
}

Type* TypeChecker::visitReturnStmt(ASTNode* parent, ASTReturnStmtNode* node) {
    Type* return_type = node->expression ? visit(node->expression) : resolvePrimitiveTypeName("void");

    if (current_fn_return_type && !areTypesCompatible(current_fn_return_type, return_type)) {
        SourceLocation loc = node->expression ? node->expression->loc : parent->loc;
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, "Return type mismatch");
    }

    return NULL;
}

Type* TypeChecker::visitDeferStmt(ASTDeferStmtNode* node) {
    visit(node->statement);
    return NULL;
}

Type* TypeChecker::visitForStmt(ASTForStmtNode* node) {
    visit(node->iterable_expr);
    visit(node->body);
    return NULL;
}

Type* TypeChecker::visitSwitchExpr(ASTSwitchExprNode* node) {
    visit(node->expression);
    // TODO: Visit prongs
    return NULL;
}

Type* TypeChecker::visitVarDecl(ASTVarDeclNode* node) {
    Type* declared_type = visit(node->type);
    Type* initializer_type = visit(node->initializer);

    if (declared_type && initializer_type && !areTypesCompatible(declared_type, initializer_type)) {
        char declared_type_str[64];
        char initializer_type_str[64];
        typeToString(declared_type, declared_type_str, sizeof(declared_type_str));
        typeToString(initializer_type, initializer_type_str, sizeof(initializer_type_str));

        char msg_buffer[256];
        snprintf(msg_buffer, sizeof(msg_buffer), "cannot assign type '%s' to variable of type '%s'",
                 initializer_type_str, declared_type_str);
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->initializer->loc, msg_buffer, unit.getArena());
    }

    return NULL;
}

Type* TypeChecker::visitFnDecl(ASTFnDeclNode* node) {
    Type* prev_fn_return_type = current_fn_return_type;

    // Resolve return type
    current_fn_return_type = visit(node->return_type);
    if (!current_fn_return_type) {
        // If the return type is invalid (e.g., an undefined identifier),
        // we can't proceed with checking the function body.
        return NULL;
    }

    // Resolve parameter types
    void* mem = unit.getArena().alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* param_types = new (mem) DynamicArray<Type*>(unit.getArena());
    bool all_params_valid = true;
    for (size_t i = 0; i < node->params->length(); ++i) {
        ASTParamDeclNode* param_node = (*node->params)[i];
        Type* param_type = visit(param_node->type);
        if (param_type) {
            param_types->append(param_type);
        } else {
            all_params_valid = false;
        }
    }

    // If any parameter type was invalid, don't create the function type
    // or check the body, as it will likely lead to cascading errors.
    if (!all_params_valid) {
        current_fn_return_type = prev_fn_return_type;
        return NULL;
    }

    // Create the function type and update the symbol
    Type* function_type = createFunctionType(unit.getArena(), param_types, current_fn_return_type);
    Symbol* fn_symbol = unit.getSymbolTable().lookup(node->name);
    if (fn_symbol) {
        fn_symbol->symbol_type = function_type;
    }

    unit.getSymbolTable().enterScope();
    for (size_t i = 0; i < node->params->length(); ++i) {
        ASTParamDeclNode* param_node = (*node->params)[i];
        Type* param_type = (*param_types)[i];
        Symbol param_symbol = SymbolBuilder(unit.getArena())
            .withName(param_node->name)
            .ofType(SYMBOL_VARIABLE)
            .withType(param_type)
            .atLocation(param_node->type->loc)
            .build();
        unit.getSymbolTable().insert(param_symbol);
    }

    visit(node->body);

    unit.getSymbolTable().exitScope();

    current_fn_return_type = prev_fn_return_type;
    return NULL;
}

Type* TypeChecker::visitStructDecl(ASTStructDeclNode* node) {
    // TODO: Visit fields
    return NULL;
}

Type* TypeChecker::visitUnionDecl(ASTUnionDeclNode* node) {
    // TODO: Visit fields
    return NULL;
}

Type* TypeChecker::visitEnumDecl(ASTEnumDeclNode* node) {
    // TODO: Visit fields
    return NULL;
}

Type* TypeChecker::visitTypeName(ASTNode* parent, ASTTypeNameNode* node) {
    Type* resolved_type = resolvePrimitiveTypeName(node->name);
    if (!resolved_type) {
        char msg_buffer[256];
        snprintf(msg_buffer, sizeof(msg_buffer), "use of undeclared type '%s'", node->name);
        unit.getErrorHandler().report(ERR_UNDECLARED_TYPE, parent->loc, msg_buffer, unit.getArena());
    }
    return resolved_type;
}

Type* TypeChecker::visitPointerType(ASTPointerTypeNode* node) {
    Type* base_type = visit(node->base);
    if (!base_type) {
        // Error already reported by the base type visit
        return NULL;
    }
    return createPointerType(unit.getArena(), base_type, node->is_const);
}

Type* TypeChecker::visitArrayType(ASTArrayTypeNode* node) {
    visit(node->element_type);
    if (node->size) {
        visit(node->size);
    }
    return NULL; // Placeholder
}

Type* TypeChecker::visitTryExpr(ASTTryExprNode* node) {
    visit(node->expression);
    return NULL; // Placeholder
}

Type* TypeChecker::visitCatchExpr(ASTCatchExprNode* node) {
    visit(node->payload);
    visit(node->else_expr);
    return NULL; // Placeholder
}

Type* TypeChecker::visitErrdeferStmt(ASTErrDeferStmtNode* node) {
    visit(node->statement);
    return NULL;
}

Type* TypeChecker::visitComptimeBlock(ASTComptimeBlockNode* node) {
    visit(node->expression);
    return NULL;
}

Type* TypeChecker::visitExpressionStmt(ASTExpressionStmtNode* node) {
    visit(node->expression);
    return NULL; // Expression statements don't have a type
}

/**
 * @brief Checks if two types are compatible for assignment or function arguments.
 *
 * This function determines if a value of type `actual` can be safely used where
 * a value of type `expected` is required. The rules are:
 * 1.  Identical types are always compatible.
 * 2.  Numeric types are compatible if the `actual` type can be widened to the
 *     `expected` type without data loss (e.g., `i16` to `i32`, `f32` to `f64`).
 * 3.  Pointer types are compatible if they point to the same base type and
 *     the `expected` type is at least as const-qualified as the `actual` type.
 *     This allows `*T` to be used as `*const T`, but not vice-versa.
 *
 * @param expected The type that is required (e.g., the variable's type).
 * @param actual The type of the value being assigned or passed.
 * @return `true` if the types are compatible, `false` otherwise.
 */
bool TypeChecker::areTypesCompatible(Type* expected, Type* actual) {
    if (expected == actual) {
        return true;
    }

    if (!expected || !actual) {
        return false;
    }

    // Widening for signed integers
    if (actual->kind >= TYPE_I8 && actual->kind <= TYPE_I64 &&
        expected->kind >= TYPE_I8 && expected->kind <= TYPE_I64) {
        return actual->kind <= expected->kind;
    }

    // Widening for unsigned integers
    if (actual->kind >= TYPE_U8 && actual->kind <= TYPE_U64 &&
        expected->kind >= TYPE_U8 && expected->kind <= TYPE_U64) {
        return actual->kind <= expected->kind;
    }

    // Widening for floats
    if (actual->kind == TYPE_F32 && expected->kind == TYPE_F64) {
        return true;
    }

    // Pointer compatibility
    if (actual->kind == TYPE_POINTER && expected->kind == TYPE_POINTER) {
        // Must have the same base type
        if (actual->as.pointer.base != expected->as.pointer.base) {
            return false;
        }
        // A mutable pointer can be assigned to a const pointer,
        // but not the other way around.
        // *T -> *const T (OK)
        // *const T -> *T (Error)
        return expected->as.pointer.is_const || !actual->as.pointer.is_const;
    }

    return false;
}

bool TypeChecker::isNumericType(Type* type) {
    if (!type) {
        return false;
    }
    return type->kind >= TYPE_I8 && type->kind <= TYPE_F64;
}
