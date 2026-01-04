#include "type_checker.hpp"
#include "c89_type_mapping.hpp"
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

    Type* resolved_type = NULL;
    switch (node->type) {
        case NODE_UNARY_OP:         resolved_type = visitUnaryOp(node, &node->as.unary_op); break;
        case NODE_BINARY_OP:        resolved_type = visitBinaryOp(node, node->as.binary_op); break;
        case NODE_FUNCTION_CALL:    resolved_type = visitFunctionCall(node->as.function_call); break;
        case NODE_ARRAY_ACCESS:     resolved_type = visitArrayAccess(node->as.array_access); break;
        case NODE_ARRAY_SLICE:      resolved_type = visitArraySlice(node->as.array_slice); break;
        case NODE_BOOL_LITERAL:     resolved_type = visitBoolLiteral(&node->as.bool_literal); break;
        case NODE_INTEGER_LITERAL:  resolved_type = visitIntegerLiteral(&node->as.integer_literal); break;
        case NODE_FLOAT_LITERAL:    resolved_type = visitFloatLiteral(&node->as.float_literal); break;
        case NODE_CHAR_LITERAL:     resolved_type = visitCharLiteral(&node->as.char_literal); break;
        case NODE_STRING_LITERAL:   resolved_type = visitStringLiteral(&node->as.string_literal); break;
        case NODE_IDENTIFIER:       resolved_type = visitIdentifier(node); break;
        case NODE_BLOCK_STMT:       resolved_type = visitBlockStmt(&node->as.block_stmt); break;
        case NODE_EMPTY_STMT:       resolved_type = visitEmptyStmt(&node->as.empty_stmt); break;
        case NODE_IF_STMT:          resolved_type = visitIfStmt(node->as.if_stmt); break;
        case NODE_WHILE_STMT:       resolved_type = visitWhileStmt(&node->as.while_stmt); break;
        case NODE_RETURN_STMT:      resolved_type = visitReturnStmt(node, &node->as.return_stmt); break;
        case NODE_DEFER_STMT:       resolved_type = visitDeferStmt(&node->as.defer_stmt); break;
        case NODE_FOR_STMT:         resolved_type = visitForStmt(node->as.for_stmt); break;
        case NODE_EXPRESSION_STMT:  resolved_type = visitExpressionStmt(&node->as.expression_stmt); break;
        case NODE_SWITCH_EXPR:      resolved_type = visitSwitchExpr(node->as.switch_expr); break;
        case NODE_VAR_DECL:         resolved_type = visitVarDecl(node->as.var_decl); break;
        case NODE_FN_DECL:          resolved_type = visitFnDecl(node->as.fn_decl); break;
        case NODE_STRUCT_DECL:      resolved_type = visitStructDecl(node, node->as.struct_decl); break;
        case NODE_UNION_DECL:       resolved_type = visitUnionDecl(node, node->as.union_decl); break;
        case NODE_ENUM_DECL:        resolved_type = visitEnumDecl(node->as.enum_decl); break;
        case NODE_TYPE_NAME:        resolved_type = visitTypeName(node, &node->as.type_name); break;
        case NODE_POINTER_TYPE:     resolved_type = visitPointerType(&node->as.pointer_type); break;
        case NODE_ARRAY_TYPE:       resolved_type = visitArrayType(&node->as.array_type); break;
        case NODE_TRY_EXPR:         resolved_type = visitTryExpr(&node->as.try_expr); break;
        case NODE_CATCH_EXPR:       resolved_type = visitCatchExpr(node->as.catch_expr); break;
        case NODE_ERRDEFER_STMT:    resolved_type = visitErrdeferStmt(&node->as.errdefer_stmt); break;
        case NODE_COMPTIME_BLOCK:   resolved_type = visitComptimeBlock(&node->as.comptime_block); break;
        default:
            // TODO: Add error handling for unhandled node types.
            resolved_type = NULL;
            break;
    }

    node->resolved_type = resolved_type;
    return resolved_type;
}

Type* TypeChecker::visitUnaryOp(ASTNode* parent, ASTUnaryOpNode* node) {
    // In a unit test, the operand's type might already be resolved.
    Type* operand_type = node->operand->resolved_type ? node->operand->resolved_type : visit(node->operand);
    if (!operand_type) {
        return NULL; // Error already reported
    }

    switch (node->op) {
        case TOKEN_STAR: // Dereference operator (*)
            if (operand_type->kind == TYPE_POINTER) {
                return operand_type->as.pointer.base;
            }
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Cannot dereference a non-pointer type");
            return NULL;

        case TOKEN_AMPERSAND: { // Address-of operator (&)
            // The operand of '&' must be an l-value.
            bool is_lvalue = false;
            if (node->operand->type == NODE_IDENTIFIER) {
                is_lvalue = true;
            } else if (node->operand->type == NODE_ARRAY_ACCESS) {
                is_lvalue = true;
            } else if (node->operand->type == NODE_UNARY_OP && node->operand->as.unary_op.op == TOKEN_STAR) {
                 Type* inner_op_type = node->operand->as.unary_op.operand->resolved_type ? node->operand->as.unary_op.operand->resolved_type : visit(node->operand->as.unary_op.operand);
                 if (inner_op_type && inner_op_type->kind == TYPE_POINTER) {
                     is_lvalue = true;
                 }
            }

            if (is_lvalue) {
                return createPointerType(unit.getArena(), operand_type, false);
            }

            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Cannot take the address of an r-value");
            return NULL;
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
                return get_g_type_bool();
            }
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Invalid operand for logical not");
            return NULL;
        default:
            return NULL;
    }
}

