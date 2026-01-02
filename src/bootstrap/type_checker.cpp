#include "type_checker.hpp"
#include "type_system.hpp"
#include "error_handler.hpp"
#include <cstdio> // For sprintf
#include <cstdlib> // For abort()

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
    Type* operand_type = visit(node->operand);
    if (!operand_type) {
        return NULL; // Error already reported
    }

    switch (node->op) {
        case TOKEN_STAR:
            if (operand_type->kind == TYPE_POINTER) {
                return operand_type->as.pointer.base;
            }
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Cannot dereference a non-pointer type");
            return NULL;
        case TOKEN_AMPERSAND: {
            // The operand of '&' must be an l-value.
            // We consider identifiers, array accesses, and dereferences to be l-values.
            bool is_lvalue = false;
            if (node->operand->type == NODE_IDENTIFIER || node->operand->type == NODE_ARRAY_ACCESS) {
                is_lvalue = true;
            } else if (node->operand->type == NODE_UNARY_OP && node->operand->as.unary_op.op == TOKEN_STAR) {
                is_lvalue = true;
            }

            if (is_lvalue) {
                return createPointerType(unit.getArena(), operand_type, false);
            } else {
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Cannot take the address of an r-value");
                return NULL;
            }
        }
        case TOKEN_MINUS:
            if (isNumericType(operand_type)) {
                return operand_type; // Negation doesn't change numeric type
            }
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Unary '-' requires a numeric operand");
            return NULL;
        case TOKEN_BANG:
            // Logical not can be applied to any type that can be a condition.
            if (operand_type->kind == TYPE_BOOL || isNumericType(operand_type) || operand_type->kind == TYPE_POINTER) {
                return resolvePrimitiveTypeName("bool");
            }
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Invalid operand for logical not");
            return NULL;
        default:
            // TODO: Handle other unary operators like dereference (*), bitwise not (~)
            return NULL;
    }
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
            // Pointer + Integer
            if (left_type->kind == TYPE_POINTER && isIntegerType(right_type)) {
                return left_type;
            }
            // Integer + Pointer
            if (isIntegerType(left_type) && right_type->kind == TYPE_POINTER) {
                return right_type;
            }
            // Numeric + Numeric
            if (isNumericType(left_type) && areTypesCompatible(left_type, right_type)) {
                return left_type;
            }
            break;
        case TOKEN_MINUS:
            // Pointer - Integer
            if (left_type->kind == TYPE_POINTER && isIntegerType(right_type)) {
                return left_type;
            }
            // Pointer - Pointer
            if (left_type->kind == TYPE_POINTER && right_type->kind == TYPE_POINTER) {
                if (areTypesCompatible(left_type->as.pointer.base, right_type->as.pointer.base)) {
                    return resolvePrimitiveTypeName("isize");
                }
            }
            // Numeric - Numeric
            if (isNumericType(left_type) && areTypesCompatible(left_type, right_type)) {
                return left_type;
            }
            break;
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
    if (node->args->length() > 4) {
        fatalError(node->callee->loc, "Bootstrap compiler does not support function calls with more than 4 arguments.");
    }

    Type* callee_type = visit(node->callee);
    if (!callee_type) {
        // Error already reported (e.g., undefined function)
        return NULL;
    }

    if (callee_type->kind != TYPE_FUNCTION) {
        // This also handles the function pointer case, as a variable holding a
        // function would have a symbol kind of VARIABLE, not FUNCTION.
        fatalError(node->callee->loc, "called object is not a function");
    }

    size_t expected_args = callee_type->as.function.params->length();
    size_t actual_args = node->args->length();

    if (actual_args != expected_args) {
        char msg_buffer[256];
        snprintf(msg_buffer, sizeof(msg_buffer), "wrong number of arguments to function call, expected %lu, got %lu",
                 (unsigned long)expected_args, (unsigned long)actual_args);
        fatalError(node->callee->loc, msg_buffer);
    }

    for (size_t i = 0; i < actual_args; ++i) {
        ASTNode* arg_node = (*node->args)[i];
        Type* arg_type = visit(arg_node);
        Type* param_type = (*callee_type->as.function.params)[i];

        if (!arg_type) {
            // Error in argument expression, already reported.
            continue;
        }

        if (!areTypesCompatible(param_type, arg_type)) {
            char param_type_str[64];
            char arg_type_str[64];
            typeToString(param_type, param_type_str, sizeof(param_type_str));
            typeToString(arg_type, arg_type_str, sizeof(arg_type_str));

            char msg_buffer[256];
            snprintf(msg_buffer, sizeof(msg_buffer), "incompatible argument type for argument %lu, expected '%s', got '%s'",
                     (unsigned long)i + 1, param_type_str, arg_type_str);
            fatalError(arg_node->loc, msg_buffer);
        }
    }

    return callee_type->as.function.return_type;
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
    unit.getSymbolTable().enterScope();
    for (size_t i = 0; i < node->statements->length(); ++i) {
        visit((*node->statements)[i]);
    }
    unit.getSymbolTable().exitScope();
    return NULL; // Blocks don't have a type
}

Type* TypeChecker::visitEmptyStmt(ASTEmptyStmtNode* node) {
    return NULL;
}

Type* TypeChecker::visitIfStmt(ASTIfStmtNode* node) {
    Type* condition_type = visit(node->condition);
    if (condition_type) {
        if (condition_type->kind != TYPE_BOOL &&
            !(condition_type->kind >= TYPE_I8 && condition_type->kind <= TYPE_USIZE) &&
            condition_type->kind != TYPE_POINTER) {
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->condition->loc,
                                           "if statement condition must be a bool, integer, or pointer",
                                           unit.getArena());
        }
    }

    visit(node->then_block);
    if (node->else_block) {
        visit(node->else_block);
    }
    return NULL;
}

Type* TypeChecker::visitWhileStmt(ASTWhileStmtNode* node) {
    Type* condition_type = visit(node->condition);
    if (condition_type) {
        if (condition_type->kind != TYPE_BOOL &&
            !(condition_type->kind >= TYPE_I8 && condition_type->kind <= TYPE_USIZE) &&
            condition_type->kind != TYPE_POINTER) {
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->condition->loc,
                                           "while statement condition must be a bool, integer, or pointer",
                                           unit.getArena());
        }
    }

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

    // Insert the symbol into the current scope
    if (declared_type) {
        Symbol var_symbol = SymbolBuilder(unit.getArena())
            .withName(node->name)
            .ofType(SYMBOL_VARIABLE)
            .withType(declared_type)
            .atLocation(node->type->loc)
            .build();
        if (!unit.getSymbolTable().insert(var_symbol)) {
            unit.getErrorHandler().report(ERR_REDEFINITION, node->type->loc, "redefinition of variable", unit.getArena());
        }
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

bool TypeChecker::isIntegerType(Type* type) {
    if (!type) {
        return false;
    }
    return type->kind >= TYPE_I8 && type->kind <= TYPE_USIZE;
}

void TypeChecker::fatalError(SourceLocation loc, const char* message) {
    // For now, we'll just print to stderr and abort.
    // In the future, this could be integrated with the ErrorHandler.
    const SourceFile* file = unit.getSourceManager().getFile(loc.file_id);
    fprintf(stderr, "Fatal type error at %s:%d:%d: %s\n",
            file ? file->filename : "<unknown>",
            loc.line,
            loc.column,
            message);
    abort();
}
