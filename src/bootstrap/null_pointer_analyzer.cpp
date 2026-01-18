#include "null_pointer_analyzer.hpp"
#include "ast.hpp"
#include "error_handler.hpp"
#include <new>
#include <cstring>

NullPointerAnalyzer::NullPointerAnalyzer(ArenaAllocator& arena, CompilationUnit& unit)
    : unit(unit), arena(arena), currentScope(NULL), scopes(arena) {
}

void NullPointerAnalyzer::analyze(ASTNode* root) {
    if (!root) return;

    // Phase 1C requirement: Handle global scope
    pushScope();
    visit(root);
    popScope();
}

void NullPointerAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_FN_DECL:
            visitFnDecl(node->as.fn_decl);
            break;
        case NODE_BLOCK_STMT:
            visitBlockStmt(&node->as.block_stmt);
            break;
        case NODE_VAR_DECL:
            // In Phase 1, we track both local and global var decls here
            // using the current scope.
            visitVarDecl(node->as.var_decl);
            break;
        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;
        default:
            // Skip other nodes in Phase 1
            break;
    }
}

void NullPointerAnalyzer::visitGlobalVar(ASTNode* node) {
    if (!node || node->type != NODE_VAR_DECL) return;
    visitVarDecl(node->as.var_decl);
}

void NullPointerAnalyzer::visitFnDecl(ASTFnDeclNode* node) {
    pushScope();
    // Track parameters if any (all considered MAYBE for now, except if they have attributes)
    if (node->params) {
        for (size_t i = 0; i < node->params->length(); ++i) {
            ASTParamDeclNode* param = (*node->params)[i];
            setState(param->name, STATE_MAYBE);
        }
    }
    visit(node->body);
    popScope();
}

void NullPointerAnalyzer::visitBlockStmt(ASTBlockStmtNode* node) {
    pushScope();
    if (node->statements) {
        for (size_t i = 0; i < node->statements->length(); ++i) {
            visit((*node->statements)[i]);
        }
    }
    popScope();
}

void NullPointerAnalyzer::visitVarDecl(ASTVarDeclNode* node) {
    // Phase 1: Just track the variable and its basic state if it's a pointer.
    // For now, assume it's a pointer if we want to track it, or just track all for simplicity.
    // Ideally check if node->type is a pointer type.

    State initialState = STATE_UNINIT;
    if (node->initializer) {
        if (node->initializer->type == NODE_NULL_LITERAL) {
            initialState = STATE_NULL;
        } else if (node->initializer->type == NODE_UNARY_OP && node->initializer->as.unary_op.op == TOKEN_AMPERSAND) {
            initialState = STATE_SAFE;
        } else {
            initialState = STATE_MAYBE;
        }
    }

    setState(node->name, initialState);
}

void NullPointerAnalyzer::pushScope() {
    void* mem = arena.alloc(sizeof(DynamicArray<VarTrack>));
    DynamicArray<VarTrack>* newScope = new (mem) DynamicArray<VarTrack>(arena);
    scopes.append(newScope);
    currentScope = newScope;
}

void NullPointerAnalyzer::popScope() {
    if (scopes.length() > 0) {
        scopes.pop_back();
        if (scopes.length() > 0) {
            currentScope = scopes.back();
        } else {
            currentScope = NULL;
        }
    }
}

void NullPointerAnalyzer::setState(const char* name, State state) {
    if (!currentScope) return;

    // Check if already in current scope
    for (size_t i = 0; i < currentScope->length(); ++i) {
        if (stringsEqual((*currentScope)[i].name, name)) {
            (*currentScope)[i].state = state;
            return;
        }
    }

    // Otherwise, add to current scope
    VarTrack vt;
    vt.name = name;
    vt.state = state;
    currentScope->append(vt);
}

NullPointerAnalyzer::State NullPointerAnalyzer::getState(const char* name) {
    // Search from innermost scope outwards
    for (int i = (int)scopes.length() - 1; i >= 0; --i) {
        DynamicArray<VarTrack>* scope = scopes[i];
        for (size_t j = 0; j < scope->length(); ++j) {
            if (stringsEqual((*scope)[j].name, name)) {
                return (*scope)[j].state;
            }
        }
    }
    return STATE_MAYBE;
}

bool NullPointerAnalyzer::stringsEqual(const char* s1, const char* s2) {
    if (s1 == s2) return true;
    if (!s1 || !s2) return false;
    return strcmp(s1, s2) == 0;
}