Type* TypeChecker::visitBinaryOp(ASTNode* parent, ASTBinaryOpNode* node) {
    Type* left_type = node->left->resolved_type ? node->left->resolved_type : visit(node->left);
    Type* right_type = node->right->resolved_type ? node->right->resolved_type : visit(node->right);

    // If either operand is null, an error has already been reported.
    if (!left_type || !right_type) {
        return NULL;
    }

    // --- NEW: Check for void pointer arithmetic ---
    // C89 does not allow arithmetic on void pointers.
    if (node->op == TOKEN_PLUS || node->op == TOKEN_MINUS) {
        if ((left_type->kind == TYPE_POINTER && left_type->as.pointer.base->kind == TYPE_VOID) ||
            (right_type->kind == TYPE_POINTER && right_type->as.pointer.base->kind == TYPE_VOID)) {
            unit.getErrorHandler().report(ERR_INVALID_VOID_POINTER_ARITHMETIC, parent->loc, "pointer arithmetic on 'void*' is not allowed");
            return NULL; // Return error type
        }
    }


    // Check for compatible types based on the operator
    switch (node->op) {
        // Arithmetic operators
        case TOKEN_PLUS:
            // Pointer + Integer -> Pointer
            if (left_type->kind == TYPE_POINTER && isIntegerType(right_type)) {
                return left_type; // Result type is the pointer type
            }
            // Integer + Pointer -> Pointer
            if (isIntegerType(left_type) && right_type->kind == TYPE_POINTER) {
                return right_type; // Result type is the pointer type
            }
            // Numeric + Numeric (existing logic)
            if (isNumericType(left_type) && areTypesCompatible(left_type, right_type)) {
                return left_type; // For now, result type is the same as operands
            }
            // If none of the above match, it's an error for + (unless handled by generic error below)
            break; // Fall through to generic error

        case TOKEN_MINUS:
            // Pointer - Integer -> Pointer
            if (left_type->kind == TYPE_POINTER && isIntegerType(right_type)) {
                return left_type; // Result type is the pointer type
            }
            // Pointer - Pointer -> isize (if compatible base types)
            if (left_type->kind == TYPE_POINTER && right_type->kind == TYPE_POINTER) {
                if (areTypesCompatible(left_type->as.pointer.base, right_type->as.pointer.base)) {
                    Type* isize_type = resolvePrimitiveTypeName("isize");
                    if (!isize_type) {
                         unit.getErrorHandler().report(ERR_UNDECLARED_TYPE, parent->loc, "Internal Error: 'isize' type not found for pointer difference");
                         return NULL;
                    }
                    return isize_type; // Result type is isize
                } else {
                     unit.getErrorHandler().report(ERR_TYPE_MISMATCH, parent->loc, "cannot subtract pointers to incompatible types");
                     return NULL; // Return error type
                }
            }
            // Numeric - Numeric (existing logic)
            if (isNumericType(left_type) && areTypesCompatible(left_type, right_type)) {
                return left_type; // For now, result type is the same as operands
            }
            // If none of the above match, it's an error for - (unless handled by generic error below)
            break; // Fall through to generic error
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
                return get_g_type_bool();
            }
            break;

        default:
            // Operator not supported for binary expressions yet
            break;
    }

    // If we fall through, the types were not compatible for the given operator.
    char left_type_str[64];
    char right_type_str[64];
    typeToString(left_type, left_type_str, sizeof(left_type_str));
    typeToString(right_type, right_type_str, sizeof(right_type_str));
    char msg_buffer[256];
    snprintf(msg_buffer, sizeof(msg_buffer), "invalid operands for binary operator: '%s' and '%s'", left_type_str, right_type_str);
    unit.getErrorHandler().report(ERR_TYPE_MISMATCH, parent->loc, msg_buffer, unit.getArena());
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
    if (node->is_unsigned) {
        if (node->value <= 255) return resolvePrimitiveTypeName("u8");
        if (node->value <= 65535) return resolvePrimitiveTypeName("u16");
        if (node->value <= 4294967295) return resolvePrimitiveTypeName("u32");
        return resolvePrimitiveTypeName("u64");
    } else {
        // Since node->value is u64, we need to cast to i64 for signed comparison.
        i64 signed_value = (i64)node->value;
        if (signed_value >= -128 && signed_value <= 127) return resolvePrimitiveTypeName("i8");
        if (signed_value >= -32768 && signed_value <= 32767) return resolvePrimitiveTypeName("i16");
        if (signed_value >= -2147483648LL && signed_value <= 2147483647LL) return resolvePrimitiveTypeName("i32");
        return resolvePrimitiveTypeName("i64");
    }
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
        if (condition_type->kind == TYPE_VOID) {
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->condition->loc,
                                           "if statement condition cannot be void",
                                           unit.getArena());
        } else if (condition_type->kind != TYPE_BOOL &&
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
        if (condition_type->kind == TYPE_VOID) {
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->condition->loc,
                                           "while statement condition cannot be void",
                                           unit.getArena());
        } else if (condition_type->kind != TYPE_BOOL &&
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
    Type* return_type = node->expression ? visit(node->expression) : get_g_type_void();

    if (!current_fn_return_type) {
        // This can happen if we are parsing a return outside of a function,
        // which should be caught by the parser, but we check here for safety.
        return NULL;
    }

    // Case 1: Function is void
    if (current_fn_return_type->kind == TYPE_VOID) {
        if (node->expression) {
            // Error: void function returning a value
            unit.getErrorHandler().report(ERR_INVALID_RETURN_VALUE_IN_VOID_FUNCTION, node->expression->loc, "void function should not return a value");
        }
    }
    // Case 2: Function is non-void
    else {
        if (!node->expression) {
            // Error: non-void function must return a value
            unit.getErrorHandler().report(ERR_MISSING_RETURN_VALUE, parent->loc, "non-void function must return a value");
        } else if (return_type && !areTypesCompatible(current_fn_return_type, return_type)) {
            // Error: return type mismatch
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->expression->loc, "return type mismatch");
        }
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

    if (declared_type && declared_type->kind == TYPE_VOID) {
        unit.getErrorHandler().report(ERR_VARIABLE_CANNOT_BE_VOID, node->type->loc, "variables cannot be declared as 'void'");
        return NULL; // Stop processing this declaration
    }

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

    if (current_fn_return_type->kind != TYPE_VOID) {
        if (!all_paths_return(node->body)) {
            unit.getErrorHandler().report(ERR_MISSING_RETURN_VALUE, node->return_type->loc, "not all control paths return a value");
        }
    }

    unit.getSymbolTable().exitScope();

    current_fn_return_type = prev_fn_return_type;
    return NULL;
}

