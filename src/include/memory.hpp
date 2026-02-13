#ifndef MEMORY_HPP
#define MEMORY_HPP

#include "common.hpp"
#include "platform.hpp"
#include <cstddef> // For size_t
#include <cassert> // For assert
#include <cstdlib> // For abort()
#include <new>     // For placement new

/**
 * @brief A simple integer-to-string conversion function.
 *
 * This function converts an unsigned `size_t` integer to its string
 * representation. It is designed to be dependency-free, avoiding stdio
 * functions like `sprintf` to comply with project constraints.
 *
 * @param value The integer value to convert.
 * @param buffer A character buffer to store the resulting string.
 * @param buffer_size The size of the buffer.
 */
static void arena_simple_itoa(size_t value, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    buffer[--buffer_size] = '\0'; // Null-terminate

    if (value == 0) {
        if (buffer_size > 0) {
            buffer[0] = '0';
            buffer[1] = '\0';
        }
        return;
    }

    size_t i = buffer_size;
    while (value > 0 && i > 0) {
        buffer[--i] = (value % 10) + '0';
        value /= 10;
    }

    // Shift the number to the start of the buffer
    size_t len = buffer_size - i;
    plat_memmove(buffer, buffer + i, len + 1);
}


/**
 * @brief Safely appends a source string to a destination buffer.
 *
 * This function appends `src` to the buffer pointed to by `dest_ptr`,
 * ensuring that it does not write past the buffer's boundary. It updates
 * `dest_ptr` to point to the new null terminator and decrements `remaining`
 * by the number of characters written.
 *
 * @param dest_ptr A reference to a pointer to the current position in the buffer.
 * @param remaining A reference to the remaining size of the buffer.
 * @param src The null-terminated string to append.
 */
static void safe_append(char*& dest_ptr, size_t& remaining, const char* src) {
    if (remaining <= 1) return; // Not enough space for content + null terminator
    size_t len = plat_strlen(src);
    size_t to_copy = len;
    if (to_copy >= remaining) {
        to_copy = remaining - 1;
    }
    plat_memcpy(dest_ptr, src, to_copy);
    dest_ptr += to_copy;
    remaining -= to_copy;
    *dest_ptr = '\0'; // Always keep the buffer null-terminated
}

#ifdef MEASURE_MEMORY
class MemoryTracker {
public:
    static size_t total_allocated;
    static size_t peak_usage;
    static size_t ast_nodes;
    static size_t types;
    static size_t symbols;
    static size_t catalogue_entries;

    static void record_allocation(size_t size) {
        total_allocated += size;
        if (total_allocated > peak_usage) {
            peak_usage = total_allocated;
        }
    }

    static void record_free(size_t size) {
        if (size <= total_allocated) {
            total_allocated -= size;
        } else {
            total_allocated = 0;
        }
    }

    static void reset_counts() {
        ast_nodes = 0;
        types = 0;
        symbols = 0;
        catalogue_entries = 0;
    }
};
#endif

#ifdef DEBUG
/**
 * @brief Reports a detailed out-of-memory error before aborting.
 *
 * This function provides a centralized way to report memory exhaustion with
 * contextual information. On Windows, it uses the Win32 API to output a
 * detailed message to the debugger. On other platforms, it does nothing to
 * adhere to project constraints.
 *
 * @param context A string describing the context of the failure (e.g., function name).
 * @param requested The amount of memory requested.
 * @param p1 Optional parameter 1 for context.
 * @param p2 Optional parameter 2 for context.
 * @param p3 Optional parameter 3 for context.
 */
