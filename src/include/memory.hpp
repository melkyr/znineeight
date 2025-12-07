#ifndef MEMORY_HPP
#define MEMORY_HPP

#include <cstddef> // For size_t
#include <cstdlib> // For malloc, free
#include <cassert> // For assert

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
    char* buffer;
    size_t offset;
    size_t capacity;

public:
    /**
     * @brief Constructs an ArenaAllocator with a given capacity.
     * @param capacity The total size of the memory arena in bytes.
     */
    ArenaAllocator(size_t capacity) : buffer(nullptr), offset(0), capacity(capacity) {
        buffer = static_cast<char*>(malloc(capacity));
    }

    /**
     * @brief Destroys the ArenaAllocator, freeing the entire memory arena.
     */
    ~ArenaAllocator() {
        free(buffer);
    }

    /**
     * @brief Allocates a block of memory of a given size.
     * @param size The number of bytes to allocate.
     * @return A pointer to the allocated memory, or nullptr if the arena is full.
     */
    void* alloc(size_t size) {
        // Overflow-safe check: ensure size doesn't exceed remaining capacity.
        if (size > capacity - offset) {
            return nullptr;
        }
        void* ptr = buffer + offset;
        offset += size;
        return ptr;
    }

    /**
     * @brief Allocates a block of memory with a specific alignment.
     * @param size The number of bytes to allocate.
     * @param align The desired alignment of the memory block. Must be a power of two.
     * @return A pointer to the allocated, aligned memory, or nullptr if the arena is full.
     */
    void* alloc_aligned(size_t size, size_t align) {
        // Precondition: alignment must be a power of two.
        assert(align != 0 && (align & (align - 1)) == 0);

        // This is a common bit-twiddling trick to align a pointer.
        // It rounds the allocation start offset up to the nearest multiple of `align`.
        size_t new_offset = (offset + align - 1) & ~(align - 1);

        // Overflow-safe check: ensure the requested size fits in the remaining capacity.
        if (new_offset >= capacity || size > capacity - new_offset) {
            return nullptr;
        }

        void* ptr = buffer + new_offset;
        offset = new_offset + size;
        return ptr;
    }

    /**
     * @brief Resets the allocator, effectively freeing all allocated memory.
     * This simply resets the offset pointer to the beginning of the arena.
     */
    void reset() {
        offset = 0;
    }

private:
    // Make the class non-copyable to prevent accidental copies of the buffer.
    ArenaAllocator(const ArenaAllocator&);
    ArenaAllocator& operator=(const ArenaAllocator&);
};

#endif // MEMORY_HPP
