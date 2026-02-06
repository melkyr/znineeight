#include "type_checker.hpp"
#include "c89_type_mapping.hpp"
#include "ast_utils.hpp"
#include "type_system.hpp"
#include "error_handler.hpp"
#include "utils.hpp"
#include "platform.hpp"
#include <cstdlib> // For abort()

// MSVC 6.0 compatibility
#ifndef _MSC_VER
    typedef long long __int64;
#endif

// Helper to get the string representation of a binary operator token.
static const char* getTokenSpelling(TokenType op) {
    switch (op) {
        case TOKEN_PLUS: return "+";
        case TOKEN_MINUS: return "-";
        case TOKEN_STAR: return "*";
        case TOKEN_SLASH: return "/";
        case TOKEN_PERCENT: return "%";
        case TOKEN_EQUAL_EQUAL: return "==";
        case TOKEN_BANG_EQUAL: return "!=";
        case TOKEN_LESS: return "<";
        case TOKEN_LESS_EQUAL: return "<=";
        case TOKEN_GREATER: return ">";
        case TOKEN_GREATER_EQUAL: return ">=";
        case TOKEN_AMPERSAND: return "&";
        case TOKEN_PIPE: return "|";
        case TOKEN_CARET: return "^";
        case TOKEN_LARROW2: return "<<";
        case TOKEN_RARROW2: return ">>";
        default: return "unknown";
    }
}

TypeChecker::TypeChecker(CompilationUnit& unit) : unit(unit), current_fn_return_type(NULL) {
}

void TypeChecker::check(ASTNode* root) {
    if (root && root->type == NODE_BLOCK_STMT && root->as.block_stmt.statements) {
        // First pass: Process function declarations and global variables
        for (size_t i = 0; i < root->as.block_stmt.statements->length(); ++i) {
            ASTNode* top_level_node = (*root->as.block_stmt.statements)[i];
            if (top_level_node && top_level_node->type == NODE_FN_DECL) {
                // We could do a pre-scan here, but visit() handles it for now.
            }
        }

        // Main pass: visit children directly to avoid root block scope level issue
        for (size_t i = 0; i < root->as.block_stmt.statements->length(); ++i) {
            visit((*root->as.block_stmt.statements)[i]);
        }
    } else {
        visit(root);
    }
}

Type* TypeChecker::visit(ASTNode* node) {
    if (!node) {
        return NULL;
    }

    Type* resolved_type = NULL;
    switch (node->type) {
        case NODE_ASSIGNMENT:       resolved_type = visitAssignment(node->as.assignment); break;
        case NODE_COMPOUND_ASSIGNMENT: resolved_type = visitCompoundAssignment(node->as.compound_assignment); break;
        case NODE_UNARY_OP:         resolved_type = visitUnaryOp(node, &node->as.unary_op); break;
        case NODE_BINARY_OP:        resolved_type = visitBinaryOp(node, node->as.binary_op); break;
        case NODE_FUNCTION_CALL:    resolved_type = visitFunctionCall(node->as.function_call); break;
        case NODE_ARRAY_ACCESS:     resolved_type = visitArrayAccess(node->as.array_access); break;
        case NODE_ARRAY_SLICE:      resolved_type = visitArraySlice(node->as.array_slice); break;
        case NODE_MEMBER_ACCESS:    resolved_type = visitMemberAccess(node, node->as.member_access); break;
        case NODE_STRUCT_INITIALIZER: resolved_type = visitStructInitializer(node->as.struct_initializer); break;
        case NODE_BOOL_LITERAL:     resolved_type = visitBoolLiteral(node, &node->as.bool_literal); break;
        case NODE_NULL_LITERAL:     resolved_type = visitNullLiteral(node); break;
        case NODE_INTEGER_LITERAL:  resolved_type = visitIntegerLiteral(node, &node->as.integer_literal); break;
        case NODE_FLOAT_LITERAL:    resolved_type = visitFloatLiteral(node, &node->as.float_literal); break;
        case NODE_CHAR_LITERAL:     resolved_type = visitCharLiteral(node, &node->as.char_literal); break;
        case NODE_STRING_LITERAL:   resolved_type = visitStringLiteral(node, &node->as.string_literal); break;
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
        case NODE_VAR_DECL:         resolved_type = visitVarDecl(node, node->as.var_decl); break;
        case NODE_FN_DECL:          resolved_type = visitFnDecl(node->as.fn_decl); break;
        case NODE_STRUCT_DECL:      resolved_type = visitStructDecl(node, node->as.struct_decl); break;
        case NODE_UNION_DECL:       resolved_type = visitUnionDecl(node, node->as.union_decl); break;
        case NODE_ENUM_DECL:        resolved_type = visitEnumDecl(node->as.enum_decl); break;
        case NODE_ERROR_SET_DEFINITION: resolved_type = visitErrorSetDefinition(node->as.error_set_decl); break;
        case NODE_ERROR_SET_MERGE:  resolved_type = visitErrorSetMerge(node->as.error_set_merge); break;
        case NODE_TYPE_NAME:        resolved_type = visitTypeName(node, &node->as.type_name); break;
        case NODE_POINTER_TYPE:     resolved_type = visitPointerType(&node->as.pointer_type); break;
        case NODE_ARRAY_TYPE:       resolved_type = visitArrayType(&node->as.array_type); break;
        case NODE_ERROR_UNION_TYPE: resolved_type = visitErrorUnionType(node->as.error_union_type); break;
        case NODE_OPTIONAL_TYPE:    resolved_type = visitOptionalType(node->as.optional_type); break;
        case NODE_TRY_EXPR:         resolved_type = visitTryExpr(&node->as.try_expr); break;
        case NODE_CATCH_EXPR:       resolved_type = visitCatchExpr(node->as.catch_expr); break;
        case NODE_ORELSE_EXPR:      resolved_type = visitOrelseExpr(node->as.orelse_expr); break;
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
        case TOKEN_STAR:
        case TOKEN_DOT_ASTERISK: { // Dereference operator (*) or (.*)
            // Check for null literal dereference first, as it's a special case.
            if (node->operand->type == NODE_NULL_LITERAL ||
                (node->operand->type == NODE_INTEGER_LITERAL && node->operand->as.integer_literal.value == 0)) {
                unit.getErrorHandler().reportWarning(WARN_NULL_DEREFERENCE, node->operand->loc, "Dereferencing null pointer may cause undefined behavior");
                // The type of '*null' is technically undefined, but for the compiler to proceed,
                // we can treat it as yielding a void type. This prevents cascading errors.
                return get_g_type_void();
            }

            // Now, perform standard pointer checks.
            if (operand_type->kind != TYPE_POINTER) {
                char type_str[64];
                typeToString(operand_type, type_str, sizeof(type_str));
                char msg_buffer[256];
                char* current = msg_buffer;
                size_t remaining = sizeof(msg_buffer);
                safe_append(current, remaining, "Cannot dereference a non-pointer type '");
                safe_append(current, remaining, type_str);
                safe_append(current, remaining, "'");
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, msg_buffer, unit.getArena());
                return NULL;
            }

            Type* base_type = operand_type->as.pointer.base;
            if (base_type->kind == TYPE_VOID) {
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->operand->loc, "Cannot dereference a void pointer");
                return NULL;
            }

            return base_type;
        }
        case TOKEN_AMPERSAND: { // Address-of operator (&)
            // The operand of '&' must be an l-value.
            bool is_lvalue;
            switch (node->operand->type) {
                case NODE_IDENTIFIER:
                case NODE_ARRAY_ACCESS:
                    is_lvalue = true;
                    break;
                case NODE_UNARY_OP:
                    is_lvalue = (node->operand->as.unary_op.op == TOKEN_STAR);
                    break;
                default:
                    is_lvalue = false;
                    break;
            }

            if (is_lvalue) {
                return createPointerType(unit.getArena(), operand_type, false);
            }

            unit.getErrorHandler().report(ERR_LVALUE_EXPECTED, node->operand->loc, "l-value expected as operand of address-of operator '&'");
            fatalError(node->operand->loc, "l-value expected as operand of address-of operator '&'");
            return NULL; // Unreachable
        }
        case TOKEN_MINUS:
            // C89 Unary '-' is only valid for numeric types.
            if (isNumericType(operand_type)) {
                return operand_type; // Negation doesn't change numeric type.
            }
            fatalError(parent->loc, "Unary '-' operator cannot be applied to non-numeric types.");
            return NULL; // Unreachable

        case TOKEN_BANG:
            // Logical NOT is valid for bools, integers, and pointers.
            if (operand_type->kind == TYPE_BOOL || isIntegerType(operand_type) || operand_type->kind == TYPE_POINTER) {
                return get_g_type_bool();
            }
            fatalError(parent->loc, "Logical NOT operator '!' can only be applied to bools, integers, or pointers.");
            return NULL; // Unreachable

        case TOKEN_TILDE:
            // Bitwise NOT is only valid for integer types in C89.
            if (isIntegerType(operand_type)) {
                return operand_type; // Bitwise NOT doesn't change the type.
            }
            fatalError(parent->loc, "Bitwise NOT operator '~' can only be applied to integer types.");
            return NULL; // Unreachable

        default:
            // Should not happen if parser is correct.
            fatalError(parent->loc, "Unsupported unary operator.");
            return NULL; // Unreachable
    }
}

