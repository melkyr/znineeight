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
    Type* visitUnaryOp(ASTNode* parent, ASTUnaryOpNode* node);
    Type* visitBinaryOp(ASTNode* parent, ASTBinaryOpNode* node);
    Type* visitFunctionCall(ASTFunctionCallNode* node);
    Type* visitArrayAccess(ASTArrayAccessNode* node);
    Type* visitArraySlice(ASTArraySliceNode* node);
    Type* visitBoolLiteral(ASTNode* parent, ASTBoolLiteralNode* node);
    Type* visitIntegerLiteral(ASTNode* parent, ASTIntegerLiteralNode* node);
    Type* visitFloatLiteral(ASTNode* parent, ASTFloatLiteralNode* node);
    Type* visitCharLiteral(ASTNode* parent, ASTCharLiteralNode* node);
    Type* visitStringLiteral(ASTNode* parent, ASTStringLiteralNode* node);
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
    Type* visitStructDecl(ASTNode* parent, ASTStructDeclNode* node);
    Type* visitUnionDecl(ASTNode* parent, ASTUnionDeclNode* node);
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
    void validateStructOrUnionFields(ASTNode* decl_node);
    bool isNumericType(Type* type);
    bool isIntegerType(Type* type);
    bool checkIntegerLiteralFit(i64 value, Type* int_type);
    bool all_paths_return(ASTNode* node);
    CompilationUnit& unit;
    Type* current_fn_return_type;

};

#endif // TYPE_CHECKER_HPP
