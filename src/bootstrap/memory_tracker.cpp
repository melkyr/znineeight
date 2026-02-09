#include "memory.hpp"

#ifdef MEASURE_MEMORY
size_t MemoryTracker::total_allocated = 0;
size_t MemoryTracker::peak_usage = 0;
size_t MemoryTracker::ast_nodes = 0;
size_t MemoryTracker::types = 0;
size_t MemoryTracker::symbols = 0;
size_t MemoryTracker::catalogue_entries = 0;
#endif