Type* TypeChecker::visitBinaryOp(ASTNode* parent, ASTBinaryOpNode* node) {
    Type* left_type = node->left->resolved_type ? node->left->resolved_type : visit(node->left);
    Type* right_type = node->right->resolved_type ? node->right->resolved_type : visit(node->right);

    if (!left_type || !right_type) {
        return NULL; // Error already reported
    }

    return checkBinaryOperation(left_type, right_type, node->op, parent->loc);
}

Type* TypeChecker::checkBinaryOperation(Type* left_type, Type* right_type, TokenType op, SourceLocation loc) {
    switch (op) {
// --- Arithmetic Operators ---
        case TOKEN_PLUS:
        case TOKEN_MINUS:
        case TOKEN_STAR:
        case TOKEN_SLASH:
        case TOKEN_PERCENT: {
            Type* promoted_type = checkArithmeticWithLiteralPromotion(left_type, right_type, op);
            if (promoted_type) {
                return promoted_type;
            }

            // First, check for void pointer arithmetic (must be rejected)
            if (op == TOKEN_PLUS || op == TOKEN_MINUS) {
                if ((left_type->kind == TYPE_POINTER && left_type->as.pointer.base->kind == TYPE_VOID) ||
                    (right_type->kind == TYPE_POINTER && right_type->as.pointer.base->kind == TYPE_VOID)) {
                    unit.getErrorHandler().report(ERR_INVALID_VOID_POINTER_ARITHMETIC, loc, "pointer arithmetic on 'void*' is not allowed", unit.getArena());
                    return NULL;
                }
            }

            Type* pointer_arithmetic_result = checkPointerArithmetic(left_type, right_type, op, loc);
            if (pointer_arithmetic_result) {
                return pointer_arithmetic_result;
            }

            // Handle regular numeric arithmetic with strict C89 rules
            if (isNumericType(left_type) && isNumericType(right_type)) {
                // C89 strict rule: operands must be exactly the same type
                if (left_type == right_type) {
                    return left_type; // Result type is same as operands
                } else {
                    // Different numeric types - not allowed in C89
                    char left_type_str[64];
                    char right_type_str[64];
                    typeToString(left_type, left_type_str, sizeof(left_type_str));
                    typeToString(right_type, right_type_str, sizeof(right_type_str));
                    char msg_buffer[256];
                    char* current = msg_buffer;
                    size_t remaining = sizeof(msg_buffer);
                    safe_append(current, remaining, "arithmetic operation '");
                    safe_append(current, remaining, getTokenSpelling(op));
                    safe_append(current, remaining, "' requires operands of the same type. Got '");
                    safe_append(current, remaining, left_type_str);
                    safe_append(current, remaining, "' and '");
                    safe_append(current, remaining, right_type_str);
                    safe_append(current, remaining, "'.");
                    unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
                    return NULL;
                }
            }

            // Neither pointer nor compatible numeric arithmetic
            char left_type_str[64];
            char right_type_str[64];
            typeToString(left_type, left_type_str, sizeof(left_type_str));
            typeToString(right_type, right_type_str, sizeof(right_type_str));
            char msg_buffer[256];
            char* current = msg_buffer;
            size_t remaining = sizeof(msg_buffer);
            safe_append(current, remaining, "invalid operands for arithmetic operator '");
            safe_append(current, remaining, getTokenSpelling(op));
            safe_append(current, remaining, "': '");
            safe_append(current, remaining, left_type_str);
            safe_append(current, remaining, "' and '");
            safe_append(current, remaining, right_type_str);
            safe_append(current, remaining, "'");
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
            return NULL;
        }

// --- Comparison Operators ---
        case TOKEN_EQUAL_EQUAL:
        case TOKEN_BANG_EQUAL:
        case TOKEN_LESS:
        case TOKEN_LESS_EQUAL:
        case TOKEN_GREATER:
        case TOKEN_GREATER_EQUAL:
        {
            // Check for compatible types for comparison
            if (isNumericType(left_type) && isNumericType(right_type)) {
                if (left_type == right_type) {
                    return get_g_type_bool(); // Result is always bool
                } else {
                    char left_type_str[64];
                    char right_type_str[64];
                    typeToString(left_type, left_type_str, sizeof(left_type_str));
                    typeToString(right_type, right_type_str, sizeof(right_type_str));
                    char msg_buffer[256];
                    char* current = msg_buffer;
                    size_t remaining = sizeof(msg_buffer);
                    safe_append(current, remaining, "comparison operation '");
                    safe_append(current, remaining, getTokenSpelling(op));
                    safe_append(current, remaining, "' requires operands of the same type. Got '");
                    safe_append(current, remaining, left_type_str);
                    safe_append(current, remaining, "' and '");
                    safe_append(current, remaining, right_type_str);
                    safe_append(current, remaining, "'.");
                    unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
                    return NULL;
                }
            }
                // Pointer comparisons (equality only for ordering operators)
            else if ((left_type->kind == TYPE_POINTER || left_type->kind == TYPE_NULL) &&
                     (right_type->kind == TYPE_POINTER || right_type->kind == TYPE_NULL)) {
                // Equality operators can work with any compatible pointer types
                if (op == TOKEN_EQUAL_EQUAL || op == TOKEN_BANG_EQUAL) {
                    if (left_type->kind == TYPE_NULL || right_type->kind == TYPE_NULL) {
                        return get_g_type_bool(); // Result is always bool
                    }
                    if (areTypesCompatible(left_type->as.pointer.base, right_type->as.pointer.base) ||
                        (left_type->as.pointer.base->kind == TYPE_VOID) ||
                        (right_type->as.pointer.base->kind == TYPE_VOID)) {
                        return get_g_type_bool(); // Result is always bool
                    } else {
                        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, "cannot compare pointers to incompatible types");
                        return NULL;
                    }
                }
                    // Ordering operators only work with compatible pointers (not void*)
                else {
                    if (areTypesCompatible(left_type->as.pointer.base, right_type->as.pointer.base)) {
                        return get_g_type_bool(); // Result is always bool
                    } else {
                        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, "cannot compare pointers to incompatible types for ordering");
                        return NULL;
                    }
                }
            }
                // Boolean comparisons
            else if (left_type->kind == TYPE_BOOL && right_type->kind == TYPE_BOOL) {
                return get_g_type_bool(); // Result is always bool
            }
                // If types are not compatible for comparison
            else {
                char left_type_str[64];
                char right_type_str[64];
                typeToString(left_type, left_type_str, sizeof(left_type_str));
                typeToString(right_type, right_type_str, sizeof(right_type_str));
                char msg_buffer[256];
                char* current = msg_buffer;
                size_t remaining = sizeof(msg_buffer);
                safe_append(current, remaining, "invalid operands for comparison operator '");
                safe_append(current, remaining, getTokenSpelling(op));
                safe_append(current, remaining, "': '");
                safe_append(current, remaining, left_type_str);
                safe_append(current, remaining, "' and '");
                safe_append(current, remaining, right_type_str);
                safe_append(current, remaining, "'");
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
                return NULL;
            }
        }

