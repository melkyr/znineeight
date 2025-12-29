#include "type_checker.hpp"
#include "type_system.hpp"

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
        case NODE_TYPE_NAME:        return visitTypeName(&node->as.type_name);
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
    visit(node->left);
    visit(node->right);
    return NULL; // Placeholder
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
    return createPointerType(unit.getArena(), char_type);
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

    if (declared_type && initializer_type && declared_type != initializer_type) {
        unit.getErrorHandler().report(ERR_TYPE_MISMATCH, node->initializer->loc, "Type mismatch in variable declaration");
    }

    return NULL;
}

Type* TypeChecker::visitFnDecl(ASTFnDeclNode* node) {
    Type* prev_fn_return_type = current_fn_return_type;
    current_fn_return_type = node->return_type ? visit(node->return_type) : resolvePrimitiveTypeName("void");

    // TODO: Visit params

    visit(node->body);

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

Type* TypeChecker::visitTypeName(ASTTypeNameNode* node) {
    return resolvePrimitiveTypeName(node->name);
}

Type* TypeChecker::visitPointerType(ASTPointerTypeNode* node) {
    visit(node->base);
    return NULL; // Placeholder
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

    return false;
}
