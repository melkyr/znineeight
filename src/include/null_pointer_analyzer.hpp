#ifndef NULL_POINTER_ANALYZER_HPP
#define NULL_POINTER_ANALYZER_HPP

#include "compilation_unit.hpp"

/**
 * @class NullPointerAnalyzer
 * @brief Performs static analysis to detect null pointer dereferences.
 *
 * Implements Task 126 of AI_tasks.md. Phase 1 focuses on foundational
 * state tracking and visitor framework.
 */
class NullPointerAnalyzer {
public:
    /**
     * @enum State
     * @brief Represents the known nullability state of a pointer variable.
     */
    enum State {
        STATE_UNINIT = 0, ///< No initializer provided.
        STATE_NULL   = 1, ///< Definitely null (0 or NULL).
        STATE_SAFE   = 2, ///< Definitely non-null (e.g., address-of a local).
        STATE_MAYBE  = 3  ///< Unknown state.
    };

    /**
     * @struct VarTrack
     * @brief Tracks the state of a single variable within a scope.
     */
    struct VarTrack {
        const char* name; ///< Interned identifier name.
        State state;      ///< Current nullability state.
    };

    /**
     * @brief Constructs a new NullPointerAnalyzer.
     * @param arena The arena to use for internal tracking structures.
     * @param unit The compilation unit being analyzed.
     */
    NullPointerAnalyzer(ArenaAllocator& arena, CompilationUnit& unit);

    /**
     * @brief Performs null pointer analysis on the given AST.
     * @param root The root of the AST to analyze.
     */
    void analyze(ASTNode* root);

private:
    CompilationUnit& unit;
    ArenaAllocator& arena;
    DynamicArray<VarTrack>* currentScope;
    DynamicArray<DynamicArray<VarTrack>*> scopes;

    // Visitor methods
    void visit(ASTNode* node);
    void visitFnDecl(ASTFnDeclNode* node);
    void visitBlockStmt(ASTBlockStmtNode* node);
    void visitVarDecl(ASTVarDeclNode* node);
    void visitGlobalVar(ASTNode* node);

    // State management
    void pushScope();
    void popScope();
    void setState(const char* name, State state);
    State getState(const char* name);

    // Helper functions for string comparison (since strcmp is avoided where possible)
    static bool stringsEqual(const char* s1, const char* s2);
};

#endif // NULL_POINTER_ANALYZER_HPP