// --- Bitwise Operators ---
        case TOKEN_AMPERSAND:
        case TOKEN_PIPE:
        case TOKEN_CARET:
        case TOKEN_LARROW2:
        case TOKEN_RARROW2:
        {
            // Both operands must be integer types for bitwise operations
            if (isIntegerType(left_type) && isIntegerType(right_type)) {
                // For <<, >>: Result type is the type of the left operand (the one being shifted)
                if (op == TOKEN_LARROW2 || op == TOKEN_RARROW2) {
                    if (left_type == right_type) {
                        return left_type; // Result is the type of the value being shifted
                    } else {
                        char left_type_str[64];
                        char right_type_str[64];
                        typeToString(left_type, left_type_str, sizeof(left_type_str));
                        typeToString(right_type, right_type_str, sizeof(right_type_str));
                        char msg_buffer[256];
                        char* current = msg_buffer;
                        size_t remaining = sizeof(msg_buffer);
                        safe_append(current, remaining, "bitwise shift operation '");
                        safe_append(current, remaining, getTokenSpelling(op));
                        safe_append(current, remaining, "' requires operands of the same type. Got '");
                        safe_append(current, remaining, left_type_str);
                        safe_append(current, remaining, "' and '");
                        safe_append(current, remaining, right_type_str);
                        safe_append(current, remaining, "'.");
                        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
                        return NULL;
                    }
                } else { // &, |, ^
                    // C89 rules: Operands must be the same type for these operators too
                    if (left_type == right_type) {
                        return left_type; // Result is the same type
                    } else {
                        char left_type_str[64];
                        char right_type_str[64];
                        typeToString(left_type, left_type_str, sizeof(left_type_str));
                        typeToString(right_type, right_type_str, sizeof(right_type_str));
                        char msg_buffer[256];
                        char* current = msg_buffer;
                        size_t remaining = sizeof(msg_buffer);
                        safe_append(current, remaining, "bitwise operation '");
                        safe_append(current, remaining, getTokenSpelling(op));
                        safe_append(current, remaining, "' requires operands of the same type. Got '");
                        safe_append(current, remaining, left_type_str);
                        safe_append(current, remaining, "' and '");
                        safe_append(current, remaining, right_type_str);
                        safe_append(current, remaining, "'.");
                        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
                        return NULL;
                    }
                }
            } else {
                char left_type_str[64];
                char right_type_str[64];
                typeToString(left_type, left_type_str, sizeof(left_type_str));
                typeToString(right_type, right_type_str, sizeof(right_type_str));
                char msg_buffer[256];
                char* current = msg_buffer;
                size_t remaining = sizeof(msg_buffer);
                safe_append(current, remaining, "invalid operands for bitwise operator '");
                safe_append(current, remaining, getTokenSpelling(op));
                safe_append(current, remaining, "': '");
                safe_append(current, remaining, left_type_str);
                safe_append(current, remaining, "' and '");
                safe_append(current, remaining, right_type_str);
                safe_append(current, remaining, "'. Operands must be integer types.");
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
                return NULL;
            }
        }

// --- Logical Operators ---
        case TOKEN_AND:
        case TOKEN_OR:
        {
            // Both operands must be bool type for logical operations
            if (left_type->kind == TYPE_BOOL && right_type->kind == TYPE_BOOL) {
                return get_g_type_bool(); // Result is always bool
            } else {
                char left_type_str[64];
                char right_type_str[64];
                typeToString(left_type, left_type_str, sizeof(left_type_str));
                typeToString(right_type, right_type_str, sizeof(right_type_str));
                char msg_buffer[256];
                char* current = msg_buffer;
                size_t remaining = sizeof(msg_buffer);
                safe_append(current, remaining, "invalid operands for logical operator '");
                safe_append(current, remaining, getTokenSpelling(op));
                safe_append(current, remaining, "': '");
                safe_append(current, remaining, left_type_str);
                safe_append(current, remaining, "' and '");
                safe_append(current, remaining, right_type_str);
                safe_append(current, remaining, "'. Operands must be bool types.");
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
                return NULL;
            }
        }

        default: {
            char msg_buffer[256];
            char* current = msg_buffer;
            size_t remaining = sizeof(msg_buffer);
            safe_append(current, remaining, "Unsupported binary operator in type checker: ");
            safe_append(current, remaining, getTokenSpelling(op));
            unit.getErrorHandler().report(ERR_INVALID_OPERATION, loc, msg_buffer, unit.getArena());
            return NULL;
        }
    }
}

Type* TypeChecker::visitFunctionCall(ASTFunctionCallNode* node) {
    // Detect and catalogue generic instantiation if this is a generic call
    catalogGenericInstantiation(node);

    // --- NEW LOGIC FOR TASK 119 ---
    // Check if the callee is a direct identifier call to a banned function.
    if (node->callee->type == NODE_IDENTIFIER) {
        const char* callee_name = node->callee->as.identifier.name;
        static const char* banned_functions[] = {
            "malloc", "calloc", "realloc", "free", "aligned_alloc",
            "strdup", "memcpy", "memset", "strcpy"
        };
        for (size_t i = 0; i < sizeof(banned_functions) / sizeof(banned_functions[0]); ++i) {
            if (plat_strcmp(callee_name, banned_functions[i]) == 0) {
                char msg_buffer[256];
                char* current = msg_buffer;
                size_t remaining = sizeof(msg_buffer);
                safe_append(current, remaining, "Call to '");
                safe_append(current, remaining, callee_name);
                safe_append(current, remaining, "' is forbidden. Use the project's ArenaAllocator for safe memory management.");
                fatalError(node->callee->loc, msg_buffer);
                return NULL; // Unreachable
            }
        }
    }
    // --- END NEW LOGIC FOR TASK 119 ---

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
        char expected_buf[21], actual_buf[21];
        simple_itoa(expected_args, expected_buf, sizeof(expected_buf));
        simple_itoa(actual_args, actual_buf, sizeof(actual_buf));
        char* current = msg_buffer;
        size_t remaining = sizeof(msg_buffer);
        safe_append(current, remaining, "wrong number of arguments to function call, expected ");
        safe_append(current, remaining, expected_buf);
        safe_append(current, remaining, ", got ");
        safe_append(current, remaining, actual_buf);
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
            char arg_num_buf[21];
            simple_itoa(i + 1, arg_num_buf, sizeof(arg_num_buf));
            char* current = msg_buffer;
            size_t remaining = sizeof(msg_buffer);
            safe_append(current, remaining, "incompatible argument type for argument ");
            safe_append(current, remaining, arg_num_buf);
            safe_append(current, remaining, ", expected '");
            safe_append(current, remaining, param_type_str);
            safe_append(current, remaining, "', got '");
            safe_append(current, remaining, arg_type_str);
            safe_append(current, remaining, "'");
            fatalError(arg_node->loc, msg_buffer);
        }
    }

    return callee_type->as.function.return_type;
}