static void report_out_of_memory(const char* context, size_t requested, size_t p1, size_t p2, size_t p3) {
    char buffer[256];
    char* current = buffer;
    size_t remaining = sizeof(buffer);
    buffer[0] = '\0';

    char n_requested[21], n_p1[21], n_p2[21], n_p3[21];
    arena_simple_itoa(requested, n_requested, sizeof(n_requested));
    arena_simple_itoa(p1, n_p1, sizeof(n_p1));
    arena_simple_itoa(p2, n_p2, sizeof(n_p2));
    arena_simple_itoa(p3, n_p3, sizeof(n_p3));

    safe_append(current, remaining, "Out of memory in ");
    safe_append(current, remaining, context);
    safe_append(current, remaining, ". Requested: ");
    safe_append(current, remaining, n_requested);
    safe_append(current, remaining, ", P1: ");
    safe_append(current, remaining, n_p1);
    safe_append(current, remaining, ", P2: ");
    safe_append(current, remaining, n_p2);
    safe_append(current, remaining, ", P3: ");
    safe_append(current, remaining, n_p3);
    safe_append(current, remaining, "\n");

    plat_print_debug(buffer);
}

#endif // DEBUG


/**
 * @class ArenaAllocator
 * @brief A simple bump allocator for fast, region-based memory management.
 *
 * This allocator pre-allocates a large block of memory (the arena) and serves
 * allocation requests by simply "bumping" a pointer forward. All memory is
 * freed at once by resetting the arena. This is highly efficient for phase-based
 * memory management, such as during different stages of a compiler.
 */
class ArenaAllocator {
    struct Chunk {
        Chunk* next;
        size_t capacity;
        size_t offset;
    };

    Chunk* head;
    size_t total_cap;
    size_t total_allocated_from_os;
    size_t total_used_for_stats; // To maintain compatibility with old getOffset() behavior

public:
    /**
     * @brief Constructs an ArenaAllocator with a maximum capacity cap.
     * @param capacity_cap The maximum total size of the memory arena in bytes.
     */
    ArenaAllocator(size_t capacity_cap)
        : head(NULL), total_cap(capacity_cap), total_allocated_from_os(0), total_used_for_stats(0) {}

    /**
     * @brief Destroys the ArenaAllocator, freeing all memory chunks.
     */
    ~ArenaAllocator() {
        freeAllChunks();
    }

    /**
     * @brief Allocates a block of memory with a default 8-byte alignment.
     *
     * This method is the primary interface for allocation. It guarantees
     * that the returned pointer is aligned to at least 8 bytes.
     *
     * @param size The number of bytes to allocate.
     * @return A pointer to the allocated memory, or NULL if the allocation fails.
     */
    void* alloc(size_t size) {
        return alloc_aligned(size, 8);
    }

    /**
     * @brief Allocates a block of memory with a specific alignment and overflow protection.
     *
     * @param size The number of bytes to allocate.
     * @param align The desired alignment of the memory block. Must be a power of two.
     * @return A pointer to the allocated, aligned memory, or NULL if the arena is full or
     *         allocation fails.
     */
    void* alloc_aligned(size_t size, size_t align) {
        if (size == 0) {
            return NULL;
        }
        assert(align != 0 && (align & (align - 1)) == 0);

        // Check if this request would exceed total_cap regardless of chunking
        // This maintains compatibility with tests using small capacities.
        if (total_used_for_stats + size > total_cap) {
#ifdef DEBUG
            char dbg[256];
            char* cur = dbg;
            size_t rem = sizeof(dbg);
            char n_used[21], n_size[21], n_cap[21];
            arena_simple_itoa(total_used_for_stats, n_used, sizeof(n_used));
            arena_simple_itoa(size, n_size, sizeof(n_size));
            arena_simple_itoa(total_cap, n_cap, sizeof(n_cap));

            dbg[0] = '\0';
            safe_append(cur, rem, "DEBUG: total_used=");
            safe_append(cur, rem, n_used);
            safe_append(cur, rem, ", size=");
            safe_append(cur, rem, n_size);
            safe_append(cur, rem, ", cap=");
            safe_append(cur, rem, n_cap);
            safe_append(cur, rem, "\n");

            plat_print_debug(dbg);
            report_out_of_memory("ArenaAllocator::alloc_aligned (total_cap)", size, total_used_for_stats, 0, total_cap);
#endif
            return NULL;
        }

        // Try current chunk
        if (head) {
            void* p = try_alloc_in_chunk(head, size, align);
            if (p) return p;
        }

        // Need new chunk. For small caps, don't use 1MB chunks.
        size_t chunk_size = 1024 * 1024; // 1MB default
        if (chunk_size > total_cap && total_cap > 0) {
            chunk_size = total_cap + sizeof(Chunk) + 32; // Allow some slack for headers/alignment
        }

        // Ensure the chunk is large enough for the requested size plus header
        size_t min_needed = size + align + sizeof(Chunk);
        if (chunk_size < min_needed) {
            chunk_size = min_needed;
        }

        void* mem = plat_alloc(chunk_size);
        if (!mem) return NULL;

        Chunk* new_chunk = (Chunk*)mem;
        new_chunk->next = head;
        new_chunk->capacity = chunk_size;
        new_chunk->offset = sizeof(Chunk);

        head = new_chunk;
        total_allocated_from_os += chunk_size;

        return try_alloc_in_chunk(head, size, align);
    }

