#ifndef DEBUG_HELPERS_HPP
#define DEBUG_HELPERS_HPP

#include "ast.hpp"

/**
 * @brief Returns a human-readable string representation of an AST node type.
 * @param t The NodeType to convert.
 * @return A string literal representing the node type name.
 */
inline const char* AST_NODE_TYPE_NAME(NodeType t) {
    switch (t) {
        /* Expressions */
        case NODE_ASSIGNMENT: return "NODE_ASSIGNMENT";
        case NODE_COMPOUND_ASSIGNMENT: return "NODE_COMPOUND_ASSIGNMENT";
        case NODE_UNARY_OP: return "NODE_UNARY_OP";
        case NODE_BINARY_OP: return "NODE_BINARY_OP";
        case NODE_FUNCTION_CALL: return "NODE_FUNCTION_CALL";
        case NODE_ARRAY_ACCESS: return "NODE_ARRAY_ACCESS";
        case NODE_ARRAY_SLICE: return "NODE_ARRAY_SLICE";
        case NODE_MEMBER_ACCESS: return "NODE_MEMBER_ACCESS";
        case NODE_STRUCT_INITIALIZER: return "NODE_STRUCT_INITIALIZER";
        case NODE_TUPLE_LITERAL: return "NODE_TUPLE_LITERAL";

        /* Literals */
        case NODE_BOOL_LITERAL: return "NODE_BOOL_LITERAL";
        case NODE_NULL_LITERAL: return "NODE_NULL_LITERAL";
        case NODE_UNDEFINED_LITERAL: return "NODE_UNDEFINED_LITERAL";
        case NODE_INTEGER_LITERAL: return "NODE_INTEGER_LITERAL";
        case NODE_FLOAT_LITERAL: return "NODE_FLOAT_LITERAL";
        case NODE_CHAR_LITERAL: return "NODE_CHAR_LITERAL";
        case NODE_STRING_LITERAL: return "NODE_STRING_LITERAL";
        case NODE_ERROR_LITERAL: return "NODE_ERROR_LITERAL";
        case NODE_IDENTIFIER: return "NODE_IDENTIFIER";

        /* Statements */
        case NODE_BLOCK_STMT: return "NODE_BLOCK_STMT";
        case NODE_EMPTY_STMT: return "NODE_EMPTY_STMT";
        case NODE_IF_STMT: return "NODE_IF_STMT";
        case NODE_IF_EXPR: return "NODE_IF_EXPR";
        case NODE_WHILE_STMT: return "NODE_WHILE_STMT";
        case NODE_SWITCH_STMT: return "NODE_SWITCH_STMT";
        case NODE_BREAK_STMT: return "NODE_BREAK_STMT";
        case NODE_CONTINUE_STMT: return "NODE_CONTINUE_STMT";
        case NODE_RETURN_STMT: return "NODE_RETURN_STMT";
        case NODE_DEFER_STMT: return "NODE_DEFER_STMT";
        case NODE_FOR_STMT: return "NODE_FOR_STMT";
        case NODE_EXPRESSION_STMT: return "NODE_EXPRESSION_STMT";
        case NODE_PAREN_EXPR: return "NODE_PAREN_EXPR";
        case NODE_RANGE: return "NODE_RANGE";
        case NODE_UNREACHABLE: return "NODE_UNREACHABLE";

        /* Built-in Expressions */
        case NODE_SWITCH_EXPR: return "NODE_SWITCH_EXPR";
        case NODE_PTR_CAST: return "NODE_PTR_CAST";
        case NODE_INT_CAST: return "NODE_INT_CAST";
        case NODE_FLOAT_CAST: return "NODE_FLOAT_CAST";
        case NODE_OFFSET_OF: return "NODE_OFFSET_OF";

        /* Declarations */
        case NODE_VAR_DECL: return "NODE_VAR_DECL";
        case NODE_PARAM_DECL: return "NODE_PARAM_DECL";
        case NODE_FN_DECL: return "NODE_FN_DECL";
        case NODE_STRUCT_FIELD: return "NODE_STRUCT_FIELD";

        /* Container Declarations */
        case NODE_STRUCT_DECL: return "NODE_STRUCT_DECL";
        case NODE_UNION_DECL: return "NODE_UNION_DECL";
        case NODE_ENUM_DECL: return "NODE_ENUM_DECL";
        case NODE_ERROR_SET_DEFINITION: return "NODE_ERROR_SET_DEFINITION";
        case NODE_ERROR_SET_MERGE: return "NODE_ERROR_SET_MERGE";

        /* Modules */
        case NODE_IMPORT_STMT: return "NODE_IMPORT_STMT";

        /* Type Expressions */
        case NODE_TYPE_NAME: return "NODE_TYPE_NAME";
        case NODE_POINTER_TYPE: return "NODE_POINTER_TYPE";
        case NODE_ARRAY_TYPE: return "NODE_ARRAY_TYPE";
        case NODE_ERROR_UNION_TYPE: return "NODE_ERROR_UNION_TYPE";
        case NODE_OPTIONAL_TYPE: return "NODE_OPTIONAL_TYPE";
        case NODE_FUNCTION_TYPE: return "NODE_FUNCTION_TYPE";

        /* Error Handling */
        case NODE_TRY_EXPR: return "NODE_TRY_EXPR";
        case NODE_CATCH_EXPR: return "NODE_CATCH_EXPR";
        case NODE_ORELSE_EXPR: return "NODE_ORELSE_EXPR";
        case NODE_ERRDEFER_STMT: return "NODE_ERRDEFER_STMT";

        /* Async Operations */
        case NODE_ASYNC_EXPR: return "NODE_ASYNC_EXPR";
        case NODE_AWAIT_EXPR: return "NODE_AWAIT_EXPR";

        /* Compile-Time */
        case NODE_COMPTIME_BLOCK: return "NODE_COMPTIME_BLOCK";

        default: return "NODE_UNKNOWN";
    }
}

#endif /* DEBUG_HELPERS_HPP */