Type* TypeChecker::visitAssignment(ASTAssignmentNode* node) {
    // Step 0: Ensure the l-value is a valid l-value.
    // This check is implicitly handled by isLValueConst and the type checks below.
    // Identifiers, array accesses, and pointer dereferences are the main valid l-values.

    // First, resolve the type of the left-hand side.
    Type* lvalue_type = visit(node->lvalue);
    if (!lvalue_type) {
        return NULL; // Error already reported (e.g., undeclared variable)
    }

    // Step 1: Check if the l-value is const.
    if (isLValueConst(node->lvalue)) {
        fatalError(node->lvalue->loc, "Cannot assign to a constant value (l-value is const).");
        return NULL; // Unreachable
    }

    // Step 2: Resolve the type of the right-hand side.
    Type* rvalue_type = visit(node->rvalue);
    if (!rvalue_type) {
        return NULL; // Error already reported.
    }

    // Step 3: Check if the r-value type is assignable to the l-value type using strict C89 rules.
    if (!IsTypeAssignableTo(rvalue_type, lvalue_type, node->rvalue->loc)) {
        // IsTypeAssignableTo already reports a detailed error.
        // We will now call fatalError to halt compilation as requested.
        char ltype_str[64];
        char rtype_str[64];
        typeToString(lvalue_type, ltype_str, sizeof(ltype_str));
        typeToString(rvalue_type, rtype_str, sizeof(rtype_str));

        char msg_buffer[256];
        char* current = msg_buffer;
        size_t remaining = sizeof(msg_buffer);
        safe_append(current, remaining, "incompatible types in assignment, cannot assign '");
        safe_append(current, remaining, rtype_str);
        safe_append(current, remaining, "' to '");
        safe_append(current, remaining, ltype_str);
        safe_append(current, remaining, "'");
        fatalError(node->rvalue->loc, msg_buffer);
        return NULL; // Unreachable
    }

    // The type of an assignment expression is the type of the l-value.
    return lvalue_type;
}

Type* TypeChecker::visitCompoundAssignment(ASTCompoundAssignmentNode* node) {
    // First, resolve the type of the left-hand side.
    Type* lvalue_type = visit(node->lvalue);
    if (!lvalue_type) {
        return NULL; // Error already reported.
    }

    // Step 1: Check if the l-value is const.
    if (isLValueConst(node->lvalue)) {
        fatalError(node->lvalue->loc, "Cannot assign to a constant value (l-value is const).");
        return NULL; // Unreachable
    }

    // Step 2: Resolve the type of the right-hand side.
    Type* rvalue_type = visit(node->rvalue);
    if (!rvalue_type) {
        return NULL; // Error already reported.
    }

    // Step 3: Map the compound operator to a binary operator.
    TokenType binary_op;
    switch (node->op) {
        case TOKEN_PLUS_EQUAL:      binary_op = TOKEN_PLUS; break;
        case TOKEN_MINUS_EQUAL:     binary_op = TOKEN_MINUS; break;
        case TOKEN_STAR_EQUAL:      binary_op = TOKEN_STAR; break;
        case TOKEN_SLASH_EQUAL:     binary_op = TOKEN_SLASH; break;
        case TOKEN_PERCENT_EQUAL:   binary_op = TOKEN_PERCENT; break;
        case TOKEN_AMPERSAND_EQUAL: binary_op = TOKEN_AMPERSAND; break;
        case TOKEN_PIPE_EQUAL:      binary_op = TOKEN_PIPE; break;
        case TOKEN_CARET_EQUAL:     binary_op = TOKEN_CARET; break;
        case TOKEN_LARROW2_EQUAL:   binary_op = TOKEN_LARROW2; break;
        case TOKEN_RARROW2_EQUAL:   binary_op = TOKEN_RARROW2; break;
        default:
            fatalError(node->lvalue->loc, "Unsupported compound assignment operator.");
            return NULL; // Unreachable
    }

    // Step 4: Check if the underlying binary operation is valid.
    Type* result_type = checkBinaryOperation(lvalue_type, rvalue_type, binary_op, node->lvalue->loc);
    if (!result_type) {
        // Error already reported by checkBinaryOperation. We can just return.
        return NULL;
    }

    // Step 5: Ensure the result of the operation can be assigned back to the l-value.
    if (!IsTypeAssignableTo(result_type, lvalue_type, node->lvalue->loc)) {
        // IsTypeAssignableTo already reports a detailed error.
        // We will now call fatalError to halt compilation as requested.
        char ltype_str[64];
        char result_type_str[64];
        typeToString(lvalue_type, ltype_str, sizeof(ltype_str));
        typeToString(result_type, result_type_str, sizeof(result_type_str));

        char msg_buffer[256];
        char* current = msg_buffer;
        size_t remaining = sizeof(msg_buffer);
        safe_append(current, remaining, "result of operator '");
        safe_append(current, remaining, getTokenSpelling(binary_op));
        safe_append(current, remaining, "' is '");
        safe_append(current, remaining, result_type_str);
        safe_append(current, remaining, "', which cannot be assigned to type '");
        safe_append(current, remaining, ltype_str);
        safe_append(current, remaining, "'");
        fatalError(node->lvalue->loc, msg_buffer);
        return NULL; // Unreachable
    }

    // The type of a compound assignment expression is the type of the l-value.
    return lvalue_type;
}

/**
 * @brief Checks if a binary operation is compatible with the types of its operands.
 *
 * This is a simplified check focusing on basic numeric types as per the bootstrap requirements.
 *
 * @param left The type of the left operand.
 * @param right The type of the right operand.
 * @param op The token type of the binary operator.
 * @param loc The source location for error reporting.
 * @return The resulting type of the operation, or NULL if incompatible.
 */
Type* TypeChecker::checkBinaryOpCompatibility(Type* left, Type* right, TokenType /*op*/, SourceLocation /*loc*/) {
    if ((left->kind >= TYPE_I8 && left->kind <= TYPE_F64) && (right->kind >= TYPE_I8 && right->kind <= TYPE_F64)) {
        return left; // Simplified promotion
    }
    return NULL;
}

/**
 * @brief Finds a field within a struct type.
 *
 * This is a placeholder implementation to allow the compiler to build.
 * It does not yet perform a real field lookup.
 *
 * @param struct_type The struct type to search within.
 * @param field_name The name of the field to find.
 * @return Returns NULL as it is a placeholder.
 */
Type* TypeChecker::findStructField(Type* struct_type, const char* field_name) {
    if (struct_type->kind != TYPE_STRUCT) {
        return NULL;
    }

    DynamicArray<StructField>* fields = struct_type->as.struct_details.fields;
    for (size_t i = 0; i < fields->length(); ++i) {
        if (identifiers_equal((*fields)[i].name, field_name)) {
            return (*fields)[i].type;
        }
    }
    return NULL;
}

Type* TypeChecker::visitArrayAccess(ASTArrayAccessNode* node) {
    Type* array_type = visit(node->array);
    Type* index_type = visit(node->index);

    if (!array_type || !index_type) {
        return NULL; // Error already reported
    }

    if (array_type->kind != TYPE_ARRAY) {
        fatalError(node->array->loc, "Cannot index into a non-array type.");
        return NULL;
    }

    // Attempt to evaluate the index as a compile-time constant.
    i64 index_value;
    if (evaluateConstantExpression(node->index, &index_value)) {
        u64 array_size = array_type->as.array.size;
        if (index_value < 0 || (u64)index_value >= array_size) {
            fatalError(node->index->loc, "Array index out of bounds.");
            return NULL;
        }
    }

    return array_type->as.array.element_type;
}

Type* TypeChecker::visitArraySlice(ASTArraySliceNode* node) {
    // Slice expressions are not supported in C89.
    unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->array->loc, "Slice expressions (e.g., array[start..end]) are not supported in C89 mode.", unit.getArena());
    return NULL;
}

Type* TypeChecker::visitBoolLiteral(ASTNode* /*parent*/, ASTBoolLiteralNode* /*node*/) {
    return resolvePrimitiveTypeName("bool");
}

Type* TypeChecker::visitNullLiteral(ASTNode* /*node*/) {
    return get_g_type_null();
}

