#ifndef TYPE_CHECKER_HPP
#define TYPE_CHECKER_HPP

#include "ast.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"

class TypeChecker {
public:
    /**
     * @brief Constructs a new TypeChecker.
     * @param unit The CompilationUnit that owns this TypeChecker and its resources.
     */
    TypeChecker(CompilationUnit& unit);

    void check(ASTNode* root);
    Type* visit(ASTNode* node);
    Type* visitUnaryOp(ASTNode* parent, ASTUnaryOpNode* node);
    Type* visitBinaryOp(ASTNode* parent, ASTBinaryOpNode* node);
    Type* visitAssignment(ASTAssignmentNode* node);
    Type* visitCompoundAssignment(ASTCompoundAssignmentNode* node);
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
    Type* visitVarDecl(ASTNode* parent, ASTVarDeclNode* node);
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

    // Public for TDD
    Type* checkBinaryOperation(Type* left_type, Type* right_type, TokenType op, SourceLocation loc);
    Type* findStructField(Type* struct_type, const char* field_name);
    void fatalError(const char* msg);
    Type* checkBinaryOpCompatibility(Type* left, Type* right, TokenType op, SourceLocation loc);
private:
    /**
     * @brief Checks if a type can be assigned to another, enforcing strict C89 rules.
     * @param actual The type of the value being assigned (R-value).
     * @param expected The type of the location being assigned to (L-value).
     * @param loc The source location for error reporting.
     * @return True if the assignment is valid, false otherwise.
     */
    bool isTypeAssignableTo(Type* actual, Type* expected, SourceLocation loc);

    /**
     * @brief Recursively checks if an l-value expression refers to a constant.
     * @param node The AST node of the l-value.
     * @return True if the l-value is const, false otherwise.
     */
    bool isLValueConst(ASTNode* node);

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
