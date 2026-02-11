#ifndef MOCK_EMITTER_HPP
#define MOCK_EMITTER_HPP

// TEST-ONLY: Mock emitter for integration testing
// Not part of the production codebase
// Will be replaced by real C89Emitter in Milestone 5

#include "ast.hpp"
#include "type_system.hpp"
#include "symbol_table.hpp"
#include "c89_type_mapping.hpp"
#include "call_site_lookup_table.hpp"
#include <string>
#include <sstream>
#include <iomanip>

/**
 * @class MockC89Emitter
 * @brief A simple emitter that converts literal AST nodes into C89 string representations.
 *
 * This is used for Milestone 4 Task 170 to validate that literals are correctly
 * parsed and typed, and can be mapped to valid C89 syntax.
 */
class MockC89Emitter {
    const CallSiteLookupTable* call_table_;
    SymbolTable* symbol_table_;

public:
    MockC89Emitter(const CallSiteLookupTable* call_table = NULL, SymbolTable* symbol_table = NULL)
        : call_table_(call_table), symbol_table_(symbol_table) {}

    /**
     * @brief Emits a C89 variable declaration.
     * @param decl The variable declaration node.
     * @param symbol The associated symbol.
     * @return A std::string containing the C89 declaration.
     */
    std::string emitVariableDeclaration(const ASTVarDeclNode* decl, const Symbol* symbol) {
        if (!decl || !symbol) return "/* INVALID DECL */";

        std::stringstream ss;
        if (decl->is_const) {
            ss << "const ";
        }

        ss << getC89TypeName(symbol->symbol_type) << " ";
        ss << (symbol->mangled_name ? symbol->mangled_name : decl->name);

        if (decl->initializer) {
            ss << " = " << emitExpression(decl->initializer);
        }
        ss << ";";

        return ss.str();
    }

    /**
     * @brief Emits a C89 string representation of an expression.
     * @param node The ASTNode to emit.
     * @return A std::string containing the C89 representation.
     */
    std::string emitExpression(const ASTNode* node) {
        if (!node) return "/* NULL */";

        switch (node->type) {
            case NODE_INTEGER_LITERAL:
                return emitIntegerLiteral(&node->as.integer_literal, node->resolved_type);
            case NODE_FLOAT_LITERAL:
                return emitFloatLiteral(&node->as.float_literal, node->resolved_type);
            case NODE_CHAR_LITERAL:
                return emitCharLiteral(&node->as.char_literal, node->resolved_type);
            case NODE_STRING_LITERAL:
                return emitStringLiteral(&node->as.string_literal, node->resolved_type);
            case NODE_BOOL_LITERAL:
                return node->as.bool_literal.value ? "1" : "0";
            case NODE_NULL_LITERAL:
                return "((void*)0)";
            case NODE_IDENTIFIER:
                return node->as.identifier.name;
            case NODE_FUNCTION_CALL:
                return emitFunctionCall(node);
            case NODE_MEMBER_ACCESS:
                return emitMemberAccess(node->as.member_access);
            case NODE_STRUCT_INITIALIZER:
                return emitStructInitializer(node->as.struct_initializer);
            case NODE_BINARY_OP:
                return emitBinaryOp(node->as.binary_op);
            case NODE_UNARY_OP:
                return emitUnaryOp(&node->as.unary_op);
            case NODE_PAREN_EXPR:
                return "(" + emitExpression(node->as.paren_expr.expr) + ")";
            case NODE_BLOCK_STMT:
                return emitBlockStatement(&node->as.block_stmt);
            case NODE_IF_STMT:
                return emitIfStatement(node->as.if_stmt);
            case NODE_WHILE_STMT:
                return emitWhileStatement(&node->as.while_stmt);
            case NODE_BREAK_STMT:
                return emitBreakStatement(&node->as.break_stmt);
            case NODE_CONTINUE_STMT:
                return emitContinueStatement(&node->as.continue_stmt);
            case NODE_RETURN_STMT:
                return "return" + (node->as.return_stmt.expression ? " " + emitExpression(node->as.return_stmt.expression) : "") + ";";
            case NODE_EXPRESSION_STMT:
                return emitExpression(node->as.expression_stmt.expression) + ";";
            case NODE_ASSIGNMENT:
                return emitExpression(node->as.assignment->lvalue) + " = " + emitExpression(node->as.assignment->rvalue);
            case NODE_VAR_DECL: {
                if (symbol_table_) {
                    Symbol* sym = symbol_table_->findInAnyScope(node->as.var_decl->name);
                    if (sym) {
                        return emitVariableDeclaration(node->as.var_decl, sym);
                    }
                }
                return "/* var " + std::string(node->as.var_decl->name) + " */";
            }
            default:
                return "/* unsupported node type */";
        }
    }

