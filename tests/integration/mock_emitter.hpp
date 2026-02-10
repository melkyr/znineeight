#ifndef MOCK_EMITTER_HPP
#define MOCK_EMITTER_HPP

// TEST-ONLY: Mock emitter for integration testing
// Not part of the production codebase
// Will be replaced by real C89Emitter in Milestone 5

#include "ast.hpp"
#include "type_system.hpp"
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
public:
    /**
     * @brief Emits a C89 string representation of a literal expression.
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
            default:
                return "/* unsupported node type */";
        }
    }

private:
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
