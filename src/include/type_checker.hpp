#ifndef TYPE_CHECKER_HPP
#define TYPE_CHECKER_HPP

#include "ast.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"

class TypeChecker {
public:
    TypeChecker(CompilationUnit& unit);

    void check(ASTNode* root);
    Type* visit(ASTNode* node);
    Type* visitUnaryOp(ASTUnaryOpNode* node);
    Type* visitBinaryOp(ASTBinaryOpNode* node);
    Type* visitFunctionCall(ASTFunctionCallNode* node);
    Type* visitArrayAccess(ASTArrayAccessNode* node);
    Type* visitArraySlice(ASTArraySliceNode* node);
    Type* visitBoolLiteral(ASTBoolLiteralNode* node);
    Type* visitIntegerLiteral(ASTIntegerLiteralNode* node);
    Type* visitFloatLiteral(ASTFloatLiteralNode* node);
    Type* visitCharLiteral(ASTCharLiteralNode* node);
    Type* visitStringLiteral(ASTStringLiteralNode* node);
    Type* visitIdentifier(ASTNode* node);
    Type* visitBlockStmt(ASTBlockStmtNode* node);
    Type* visitEmptyStmt(ASTEmptyStmtNode* node);
    Type* visitIfStmt(ASTIfStmtNode* node);
    Type* visitWhileStmt(ASTWhileStmtNode* node);
    Type* visitReturnStmt(ASTNode* parent, ASTReturnStmtNode* node);
    Type* visitDeferStmt(ASTDeferStmtNode* node);
    Type* visitForStmt(ASTForStmtNode* node);
    Type* visitExpressionStmt(ASTExpressionStmtNode* node);
    Type* visitSwitchExpr(ASTSwitchExprNode* node);
    Type* visitVarDecl(ASTVarDeclNode* node);
    Type* visitFnDecl(ASTFnDeclNode* node);
    Type* visitStructDecl(ASTStructDeclNode* node);
    Type* visitUnionDecl(ASTUnionDeclNode* node);
    Type* visitEnumDecl(ASTEnumDeclNode* node);
    Type* visitTypeName(ASTNode* parent, ASTTypeNameNode* node);
    Type* visitPointerType(ASTPointerTypeNode* node);
    Type* visitArrayType(ASTArrayTypeNode* node);
    Type* visitTryExpr(ASTTryExprNode* node);
    Type* visitCatchExpr(ASTCatchExprNode* node);
    Type* visitErrdeferStmt(ASTErrDeferStmtNode* node);
    Type* visitComptimeBlock(ASTComptimeBlockNode* node);
    bool areTypesCompatible(Type* expected, Type* actual);
private:
    void fatalError(SourceLocation loc, const char* message);
    bool isNumericType(Type* type);
    bool isIntegerType(Type* type);
    bool all_paths_return(ASTNode* node);
    CompilationUnit& unit;
    Type* current_fn_return_type;

};

#endif // TYPE_CHECKER_HPP