    /**
     * @brief Emits a C89 if statement.
     */
    std::string emitIfStatement(const ASTIfStmtNode* node) {
        if (!node) return "/* INVALID IF */";
        std::stringstream ss;

        ss << "if (" << emitExpression(node->condition) << ") ";

        // Then block (assumed to be NODE_BLOCK_STMT per bootstrap parser rules)
        if (node->then_block && node->then_block->type == NODE_BLOCK_STMT) {
            ss << emitBlockStatement(&node->then_block->as.block_stmt);
        } else {
            ss << emitExpression(node->then_block);
        }

        if (node->else_block) {
            ss << " else ";

            // Check for else-if chain
            // In our AST, if else_block is a block with exactly one if statement,
            // we can emit it as "else if"
            if (node->else_block->type == NODE_BLOCK_STMT &&
                node->else_block->as.block_stmt.statements &&
                node->else_block->as.block_stmt.statements->length() == 1 &&
                (*node->else_block->as.block_stmt.statements)[0]->type == NODE_IF_STMT) {

                ss << emitIfStatement((*node->else_block->as.block_stmt.statements)[0]->as.if_stmt);
            } else if (node->else_block->type == NODE_BLOCK_STMT) {
                ss << emitBlockStatement(&node->else_block->as.block_stmt);
            } else {
                ss << emitExpression(node->else_block);
            }
        }

        return ss.str();
    }

    /**
     * @brief Emits a C89 while statement.
     */
    std::string emitWhileStatement(const ASTWhileStmtNode* node) {
        if (!node) return "/* INVALID WHILE */";
        std::stringstream ss;
        ss << "while (" << emitExpression(node->condition) << ") ";

        if (node->body && node->body->type == NODE_BLOCK_STMT) {
            ss << emitBlockStatement(&node->body->as.block_stmt);
        } else {
            ss << emitExpression(node->body);
        }

        return ss.str();
    }

    /**
     * @brief Emits a C89 break statement.
     */
    std::string emitBreakStatement(const ASTBreakStmtNode* /*node*/) {
        return "break;";
    }

    /**
     * @brief Emits a C89 continue statement.
     */
    std::string emitContinueStatement(const ASTContinueStmtNode* /*node*/) {
        return "continue;";
    }

    /**
     * @brief Emits a C89 block statement.
     */
    std::string emitBlockStatement(const ASTBlockStmtNode* block) {
        if (!block) return "{ }";
        std::stringstream ss;
        ss << "{ ";
        if (block->statements) {
            for (size_t i = 0; i < block->statements->length(); ++i) {
                ss << emitExpression((*block->statements)[i]) << " ";
            }
        }
        ss << "}";
        return ss.str();
    }

    /**
     * @brief Emits a C89 function signature.
     * @param fn The function declaration node.
     * @param symbol The associated symbol.
     * @return A std::string containing the C89 signature.
     */
    std::string emitFunctionSignature(const ASTFnDeclNode* fn, const Symbol* symbol) {
        if (!fn || !symbol || !symbol->symbol_type || symbol->symbol_type->kind != TYPE_FUNCTION) {
            return "/* INVALID FN */";
        }

        std::stringstream ss;
        Type* fn_type = symbol->symbol_type;
        ss << getC89TypeName(fn_type->as.function.return_type) << " ";
        ss << (symbol->mangled_name ? symbol->mangled_name : fn->name);
        ss << "(";

        DynamicArray<Type*>* params = fn_type->as.function.params;
        if (params && params->length() > 0) {
            for (size_t i = 0; i < params->length(); ++i) {
                if (i > 0) ss << ", ";
                ss << getC89TypeName((*params)[i]) << " " << (*fn->params)[i]->name;
            }
        } else {
            ss << "void";
        }
        ss << ")";

        return ss.str();
    }

