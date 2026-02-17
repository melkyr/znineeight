#include "indirect_call_catalogue.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <new>

IndirectCallCatalogue::IndirectCallCatalogue(ArenaAllocator& arena) : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<IndirectCallInfo>));
    if (mem == NULL) plat_abort();
   entries_ = new (mem) DynamicArray<IndirectCallInfo>(arena_);
}

void IndirectCallCatalogue::addIndirectCall(const IndirectCallInfo& info) {
    entries_->append(info);
}

int IndirectCallCatalogue::count() const {
    return (int)entries_->length();
}

const IndirectCallInfo& IndirectCallCatalogue::get(int index) const {
    return (*entries_)[index];
}

const IndirectCallInfo* IndirectCallCatalogue::findByLocation(SourceLocation loc) const {
    for (size_t i = 0; i < entries_->length(); ++i) {
        const IndirectCallInfo& info = (*entries_)[i];
        if (info.location.line == loc.line &&
            info.location.column == loc.column &&
            info.location.file_id == loc.file_id) {
            return &info;
        }
    }
    return NULL;
}

const char* IndirectCallCatalogue::getReasonString(IndirectType type) {
    switch (type) {
        case INDIRECT_VARIABLE: return "function pointer variable";
        case INDIRECT_MEMBER:   return "member function pointer";
        case INDIRECT_ARRAY:    return "array of function pointers";
        case INDIRECT_RETURNED: return "returned function";
        case INDIRECT_COMPLEX:  return "complex expression";
        default:                return "indirect call";
    }
}