Type* TypeChecker::visitIntegerLiteral(ASTNode* /*parent*/, ASTIntegerLiteralNode* node) {
    // This logic is intentionally C-like. Integer literals are inferred as i32
    // by default, unless the value is too large. This was changed from a
    // "smallest possible type" inference to fix a large number of test failures
    // after stricter assignment rules were put in place.
    if (node->is_unsigned) {
        if (node->value <= 4294967295U) return resolvePrimitiveTypeName("u32");
        return resolvePrimitiveTypeName("u64");
    } else {
        i64 signed_value = (i64)node->value;
        if (signed_value >= -2147483648LL && signed_value <= 2147483647LL) {
            return resolvePrimitiveTypeName("i32");
        }
        return resolvePrimitiveTypeName("i64");
    }
}

Type* TypeChecker::visitFloatLiteral(ASTNode* /*parent*/, ASTFloatLiteralNode* /*node*/) {
    return resolvePrimitiveTypeName("f64");
}

Type* TypeChecker::visitCharLiteral(ASTNode* /*parent*/, ASTCharLiteralNode* /*node*/) {
    return resolvePrimitiveTypeName("u8");
}

Type* TypeChecker::visitStringLiteral(ASTNode* /*parent*/, ASTStringLiteralNode* /*node*/) {
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

Type* TypeChecker::visitEmptyStmt(ASTEmptyStmtNode* /*node*/) {
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
    Type* cond_type = visit(node->expression);
    if (!cond_type) return NULL;

    if (!isIntegerType(cond_type) && cond_type->kind != TYPE_ENUM) {
        fatalError(node->expression->loc, "Switch condition must be integer or enum type");
        return NULL;
    }

    Type* result_type = NULL;
    for (size_t i = 0; i < node->prongs->length(); ++i) {
        ASTSwitchProngNode* prong = (*node->prongs)[i];

        if (!prong->is_else) {
            for (size_t j = 0; j < prong->cases->length(); ++j) {
                ASTNode* case_expr = (*prong->cases)[j];
                Type* case_type = visit(case_expr);
                if (case_type) {
                    // Check compatibility between condition and case
                    if (!areTypesCompatible(cond_type, case_type)) {
                        // Allow enum members if cond is enum
                        if (cond_type->kind == TYPE_ENUM && case_type->kind == TYPE_ENUM) {
                            if (cond_type != case_type) {
                                fatalError(case_expr->loc, "Switch case type mismatch");
                            }
                        } else if (cond_type->kind == TYPE_ENUM && isIntegerType(case_type)) {
                            // C89 allows integers for enum cases
                        } else if (isIntegerType(cond_type) && case_type->kind == TYPE_ENUM) {
                             // Allow enum cases for integer discriminant?
                        } else {
                            fatalError(case_expr->loc, "Switch case type mismatch");
                        }
                    }
                }
            }
        }

        Type* prong_type = visit(prong->body);
        if (!result_type) {
            result_type = prong_type;
        } else if (prong_type && result_type != prong_type) {
            // Require exact match for switch expression resulting type for now.
        }
    }

    return result_type;
}

Type* TypeChecker::visitVarDecl(ASTNode* parent, ASTVarDeclNode* node) {
    Type* declared_type = node->type ? visit(node->type) : NULL;

    if (declared_type && declared_type->kind == TYPE_VOID) {
        unit.getErrorHandler().report(ERR_VARIABLE_CANNOT_BE_VOID, node->type ? node->type->loc : parent->loc, "variables cannot be declared as 'void'");
        return NULL; // Stop processing this declaration
    }

    // Special handling for integer literal initializers to support C89-style assignments.
    if (node->initializer && node->initializer->type == NODE_INTEGER_LITERAL) {
        ASTIntegerLiteralNode* literal_node = &node->initializer->as.integer_literal;

        // Create a temporary literal type to pass to the checker.
        Type literal_type;
        literal_type.kind = TYPE_INTEGER_LITERAL;
        literal_type.as.integer_literal.value = (i64)literal_node->value;

        if (declared_type) {
            if (!canLiteralFitInType(&literal_type, declared_type)) {
                // Report a more specific error for overflow.
                char msg_buffer[256];
                char* current = msg_buffer;
                size_t remaining = sizeof(msg_buffer);
                safe_append(current, remaining, "integer literal overflows declared type");
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->initializer->loc, msg_buffer, unit.getArena());
            }
        } else {
            // Infer type from integer literal
            declared_type = visit(node->initializer);
        }
    } else {
        // For all other cases, use the standard assignment validation.
        Type* initializer_type = visit(node->initializer);
        if (declared_type) {
            if (initializer_type && !IsTypeAssignableTo(initializer_type, declared_type, node->initializer->loc)) {
                // IsTypeAssignableTo already reports a detailed error.
            }
        } else {
            // Infer type from initializer
            declared_type = initializer_type;
        }
    }

    // Update the symbol in the current scope with flags
    Symbol* existing_sym = unit.getSymbolTable().lookupInCurrentScope(node->name);
    if (existing_sym) {
        existing_sym->symbol_type = declared_type;
        existing_sym->details = node;

        // If we are inside a function body, current_fn_return_type will be non-NULL
        bool is_local = (current_fn_return_type != NULL);
        existing_sym->flags = is_local ? SYMBOL_FLAG_LOCAL : SYMBOL_FLAG_GLOBAL;
    } else {
        // If not found (e.g. injected in tests), create and insert
        if (declared_type) {
            bool is_local = (current_fn_return_type != NULL);
            Symbol var_symbol = SymbolBuilder(unit.getArena())
                .withName(node->name)
                .ofType(SYMBOL_VARIABLE)
                .withType(declared_type)
                .atLocation(node->name_loc)
                .definedBy(node)
                .withFlags(is_local ? SYMBOL_FLAG_LOCAL : SYMBOL_FLAG_GLOBAL)
                .build();
            unit.getSymbolTable().insert(var_symbol);
        }
    }

    return declared_type;
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
            .withFlags(SYMBOL_FLAG_LOCAL | SYMBOL_FLAG_PARAM)
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

Type* TypeChecker::visitStructDecl(ASTNode* /*parent*/, ASTStructDeclNode* node) {
    // 1. Check for duplicate field names
    for (size_t i = 0; i < node->fields->length(); ++i) {
        const char* name = (*node->fields)[i]->as.struct_field->name;
        for (size_t j = i + 1; j < node->fields->length(); ++j) {
            if (identifiers_equal(name, (*node->fields)[j]->as.struct_field->name)) {
                unit.getErrorHandler().report(ERR_REDEFINITION, (*node->fields)[j]->loc, "duplicate field name in struct", unit.getArena());
                return NULL;
            }
        }
    }

    // 2. Resolve field types and build the type structure
    void* mem = unit.getArena().alloc(sizeof(DynamicArray<StructField>));
    DynamicArray<StructField>* fields = new (mem) DynamicArray<StructField>(unit.getArena());

    for (size_t i = 0; i < node->fields->length(); ++i) {
        ASTNode* field_node = (*node->fields)[i];
        ASTStructFieldNode* field_data = field_node->as.struct_field;
        Type* field_type = visit(field_data->type);

        if (!field_type) {
             return NULL; // Error already reported
        }

        if (!is_c89_compatible(field_type)) {
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, field_data->type->loc, "struct field type is not C89 compatible.", unit.getArena());
            return NULL;
        }

        StructField sf;
        sf.name = field_data->name;
        sf.type = field_type;
        sf.offset = 0;
        sf.size = field_type->size;
        sf.alignment = field_type->alignment;
        fields->append(sf);
    }

    // 3. Create struct type and calculate layout
    Type* struct_type = createStructType(unit.getArena(), fields);
    calculateStructLayout(struct_type);

    return struct_type;
}

Type* TypeChecker::visitUnionDecl(ASTNode* /*parent*/, ASTUnionDeclNode* node) {
    // Basic validation for unions as well
    for (size_t i = 0; i < node->fields->length(); ++i) {
        const char* name = (*node->fields)[i]->as.struct_field->name;
        for (size_t j = i + 1; j < node->fields->length(); ++j) {
            if (identifiers_equal(name, (*node->fields)[j]->as.struct_field->name)) {
                unit.getErrorHandler().report(ERR_REDEFINITION, (*node->fields)[j]->loc, "duplicate field name in union", unit.getArena());
                return NULL;
            }
        }
    }
    // Note: We don't fully implement Union type creation yet, but we validate fields
    return NULL;
}

