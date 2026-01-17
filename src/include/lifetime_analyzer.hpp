#ifndef LIFETIME_ANALYZER_HPP
#define LIFETIME_ANALYZER_HPP

#include "compilation_unit.hpp"

/**
 * @struct PointerAssignment
 * @brief Tracks the source of a pointer variable assignment.
 */
struct PointerAssignment {
    const char* pointer_name;
    const char* points_to_name; // NULL if unknown or not a local variable
};

/**
 * @class LifetimeAnalyzer
 * @brief Performs static analysis to detect lifetime violations, such as dangling pointers.
 */
class LifetimeAnalyzer {
public:
    LifetimeAnalyzer(CompilationUnit& unit);
    void analyze(ASTNode* root);

private:
    CompilationUnit& unit_;
    DynamicArray<PointerAssignment>* current_assignments_;

    void visit(ASTNode* node);
    void visitBlockStmt(ASTBlockStmtNode* node);
    void visitFnDecl(ASTFnDeclNode* node);
    void visitReturnStmt(ASTReturnStmtNode* node);
    void visitVarDecl(ASTVarDeclNode* node);
    void visitAssignment(ASTAssignmentNode* node);
    void visitIfStmt(ASTIfStmtNode* node);
    void visitWhileStmt(ASTWhileStmtNode* node);
    void visitForStmt(ASTForStmtNode* node);

    bool isDangerousLocalPointer(ASTNode* expr);
    bool isSymbolLocalVariable(const char* name);
    void trackLocalPointerAssignment(const char* pointer_name, ASTNode* rvalue);
    const char* extractVariableName(ASTNode* expr);
};

#endif // LIFETIME_ANALYZER_HPP
