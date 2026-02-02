#include "errdefer_catalogue.hpp"
#include <new>

ErrDeferCatalogue::ErrDeferCatalogue(ArenaAllocator& arena) : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<ErrDeferInfo>));
    err_defers_ = new (mem) DynamicArray<ErrDeferInfo>(arena_);
}

void ErrDeferCatalogue::addErrDefer(SourceLocation loc) {
    ErrDeferInfo info;
    info.location = loc;
    err_defers_->append(info);
}

int ErrDeferCatalogue::count() const {
    return (int)err_defers_->length();
}