Type* TypeChecker::visitMemberAccess(ASTNode* parent, ASTMemberAccessNode* node) {
    Type* base_type = visit(node->base);
    if (!base_type) return NULL;

    // Auto-dereference for single level pointer
    if (base_type->kind == TYPE_POINTER) {
        base_type = base_type->as.pointer.base;
    }

    if (base_type->kind == TYPE_ENUM) {
        // Enum member access
        DynamicArray<EnumMember>* members = base_type->as.enum_details.members;
        bool found = false;
        for (size_t i = 0; i < members->length(); ++i) {
            if (identifiers_equal((*members)[i].name, node->field_name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            char msg_buffer[256];
            char* current = msg_buffer;
            size_t remaining = sizeof(msg_buffer);
            safe_append(current, remaining, "enum has no member named '");
            safe_append(current, remaining, node->field_name);
            safe_append(current, remaining, "'");
            fatalError(parent->loc, msg_buffer);
            return NULL;
        }

        return base_type; // Result type is the enum type itself
    }

    if (base_type->kind != TYPE_STRUCT) {
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->base->loc, "member access '.' only allowed on structs, enums or pointers to structs", unit.getArena());
        return NULL;
    }

    Type* field_type = findStructField(base_type, node->field_name);
    if (!field_type) {
        char msg_buffer[256];
        char* current = msg_buffer;
        size_t remaining = sizeof(msg_buffer);
        safe_append(current, remaining, "struct has no field named '");
        safe_append(current, remaining, node->field_name);
        safe_append(current, remaining, "'");
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->base->loc, msg_buffer, unit.getArena());
        return NULL;
    }

    return field_type;
}

Type* TypeChecker::visitStructInitializer(ASTStructInitializerNode* node) {
    Type* struct_type = visit(node->type_expr);
    if (!struct_type) return NULL;

    if (struct_type->kind != TYPE_STRUCT) {
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->type_expr->loc, "expected struct type for initialization", unit.getArena());
        return NULL;
    }

    DynamicArray<StructField>* fields = struct_type->as.struct_details.fields;

    // 1. Check for missing or extra fields
    for (size_t i = 0; i < fields->length(); ++i) {
        const char* expected_name = (*fields)[i].name;
        bool found = false;
        for (size_t j = 0; j < node->fields->length(); ++j) {
            if (identifiers_equal(expected_name, (*node->fields)[j]->field_name)) {
                found = true;
                break;
            }
        }
        if (!found) {
             char msg_buffer[256];
             char* current = msg_buffer;
             size_t remaining = sizeof(msg_buffer);
             safe_append(current, remaining, "missing field '");
             safe_append(current, remaining, expected_name);
             safe_append(current, remaining, "' in struct initializer");
             unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->type_expr->loc, msg_buffer, unit.getArena());
             return NULL;
        }
    }

    for (size_t i = 0; i < node->fields->length(); ++i) {
        ASTNamedInitializer* init = (*node->fields)[i];
        Type* field_type = findStructField(struct_type, init->field_name);
        if (!field_type) {
            char msg_buffer[256];
            char* current = msg_buffer;
            size_t remaining = sizeof(msg_buffer);
            safe_append(current, remaining, "no field named '");
            safe_append(current, remaining, init->field_name);
            safe_append(current, remaining, "' in struct");
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, init->loc, msg_buffer, unit.getArena());
            return NULL;
        }

        // Check for duplicates in initializer
        for (size_t j = i + 1; j < node->fields->length(); ++j) {
            if (identifiers_equal(init->field_name, (*node->fields)[j]->field_name)) {
                unit.getErrorHandler().report(ERR_REDEFINITION, (*node->fields)[j]->loc, "duplicate field initializer", unit.getArena());
                return NULL;
            }
        }

        // 2. Type check initializer values
        Type* val_type = visit(init->value);
        if (!IsTypeAssignableTo(val_type, field_type, init->loc)) {
             // IsTypeAssignableTo already reports the error
        }
    }

    return struct_type;
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

        // Check for unique member names
        for (size_t j = 0; j < i; ++j) {
            if (identifiers_equal((*members)[j].name, member_node->name)) {
                fatalError(member_node_wrapper->loc, "Duplicate enum member name");
            }
        }

        EnumMember member;
        member.name = member_node->name;
        member.value = member_value;
        member.loc = member_node_wrapper->loc;
        members->append(member);

        current_value = member_value + 1;
    }

    i64 min_val = 0;
    i64 max_val = 0;
    if (members->length() > 0) {
        min_val = (*members)[0].value;
        max_val = (*members)[0].value;
        for (size_t i = 1; i < members->length(); ++i) {
            if ((*members)[i].value < min_val) min_val = (*members)[i].value;
            if ((*members)[i].value > max_val) max_val = (*members)[i].value;
        }
    }

    // 4. Create and return the new enum type.
    return createEnumType(unit.getArena(), NULL, backing_type, members, min_val, max_val);
}

Type* TypeChecker::visitTypeName(ASTNode* parent, ASTTypeNameNode* node) {
    Type* resolved_type = resolvePrimitiveTypeName(node->name);
    if (!resolved_type) {
        // Look up in symbol table for type aliases (e.g., const Point = struct { ... })
        Symbol* sym = unit.getSymbolTable().lookup(node->name);
        if (sym) {
            // A constant can hold a type in Zig.
            // For now, we assume if it's in the symbol table and has a struct or enum type,
            // it can be used as a type name.
            if (sym->symbol_type && (sym->symbol_type->kind == TYPE_STRUCT || sym->symbol_type->kind == TYPE_ENUM)) {
                resolved_type = sym->symbol_type;
            }
        }
    }

    if (!resolved_type) {
        char msg_buffer[256];
        char* current = msg_buffer;
        size_t remaining = sizeof(msg_buffer);
        safe_append(current, remaining, "use of undeclared type '");
        safe_append(current, remaining, node->name);
        safe_append(current, remaining, "'");
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
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->element_type->loc, "Slices are not supported in C89 mode", unit.getArena());
        return NULL;
    }

    // 2. Ensure size is a constant integer literal
    if (node->size->type != NODE_INTEGER_LITERAL) {
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->size->loc, "Array size must be a constant integer literal", unit.getArena());
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
    Type* inner_type = visit(node->expression);
    if (inner_type && inner_type->kind == TYPE_ERROR_UNION) {
        return inner_type->as.error_union.payload;
    }
    return inner_type;
}

Type* TypeChecker::visitErrorUnionType(ASTErrorUnionTypeNode* node) {
    Type* payload = visit(node->payload_type);
    Type* error_set = node->error_set ? visit(node->error_set) : NULL;

    return createErrorUnionType(unit.getArena(), payload, error_set, node->error_set == NULL);
}

Type* TypeChecker::visitErrorSetDefinition(ASTErrorSetDefinitionNode* node) {
    return createErrorSetType(unit.getArena(), node->name, node->tags, node->name == NULL);
}

Type* TypeChecker::visitErrorSetMerge(ASTErrorSetMergeNode* node) {
    visit(node->left);
    visit(node->right);

    // For now, we just return an anonymous error set type.
    // In a real compiler we'd merge the tags, but for rejection it's enough to know it's an error set.
    return createErrorSetType(unit.getArena(), NULL, NULL, true);
}

Type* TypeChecker::visitOptionalType(ASTOptionalTypeNode* node) {
    logFeatureLocation("optional_type", node->loc);
    visit(node->payload_type);
    return NULL; // Optionals are not supported in the type system yet
}