    /**
     * @brief Resets the allocator, freeing all chunks and resetting capacity.
     *
     * Unlike the previous simple bump-pointer implementation, this version
     * actually frees the memory chunks back to the operating system.
     */
    void reset() {
#ifdef MEASURE_MEMORY
        MemoryTracker::record_free(getOffset());
#endif
        freeAllChunks();
    }

    /**
     * @brief Resets the allocator to a specific offset.
     *
     * NOTE: This is complex with multiple chunks. Currently, only a checkpoint
     * of 0 is supported, which is equivalent to calling reset().
     *
     * @param checkpoint The offset to restore the arena to. Must be 0.
     */
    void reset(size_t checkpoint) {
        if (checkpoint == 0) {
            reset();
        } else {
            // For bootstrap, full reset is usually what's needed.
            // If we really need partial reset, we'd need to track chunks better.
            assert(false && "Partial reset not supported in chunked arena");
        }
    }

    /**
     * @brief Returns the current memory offset within the arena.
     *
     * This returns the total number of bytes currently served to callers,
     * including alignment padding, across all allocated chunks.
     *
     * @return The number of bytes currently used.
     */
    size_t getOffset() const {
        return total_used_for_stats;
    }

    /**
     * @brief Returns the maximum total capacity cap of the arena.
     * @return The total capacity limit in bytes.
     */
    size_t getCapacity() const {
        return total_cap;
    }

    /**
     * @brief Returns true if any memory has been allocated from the OS.
     * @return True if at least one chunk exists.
     */
    bool isAllocated() const {
        return head != NULL;
    }

    /**
     * @brief Returns the number of chunks currently allocated from the OS.
     * @return The count of chunks.
     */
    size_t getChunkCount() const {
        size_t count = 0;
        Chunk* c = head;
        while (c) {
            count++;
            c = c->next;
        }
        return count;
    }

    /**
     * @brief Allocates space for a string in the arena and copies it.
     * @param str The string to copy.
     * @return A pointer to the copied string in the arena.
     */
    char* allocString(const char* str) {
        if (!str) return NULL;
        size_t len = plat_strlen(str);
        char* mem = (char*)alloc(len + 1);
        if (mem) {
            plat_memcpy(mem, str, len + 1);
        }
        return mem;
    }

private:
    void* try_alloc_in_chunk(Chunk* chunk, size_t size, size_t align) {
        const size_t mask = align - 1;
        size_t aligned_offset = (chunk->offset + mask) & ~mask;

        // Note: we still need to check total_cap here because of alignment padding
        size_t padding = aligned_offset - chunk->offset;
        if (total_used_for_stats + padding + size > total_cap) {
            return NULL;
        }

        if (aligned_offset + size <= chunk->capacity) {
#ifdef MEASURE_MEMORY
            size_t actual_size = padding + size;
            MemoryTracker::record_allocation(actual_size);
#endif
            void* ptr = (u8*)chunk + aligned_offset;
            chunk->offset = aligned_offset + size;
            total_used_for_stats += (padding + size);
            return ptr;
        }
        return NULL;
    }

    void freeAllChunks() {
        Chunk* c = head;
        while (c) {
            Chunk* next = c->next;
            plat_free(c);
            c = next;
        }
        head = NULL;
        total_allocated_from_os = 0;
        total_used_for_stats = 0;
    }