Type* TypeChecker::visitStructDecl(ASTNode* parent, ASTStructDeclNode* node) {
    validateStructOrUnionFields(parent);
    // TODO: The rest of the struct type checking logic will go here.
    // For now, we return NULL as no actual type is created yet.
    return NULL;
}

Type* TypeChecker::visitUnionDecl(ASTNode* parent, ASTUnionDeclNode* node) {
    validateStructOrUnionFields(parent);
    // TODO: The rest of the union type checking logic will go here.
    return NULL;
}

Type* TypeChecker::visitEnumDecl(ASTEnumDeclNode* node) {
    // 1. Determine the backing type.
    Type* backing_type = NULL;
    if (node->backing_type) {
        backing_type = visit(node->backing_type);
    } else {
        // Default backing type is i32, to be compatible with C enums.
        backing_type = resolvePrimitiveTypeName("i32");
    }

    if (!backing_type) {
        // This can happen if the backing type is an undeclared identifier.
        // The error would have been reported during visit(node->backing_type).
        return NULL;
    }

    // 2. Validate that the backing type is an integer.
    if (!isIntegerType(backing_type)) {
        fatalError(node->backing_type ? node->backing_type->loc : node->fields->length() > 0 ? (*node->fields)[0]->loc : SourceLocation(),
                   "Enum backing type must be an integer.");
        return NULL; // Unreachable
    }

    // 3. Process enum members.
    void* mem = unit.getArena().alloc(sizeof(DynamicArray<EnumMember>));
    DynamicArray<EnumMember>* members = new (mem) DynamicArray<EnumMember>(unit.getArena());

    i64 current_value = 0;
    for (size_t i = 0; i < node->fields->length(); ++i) {
        ASTNode* member_node_wrapper = (*node->fields)[i];
        ASTVarDeclNode* member_node = member_node_wrapper->as.var_decl;

        i64 member_value = 0;

        if (member_node->initializer) {
            ASTNode* init = member_node->initializer;
            if (init->type == NODE_INTEGER_LITERAL) {
                member_value = (i64)init->as.integer_literal.value;
            } else if (init->type == NODE_UNARY_OP && init->as.unary_op.op == TOKEN_MINUS) {
                ASTNode* operand = init->as.unary_op.operand;
                if (operand->type == NODE_INTEGER_LITERAL) {
                    member_value = -((i64)operand->as.integer_literal.value);
                } else {
                    fatalError(init->loc, "Enum member initializer must be a constant integer.");
                }
            } else {
                fatalError(init->loc, "Enum member initializer must be a constant integer.");
            }
            current_value = member_value;
        } else {
            member_value = current_value;
        }

        if (!checkIntegerLiteralFit(member_value, backing_type)) {
            fatalError(member_node_wrapper->loc, "Enum member value overflows its backing type.");
        }

        EnumMember member;
        member.name = member_node->name;
        member.value = member_value;
        members->append(member);

        current_value = member_value + 1;
    }

    // 4. Create and return the new enum type.
    return createEnumType(unit.getArena(), backing_type, members);
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
    // 1. Reject slices
    if (!node->size) {
        fatalError(node->element_type->loc, "Slices are not supported in C89 mode");
        return NULL; // fatalError aborts, but return for clarity
    }

    // 2. Ensure size is a constant integer literal
    if (node->size->type != NODE_INTEGER_LITERAL) {
        fatalError(node->size->loc, "Array size must be a constant integer literal");
        return NULL;
    }

    // 3. Resolve element type
    Type* element_type = visit(node->element_type);
    if (!element_type) {
        return NULL; // Error already reported
    }

    // 4. Create and return the new array type
    u64 array_size = node->size->as.integer_literal.value;
    return createArrayType(unit.getArena(), element_type, array_size);
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

bool TypeChecker::checkIntegerLiteralFit(i64 value, Type* int_type) {
    if (!isIntegerType(int_type)) {
        return false; // Should not happen with enums
    }

    switch (int_type->kind) {
        case TYPE_I8:   return value >= -128 && value <= 127;
        case TYPE_U8:   return value >= 0 && value <= 255;
        case TYPE_I16:  return value >= -32768 && value <= 32767;
        case TYPE_U16:  return value >= 0 && value <= 65535;
        case TYPE_I32:  return value >= -2147483648LL && value <= 2147483647LL;
        case TYPE_U32:  return value >= 0 && (u64)value <= 4294967295ULL;
        // For 64-bit types, i64 can hold all values, so we only check unsigned.
        case TYPE_I64:  return true;
        case TYPE_U64:  return value >= 0;
        // For isize/usize, we assume 32-bit for the bootstrap compiler.
        case TYPE_ISIZE: return value >= -2147483648LL && value <= 2147483647LL;
        case TYPE_USIZE: return value >= 0 && (u64)value <= 4294967295ULL;
        default: return false; // Not an integer type
    }
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

bool TypeChecker::all_paths_return(ASTNode* node) {
    if (!node) {
        return false;
    }

    switch (node->type) {
        case NODE_RETURN_STMT:
            return true;
        case NODE_BLOCK_STMT: {
            DynamicArray<ASTNode*>* statements = node->as.block_stmt.statements;
            if (statements->length() > 0) {
                return all_paths_return((*statements)[statements->length() - 1]);
            }
            return false;
        }
        case NODE_IF_STMT: {
            ASTIfStmtNode* if_stmt = node->as.if_stmt;
            if (if_stmt->else_block) {
                return all_paths_return(if_stmt->then_block) && all_paths_return(if_stmt->else_block);
            }
            return false;
        }
        default:
            return false;
    }
}

void TypeChecker::validateStructOrUnionFields(ASTNode* decl_node) {
    if (!decl_node) {
        return;
    }

    DynamicArray<ASTNode*>* fields = NULL;
    const char* container_type_str = "";

    if (decl_node->type == NODE_STRUCT_DECL) {
        fields = decl_node->as.struct_decl->fields;
        container_type_str = "Struct";
    } else if (decl_node->type == NODE_UNION_DECL) {
        fields = decl_node->as.union_decl->fields;
        container_type_str = "Union";
    } else {
        return; // Should not happen if called correctly
    }

    if (!fields) {
        return;
    }

    for (size_t i = 0; i < fields->length(); ++i) {
        ASTNode* field_node = (*fields)[i];
        if (field_node->type != NODE_STRUCT_FIELD) {
            continue; // Should not happen, but defensive check
        }

        ASTStructFieldNode* field = field_node->as.struct_field;
        // Resolve the field's type by visiting its type node.
        Type* field_type = visit(field->type);

        // If the type was resolved, check if it's C89 compatible.
        if (field_type && !is_c89_compatible(field_type)) {
            char msg_buffer[256];
            snprintf(msg_buffer, sizeof(msg_buffer), "%s field type is not C89 compatible.", container_type_str);
            fatalError(field->type->loc, msg_buffer);
        }
    }
}