    /**
     * @brief Emits a C89 function declaration (signature + body).
     */
    std::string emitFunctionDeclaration(const ASTFnDeclNode* fn, const Symbol* symbol) {
        std::stringstream ss;
        ss << emitFunctionSignature(fn, symbol) << " " << emitExpression(fn->body);
        return ss.str();
    }

    /**
     * @brief Emits a C89 member access expression.
     */
    std::string emitMemberAccess(const ASTMemberAccessNode* node) {
        if (!node) return "/* INVALID MEMBER ACCESS */";

        // Use -> for pointer member access
        if (node->base->resolved_type && node->base->resolved_type->kind == TYPE_POINTER) {
            return emitExpression(node->base) + "->" + node->field_name;
        }

        return emitExpression(node->base) + "." + node->field_name;
    }

    /**
     * @brief Emits a C89 struct initializer (positional).
     */
    std::string emitStructInitializer(const ASTStructInitializerNode* node) {
        if (!node || !node->type_expr || !node->type_expr->resolved_type) return "{ /* INVALID */ }";
        Type* struct_type = node->type_expr->resolved_type;
        if (struct_type->kind != TYPE_STRUCT) return "{ /* NOT A STRUCT */ }";

        DynamicArray<StructField>* fields = struct_type->as.struct_details.fields;
        std::stringstream ss;
        ss << "{";

        for (size_t i = 0; i < fields->length(); ++i) {
            if (i > 0) ss << ", ";
            const char* field_name = (*fields)[i].name;

            // Find initializer for this field
            bool found = false;
            if (node->fields) {
                for (size_t j = 0; j < node->fields->length(); ++j) {
                    if (plat_strcmp(field_name, (*node->fields)[j]->field_name) == 0) {
                        ss << emitExpression((*node->fields)[j]->value);
                        found = true;
                        break;
                    }
                }
            }
            if (!found) ss << "0";
        }
        ss << "}";
        return ss.str();
    }

    /**
     * @brief Emits a C89 function call.
     */
    std::string emitFunctionCall(const ASTNode* node) {
        if (!node || node->type != NODE_FUNCTION_CALL) return "/* INVALID CALL */";
        const ASTFunctionCallNode* call = node->as.function_call;

        std::stringstream ss;

        // Use mangled name from call table if available
        const char* name = "/* UNKNOWN */";
        if (call->callee->type == NODE_IDENTIFIER) {
            name = call->callee->as.identifier.name;
            if (call_table_) {
                const CallSiteEntry* entry = call_table_->findByCallNode(const_cast<ASTNode*>(node));
                if (entry && entry->mangled_name) {
                    name = entry->mangled_name;
                }
            }
        } else {
            // Complex callee (e.g. pointer)
            ss << emitExpression(call->callee);
            name = NULL;
        }

        if (name) ss << name;

        ss << "(";
        if (call->args) {
            for (size_t i = 0; i < call->args->length(); ++i) {
                if (i > 0) ss << ", ";
                ss << emitExpression((*call->args)[i]);
            }
        }
        ss << ")";

        return ss.str();
    }

private:
    std::string getC89TypeName(Type* type) {
        if (!type) return "/* unknown type */";

        if (type->kind == TYPE_POINTER) {
            std::string base = getC89TypeName(type->as.pointer.base);
            if (type->as.pointer.is_const) {
                return "const " + base + "*";
            }
            return base + "*";
        }

        const size_t map_size = sizeof(c89_type_map) / sizeof(c89_type_map[0]);
        for (size_t i = 0; i < map_size; ++i) {
            if (type->kind == c89_type_map[i].zig_type_kind) {
                return c89_type_map[i].c89_type_name;
            }
        }

        if (type->kind == TYPE_STRUCT) {
            if (type->as.struct_details.name) {
                return "struct " + std::string(type->as.struct_details.name);
            }
            return "struct /* anonymous */";
        }
        if (type->kind == TYPE_ENUM) return "enum /* ... */";

        return "/* unsupported type */";
    }