void TypeChecker::logFeatureLocation(const char* feature, SourceLocation loc) {
    char buffer[256];
    char* current = buffer;
    size_t remaining = sizeof(buffer);

    safe_append(current, remaining, "Feature Log: ");
    safe_append(current, remaining, feature);
    safe_append(current, remaining, " at ");

    char line_str[16];
    simple_itoa(loc.line, line_str, sizeof(line_str));
    safe_append(current, remaining, "line ");
    safe_append(current, remaining, line_str);

    safe_append(current, remaining, ", col ");
    char col_str[16];
    simple_itoa(loc.column, col_str, sizeof(col_str));
    safe_append(current, remaining, col_str);
    safe_append(current, remaining, "\n");

    plat_print_debug(buffer);
}

Type* TypeChecker::visitCatchExpr(ASTCatchExprNode* node) {
    Type* payload_type = visit(node->payload);

    Type* result_type = NULL;
    Type* error_set = NULL;
    if (payload_type && payload_type->kind == TYPE_ERROR_UNION) {
        result_type = payload_type->as.error_union.payload;
        error_set = payload_type->as.error_union.error_set;
    }

    if (node->error_name) {
        unit.getSymbolTable().enterScope();
        Symbol sym = SymbolBuilder(unit.getArena())
            .withName(node->error_name)
            .ofType(SYMBOL_VARIABLE)
            .withType(error_set) // Use error set as type if available
            .build();
        unit.getSymbolTable().insert(sym);
    }

    visit(node->else_expr);

    if (node->error_name) {
        unit.getSymbolTable().exitScope();
    }

    return result_type;
}

Type* TypeChecker::visitOrelseExpr(ASTOrelseExprNode* node) {
    /* Type* left_type = */ visit(node->payload);
    visit(node->else_expr);

    // If it's an optional type, result is the payload.
    // For now, we return NULL as optionals are not fully supported,
    // but if we had TYPE_OPTIONAL, we'd return its payload.
    return NULL;
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

bool TypeChecker::isLValueConst(ASTNode* node) {
    if (!node) {
        return false;
    }
    switch (node->type) {
        case NODE_IDENTIFIER: {
            Symbol* symbol = unit.getSymbolTable().lookup(node->as.identifier.name);
            if (symbol && symbol->details) {
                ASTVarDeclNode* decl = (ASTVarDeclNode*)symbol->details;
                return decl->is_const;
            }
            return false;
        }
        case NODE_UNARY_OP:
            // Check for dereferencing a const pointer, e.g. *const u8
            if (node->as.unary_op.op == TOKEN_STAR) {
                Type* ptr_type = visit(node->as.unary_op.operand);
                return (ptr_type && ptr_type->kind == TYPE_POINTER && ptr_type->as.pointer.is_const);
            }
            return false;
        case NODE_ARRAY_ACCESS:
            // An array access is const if the array itself is const.
            return isLValueConst(node->as.array_access->array);
        case NODE_MEMBER_ACCESS:
            // A member access is const if the struct itself is const.
            return isLValueConst(node->as.member_access->base);
        default:
            return false;
    }
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

    // Handle null assignment to any pointer
    if (actual->kind == TYPE_NULL && expected->kind == TYPE_POINTER) {
        return true;
    }

    // Enum to Integer conversion (C89 compatible)
    if (actual->kind == TYPE_ENUM && isIntegerType(expected)) {
        return true;
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

    // Error Union compatibility (Zig-like for analysis purposes)
    if (expected->kind == TYPE_ERROR_UNION) {
        // T is compatible with !T (implicit wrap)
        if (areTypesCompatible(expected->as.error_union.payload, actual)) {
            return true;
        }
    }
    if (actual->kind == TYPE_ERROR_UNION) {
        // !T is compatible with T (implicit unwrap - unsafe but fine for rejection pass)
        if (areTypesCompatible(expected, actual->as.error_union.payload)) {
            return true;
        }
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

Type* TypeChecker::checkPointerArithmetic(Type* left_type, Type* right_type, TokenType op, SourceLocation loc) {
    bool left_is_ptr = (left_type->kind == TYPE_POINTER);
    bool right_is_ptr = (right_type->kind == TYPE_POINTER);
    bool left_is_int = isIntegerType(left_type);
    bool right_is_int = isIntegerType(right_type);

    if (op == TOKEN_PLUS) {
        if (left_is_ptr && right_is_int) return left_type;  // ptr + int
        if (left_is_int && right_is_ptr) return right_type; // int + ptr
    } else if (op == TOKEN_MINUS) {
        if (left_is_ptr && right_is_int) return left_type; // ptr - int
        if (left_is_ptr && right_is_ptr) { // ptr - ptr
            // For subtraction, the pointer types must be identical, not just compatible.
            if (left_type->as.pointer.base == right_type->as.pointer.base) {
                Type* isize_type = resolvePrimitiveTypeName("isize");
                if (!isize_type) {
                    unit.getErrorHandler().report(ERR_UNDECLARED_TYPE, loc, "Internal Error: 'isize' type not found for pointer difference", unit.getArena());
                    return NULL;
                }
                return isize_type;
            } else {
                unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, "cannot subtract pointers to different types", unit.getArena());
                return NULL;
            }
        }
    }

    // If we are here, it means some combination involving a pointer was used
    // with an unsupported operator (e.g., ptr * int, ptr + ptr).
    // The calling function, checkBinaryOperation, will handle the final error reporting
    // if no valid arithmetic operation is found.
    return NULL;
}

Type* TypeChecker::checkArithmeticWithLiteralPromotion(Type* left_type, Type* right_type, TokenType op) {
    bool is_arithmetic_op = (op == TOKEN_PLUS || op == TOKEN_MINUS ||
                             op == TOKEN_STAR || op == TOKEN_SLASH);

    if (is_arithmetic_op && isNumericType(left_type) && isNumericType(right_type)) {
        if (left_type->kind == TYPE_INTEGER_LITERAL && canLiteralFitInType(left_type, right_type)) {
            return right_type;
        }
        if (right_type->kind == TYPE_INTEGER_LITERAL && canLiteralFitInType(right_type, left_type)) {
            return left_type;
        }
    }
    return NULL;
}

bool TypeChecker::canLiteralFitInType(Type* literal_type, Type* target_type) {
    if (literal_type->kind != TYPE_INTEGER_LITERAL)
         return false;
    __int64 value = literal_type->as.integer_literal.value;
    switch (target_type->kind) {
        case TYPE_I8:  return (value >= -128 && value <= 127);
        case TYPE_U8:  return (value >= 0 && value <= 255);
        case TYPE_I16: return (value >= -32768 && value <= 32767);
        case TYPE_U16: return (value >= 0 && value <= 65535);
        case TYPE_I32: return (value >= -2147483647 - 1 && value <= 2147483647);
        case TYPE_U32: return (value >= 0 && (unsigned __int64)value <= 4294967295ULL);
        case TYPE_I64: return true; // Any i64 fits in i64
        case TYPE_U64: return value >= 0;
        // C89 allows implicit conversion from integer literals to floats.
        case TYPE_F32: return true;
        case TYPE_F64: return true;
        default:       return false;
    }
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
    char buffer[512];
    const SourceFile* file = unit.getSourceManager().getFile(loc.file_id);

    char* current = buffer;
    size_t remaining = sizeof(buffer);

    safe_append(current, remaining, "Fatal type error at ");
    safe_append(current, remaining, file ? file->filename : "<unknown>");
    safe_append(current, remaining, ":");
    char line_buf[21], col_buf[21];
    simple_itoa(loc.line, line_buf, sizeof(line_buf));
    simple_itoa(loc.column, col_buf, sizeof(col_buf));
    safe_append(current, remaining, line_buf);
    safe_append(current, remaining, ":");
    safe_append(current, remaining, col_buf);
    safe_append(current, remaining, ": ");
    safe_append(current, remaining, message);
    safe_append(current, remaining, "\n");

    plat_print_debug(buffer);

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
            char* current = msg_buffer;
            size_t remaining = sizeof(msg_buffer);
            safe_append(current, remaining, container_type_str);
            safe_append(current, remaining, " field type is not C89 compatible.");
            fatalError(field->type->loc, msg_buffer);
        }
    }
}

bool TypeChecker::IsTypeAssignableTo( Type* source_type, Type* target_type, SourceLocation loc) {
    // Null literal handling
    if (source_type->kind == TYPE_NULL) {
        return (target_type->kind == TYPE_POINTER);
    }

    // Exact match always works
    if (source_type == target_type) return true;

    // Error Union assignment (Zig-like for analysis purposes)
    if (target_type->kind == TYPE_ERROR_UNION) {
        if (IsTypeAssignableTo(source_type, target_type->as.error_union.payload, loc)) {
            return true;
        }
    }

    // Enum to Integer conversion (C89 compatible)
    if (source_type->kind == TYPE_ENUM && isIntegerType(target_type)) {
        return true;
    }

    // Numeric types require exact match in C89
    if (isNumericType(source_type) && isNumericType(target_type)) {
        char src_str[64], tgt_str[64];
        typeToString(source_type, src_str, sizeof(src_str));
        typeToString(target_type, tgt_str, sizeof(tgt_str));
        char msg_buffer[256];
        char* current = msg_buffer;
        size_t remaining = sizeof(msg_buffer);
        safe_append(current, remaining, "C89 assignment requires identical types: '");
        safe_append(current, remaining, src_str);
        safe_append(current, remaining, "' to '");
        safe_append(current, remaining, tgt_str);
        safe_append(current, remaining, "'");
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
        return false;
    }

    // Pointer assignment rules
    if (source_type->kind == TYPE_POINTER && target_type->kind == TYPE_POINTER) {
        Type* src_base = source_type->as.pointer.base;
        Type* tgt_base = target_type->as.pointer.base;

        // Allow T* -> void* (implicit)
        if (tgt_base->kind == TYPE_VOID && src_base->kind != TYPE_VOID) return true;

        // Disallow void* -> T* (requires cast)
        if (src_base->kind == TYPE_VOID && tgt_base->kind != TYPE_VOID) {
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, "C89: Cannot assign void* to typed pointer without cast");
            return false;
        }

        // Const correctness check
        if (target_type->as.pointer.is_const && !source_type->as.pointer.is_const) {
            return true; // T* -> const T* allowed
        }
        if (!target_type->as.pointer.is_const && source_type->as.pointer.is_const) {
            unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, "Cannot assign const pointer to non-const");
            return false;
        }

        // Base types must match
        if (src_base == tgt_base) {
            return true;
        }
    }

    // All other cases fail
    char src_str[64], tgt_str[64];
    typeToString(source_type, src_str, sizeof(src_str));
    typeToString(target_type, tgt_str, sizeof(tgt_str));
    char msg_buffer[256];
    char* current = msg_buffer;
    size_t remaining = sizeof(msg_buffer);
    safe_append(current, remaining, "Incompatible assignment: '");
    safe_append(current, remaining, src_str);
    safe_append(current, remaining, "' to '");
    safe_append(current, remaining, tgt_str);
    safe_append(current, remaining, "'");
    unit.getErrorHandler().report(ERR_TYPE_MISMATCH, loc, msg_buffer, unit.getArena());
    return false;
}
void TypeChecker::catalogGenericInstantiation(ASTFunctionCallNode* node) {
    bool is_explicit = false;
    for (size_t i = 0; i < node->args->length(); ++i) {
        if (isTypeExpression((*node->args)[i], unit.getSymbolTable())) {
            is_explicit = true;
            break;
        }
    }

    bool is_implicit = false;
    const char* callee_name = NULL;
    if (node->callee->type == NODE_IDENTIFIER) {
        callee_name = node->callee->as.identifier.name;
        Symbol* sym = unit.getSymbolTable().lookup(callee_name);
        if (sym && sym->is_generic) {
            is_implicit = true;
        }
    } else if (node->callee->type == NODE_MEMBER_ACCESS) {
        callee_name = node->callee->as.member_access->field_name;
    }

    if (is_explicit || is_implicit) {
        // Collect parameter info
        GenericParamInfo params[4];
        int param_count = 0;
        for (size_t i = 0; i < node->args->length() && param_count < 4; ++i) {
            ASTNode* arg = (*node->args)[i];
            if (isTypeExpression(arg, unit.getSymbolTable())) {
                params[param_count].kind = GENERIC_PARAM_TYPE;
                params[param_count].type_value = visit(arg);
                params[param_count].param_name = NULL;
                param_count++;
            } else {
                i64 int_val;
                if (evaluateConstantExpression(arg, &int_val)) {
                    params[param_count].kind = GENERIC_PARAM_COMPTIME_INT;
                    params[param_count].int_value = int_val;
                    params[param_count].param_name = NULL;
                    param_count++;
                }
                // Handle float if needed, but for now int and type are primary
            }
        }

        // Compute hash for deduplication
        u32 hash = 2166136261u;
        for (int i = 0; i < param_count; ++i) {
            hash ^= (u32)params[i].kind;
            hash *= 16777619u;
            if (params[i].kind == GENERIC_PARAM_TYPE) {
                hash ^= (u32)(size_t)params[i].type_value;
            } else if (params[i].kind == GENERIC_PARAM_COMPTIME_INT) {
                hash ^= (u32)params[i].int_value;
            }
            hash *= 16777619u;
        }

        unit.getGenericCatalogue().addInstantiation(
            callee_name ? callee_name : "anonymous",
            params,
            param_count,
            node->callee->loc,
            unit.getCurrentModule(),
            is_explicit,
            hash
        );
    }
}

