#include "call_site_lookup_table.hpp"
#include "platform.hpp"
#include "utils.hpp"

CallSiteLookupTable::CallSiteLookupTable(ArenaAllocator& arena)
    : arena_(arena) {
    entries_ = (DynamicArray<CallSiteEntry>*)arena.alloc(sizeof(DynamicArray<CallSiteEntry>));
    new (entries_) DynamicArray<CallSiteEntry>(arena);
}

int CallSiteLookupTable::addEntry(ASTNode* call_node, const char* context) {
    CallSiteEntry entry;
    entry.call_node = call_node;
    entry.mangled_name = NULL;
    entry.context = context;
    entry.call_type = CALL_DIRECT;
    entry.resolved = false;
    entry.error_if_unresolved = NULL;

    int id = entries_->length();
    entries_->append(entry);
    return id;
}

void CallSiteLookupTable::resolveEntry(int id, const char* mangled_name, CallType type) {
    if (id < 0 || id >= (int)entries_->length()) return;
    CallSiteEntry& entry = (*entries_)[id];
    entry.mangled_name = mangled_name;
    entry.call_type = type;
    entry.resolved = true;
}

void CallSiteLookupTable::markUnresolved(int id, const char* reason, CallType type) {
    if (id < 0 || id >= (int)entries_->length()) return;
    CallSiteEntry& entry = (*entries_)[id];
    entry.error_if_unresolved = reason;
    entry.call_type = type;
    entry.resolved = false;
}

int CallSiteLookupTable::count() const {
    return entries_->length();
}

int CallSiteLookupTable::getUnresolvedCount() const {
    int count = 0;
    for (size_t i = 0; i < entries_->length(); ++i) {
        if (!(*entries_)[i].resolved) {
            count++;
        }
    }
    return count;
}

const CallSiteEntry& CallSiteLookupTable::getEntry(int id) const {
    return (*entries_)[id];
}

const CallSiteEntry* CallSiteLookupTable::findByCallNode(ASTNode* call_node) const {
    for (size_t i = 0; i < entries_->length(); ++i) {
        if ((*entries_)[i].call_node == call_node) {
            return &(*entries_)[i];
        }
    }
    return NULL;
}

void CallSiteLookupTable::printUnresolved() const {
    for (size_t i = 0; i < entries_->length(); ++i) {
        const CallSiteEntry& entry = (*entries_)[i];
        if (!entry.resolved) {
            char buffer[512];
            char line_buf[21], col_buf[21];
            simple_itoa(entry.call_node->loc.line, line_buf, sizeof(line_buf));
            simple_itoa(entry.call_node->loc.column, col_buf, sizeof(col_buf));

            char* current = buffer;
            size_t remaining = sizeof(buffer);

            safe_append(current, remaining, "Unresolved call at ");
            safe_append(current, remaining, line_buf);
            safe_append(current, remaining, ":");
            safe_append(current, remaining, col_buf);
            safe_append(current, remaining, " in context '");
            safe_append(current, remaining, entry.context);
            safe_append(current, remaining, "'");

            if (entry.error_if_unresolved) {
                safe_append(current, remaining, " Reason: ");
                safe_append(current, remaining, entry.error_if_unresolved);
            }

            plat_print_info(buffer);
        }
    }
}