    std::string emitIntegerLiteral(const ASTIntegerLiteralNode* node, Type* type) {
        std::stringstream ss;
        ss << node->value;

        if (type) {
            if (type->kind == TYPE_U64) {
                ss << "ULL";
            } else if (type->kind == TYPE_I64) {
                ss << "LL";
            } else if (type->kind == TYPE_U32) {
                ss << "U";
            } else if (type->kind == TYPE_U8 || type->kind == TYPE_U16) {
                // Technically C89 might not need U for small types, but it's safer
                ss << "U";
            }
        } else {
            // Fallback to suffixes in the node if type is not resolved
            if (node->is_unsigned && node->is_long) ss << "ULL";
            else if (node->is_unsigned) ss << "U";
            else if (node->is_long) ss << "L";
        }

        return ss.str();
    }

    std::string emitFloatLiteral(const ASTFloatLiteralNode* node, Type* type) {
        std::stringstream ss;
        // Ensure decimal point for whole numbers to distinguish from integers in C
        ss << std::showpoint << node->value;

        std::string s = ss.str();

        // Handle scientific notation separately to avoid trimming the exponent
        size_t exp_pos = s.find_first_of("eE");
        std::string exponent = "";
        if (exp_pos != std::string::npos) {
            exponent = s.substr(exp_pos);
            s = s.substr(0, exp_pos);
        }

        // Remove trailing zeros and possible trailing dot if it's cleaner
        size_t dot = s.find('.');
        if (dot != std::string::npos) {
            size_t last_nonzero = s.find_last_not_of('0');
            if (last_nonzero != std::string::npos && last_nonzero > dot) {
                s.erase(last_nonzero + 1);
            } else if (last_nonzero == dot) {
                // Keep the dot and one zero for clarity: "1.0"
                s.erase(dot + 2);
            }
        }

        s += exponent;

        if (type && type->kind == TYPE_F32) {
            s += "f";
        }

        return s;
    }

    std::string emitCharLiteral(const ASTCharLiteralNode* node, Type* /*type*/) {
        std::stringstream ss;
        unsigned char c = static_cast<unsigned char>(node->value);

        ss << "'";
        switch (c) {
            case '\'': ss << "\\'"; break;
            case '\\': ss << "\\\\"; break;
            case '\n': ss << "\\n"; break;
            case '\t': ss << "\\t"; break;
            case '\r': ss << "\\r"; break;
            default:
                if (c >= 32 && c <= 126) {
                    ss << (char)c;
                } else {
                    // Use octal escape for non-printable ASCII (C89 compatible)
                    ss << "\\" << std::oct << std::setw(3) << std::setfill('0') << (int)c << std::dec;
                }
                break;
        }
        ss << "'";
        return ss.str();
    }

    std::string emitBinaryOp(const ASTBinaryOpNode* node) {
        std::string left = emitExpression(node->left);
        std::string right = emitExpression(node->right);
        const char* op_str = binaryOpToString(node->op);
        return left + " " + op_str + " " + right;
    }

    std::string emitUnaryOp(const ASTUnaryOpNode* node) {
        std::string operand = emitExpression(node->operand);
        const char* op_str = unaryOpToString(node->op);
        return std::string(op_str) + operand;
    }

    const char* binaryOpToString(TokenType op) {
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
            case TOKEN_AND: return "&&";
            case TOKEN_OR: return "||";
            default: return "??";
        }
    }

    const char* unaryOpToString(TokenType op) {
        switch (op) {
            case TOKEN_MINUS: return "-";
            case TOKEN_BANG: return "!";
            case TOKEN_AMPERSAND: return "&";
            case TOKEN_DOT_ASTERISK: return "*";
            default: return "??";
        }
    }

    std::string emitStringLiteral(const ASTStringLiteralNode* node, Type* /*type*/) {
        std::stringstream ss;
        ss << "\"";
        const char* p = node->value;
        while (p && *p) {
            unsigned char c = static_cast<unsigned char>(*p);
            switch (c) {
                case '"': ss << "\\\""; break;
                case '\\': ss << "\\\\"; break;
                case '\n': ss << "\\n"; break;
                case '\t': ss << "\\t"; break;
                case '\r': ss << "\\r"; break;
                default:
                    if (c >= 32 && c <= 126) {
                        ss << (char)c;
                    } else {
                        // Use octal escape for non-printable/special chars
                        ss << "\\" << std::oct << std::setw(3) << std::setfill('0') << (int)c << std::dec;
                    }
                    break;
            }
            p++;
        }
        ss << "\"";
        return ss.str();
    }
};

#endif // MOCK_EMITTER_HPP