bool TypeChecker::evaluateConstantExpression(ASTNode* node, i64* out_value) {
    if (!node) {
        return false;
    }

    switch (node->type) {
        case NODE_INTEGER_LITERAL:
            *out_value = (i64)node->as.integer_literal.value;
            return true;

        case NODE_UNARY_OP: {
            if (node->as.unary_op.op == TOKEN_MINUS) {
                i64 operand_value;
                if (evaluateConstantExpression(node->as.unary_op.operand, &operand_value)) {
                    *out_value = -operand_value;
                    return true;
                }
            }
            return false;
        }

        case NODE_BINARY_OP: {
            i64 left_value, right_value;
            bool left_is_const = evaluateConstantExpression(node->as.binary_op->left, &left_value);
            bool right_is_const = evaluateConstantExpression(node->as.binary_op->right, &right_value);

            if (left_is_const && right_is_const) {
                switch (node->as.binary_op->op) {
                    case TOKEN_PLUS:
                        *out_value = left_value + right_value;
                        return true;
                    case TOKEN_MINUS:
                        *out_value = left_value - right_value;
                        return true;
                    case TOKEN_STAR:
                        *out_value = left_value * right_value;
                        return true;
                    case TOKEN_SLASH:
                        if (right_value == 0) {
                             unit.getErrorHandler().report(ERR_DIVISION_BY_ZERO, node->loc, "compile-time division by zero");
                            return false;
                        }
                        *out_value = left_value / right_value;
                        return true;
                    case TOKEN_PERCENT:
                        if (right_value == 0) {
                            unit.getErrorHandler().report(ERR_DIVISION_BY_ZERO, node->loc, "compile-time division by zero");
                            return false;
                        }
                        *out_value = left_value % right_value;
                        return true;
                    default:
                        return false;
                }
            }
            return false;
        }
        case NODE_IDENTIFIER: {
            Symbol* symbol = unit.getSymbolTable().lookup(node->as.identifier.name);
            if (symbol && symbol->details) {
                ASTVarDeclNode* decl = (ASTVarDeclNode*)symbol->details;
                if (decl->is_const && decl->initializer) {
                    return evaluateConstantExpression(decl->initializer, out_value);
                }
            }
            return false;
        }
        default:
            return false;
    }
}
