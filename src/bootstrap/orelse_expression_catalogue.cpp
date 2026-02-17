#include "orelse_expression_catalogue.hpp"
#include <new>

OrelseExpressionCatalogue::OrelseExpressionCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<OrelseExpressionInfo>));
    if (!mem) plat_abort();
    orelse_expressions_ = new (mem) DynamicArray<OrelseExpressionInfo>(arena_);
}

void OrelseExpressionCatalogue::addOrelseExpression(SourceLocation loc, const char* context_type,
                                                 Type* left_type, Type* right_type, Type* result_type) {
    OrelseExpressionInfo info;
    info.location = loc;
    info.context_type = context_type;
    info.left_type = left_type;
    info.right_type = right_type;
    info.result_type = result_type;
    orelse_expressions_->append(info);
}

int OrelseExpressionCatalogue::count() const {
    return (int)orelse_expressions_->length();
}