    // Make the class non-copyable to prevent accidental copies of the buffer.
    ArenaAllocator(const ArenaAllocator&);
    ArenaAllocator& operator=(const ArenaAllocator&);

    friend class ArenaLifetimeGuard;
};

/**
 * @class DynamicArray
 * @brief A simple dynamic array that uses an ArenaAllocator for memory.
 *
 * This class provides a basic, resizable array implementation. When the array's
 * capacity is exhausted, it reallocates a larger block of memory from the arena
 * and copies the existing elements. The old memory block is not freed, as the
 * arena will handle that in its lifecycle.
 */
template <typename T>
class DynamicArray {
    ArenaAllocator& allocator;
    T* data;
    size_t len;
    size_t cap;

public:
    /**
     * @brief Constructs a DynamicArray.
     * @param allocator The ArenaAllocator to use for all memory allocations.
     */
    DynamicArray(ArenaAllocator& allocator)
        : allocator(allocator), data(NULL), len(0), cap(0) {}

    /**
     * @brief Ensures the array has at least a given capacity.
     *
     * If the current capacity is insufficient, it reallocates a larger buffer.
     * The new capacity is doubled, or set to the minimum required if that's larger.
     * This operation is safe for non-POD types as it uses placement new for
     * copy construction and manually calls destructors on the old elements.
     *
     * @param min_cap The minimum required capacity.
     */
    void ensure_capacity(size_t min_cap) {
        if (cap >= min_cap) return;

        size_t new_cap = (cap == 0) ? 8 : cap * 2;
        if (new_cap < min_cap) {
            new_cap = min_cap;
        }

        T* new_data = static_cast<T*>(allocator.alloc(new_cap * sizeof(T)));
        if (!new_data) {
            // The allocator has already reported the error, so we just abort.
            abort();
        }

        // Safely copy-construct elements to the new buffer
        for (size_t i = 0; i < len; ++i) {
            new (&new_data[i]) T(data[i]);
        }

        // Manually destruct the old objects.
        // The old `data` buffer itself is managed by the arena and is not freed here.
        if (data) {
            for (size_t i = 0; i < len; ++i) {
                data[i].~T();
            }
        }

        data = new_data;
        cap = new_cap;
    }

    /**
     * @brief Appends an item to the end of the array.
     * If the array is full, it will trigger a reallocation.
     * @param item The item to append.
     */
    void append(const T& item) {
        ensure_capacity(len + 1);
        data[len] = item;
        ++len;
    }

    /**
     * @brief Removes the last element from the array.
     * Does not call the destructor on the removed element.
     */
    void pop_back() {
        if (len > 0) {
            --len;
        }
    }

    /**
     * @brief Returns a reference to the last element in the array.
     */
    T& back() {
        assert(len > 0);
        return data[len - 1];
    }

    /**
     * @brief Returns a const reference to the last element in the array.
     */
    const T& back() const {
        assert(len > 0);
        return data[len - 1];
    }

    /**
     * @brief Returns the number of elements in the array.
     */
    size_t length() const {
        return len;
    }

    /**
     * @brief Clears the array by resetting its length to zero.
     * Does not deallocate memory, which is managed by the arena.
     */
    void clear() {
        len = 0;
    }

    size_t getCapacity() const {
        return cap;
    }

    /**
     * @brief Provides access to an element by its index.
     */
    T& operator[](size_t index) {
        assert(index < len);
        return data[index];
    }

    // Public assignment operator for shallow copying.
    // This is safe because memory is managed by the ArenaAllocator, not the array object itself.
    DynamicArray& operator=(const DynamicArray& other) {
        if (this != &other) {
            data = other.data;
            len = other.len;
            cap = other.cap;
            // The allocator reference is intentionally not copied.
        }
        return *this;
    }

    /**
     * @brief Provides const access to an element by its index.
     */
    const T& operator[](size_t index) const {
        assert(index < len);
        return data[index];
    }

    /**
     * @brief Returns a pointer to the underlying data buffer.
     */
    T* getData() {
        return data;
    }
};

#endif // MEMORY_HPP
