#ifndef NAME_COLLISION_DETECTOR_HPP
#define NAME_COLLISION_DETECTOR_HPP

#include "common.hpp"
#include "ast.hpp"
#include "memory.hpp"

class CompilationUnit;
class ErrorHandler;

/**
 * @class NameCollisionDetector
 * @brief AST visitor that detects and reports name collisions in the same scope.
 *
 * This pass runs after parsing and before type checking to ensure C89 compatibility
 * regarding function and variable naming within the same scope.
 */
class NameCollisionDetector {
public:
    NameCollisionDetector(CompilationUnit& unit);
    void check(ASTNode* root);
    bool hasCollisions() const;
    int getCollisionCount() const;

private:
    /**
     * @struct ScopeInfo
     * @brief Tracks names encountered in a single scope level.
     */
    struct ScopeInfo {
        DynamicArray<const char*> function_names;
        DynamicArray<const char*> variable_names;

        ScopeInfo(ArenaAllocator& arena)
            : function_names(arena), variable_names(arena) {}
    };

    CompilationUnit& unit_;
    ErrorHandler& error_handler_;
    DynamicArray<ScopeInfo*> scope_stack_;
    int collision_count_;

    void visit(ASTNode* node);
    void visitFnDecl(ASTFnDeclNode* node);
    void visitVarDecl(ASTVarDeclNode* node);
    void enterScope();
    void exitScope();

    bool checkCollisionInCurrentScope(const char* name);
    void reportCollision(SourceLocation loc, const char* name, const char* entity_type);
};

#endif // NAME_COLLISION_DETECTOR_HPP
