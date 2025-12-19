#ifndef MEMORY_HPP
#define MEMORY_HPP

#include "common.hpp"
#include <cstddef> // For size_t
#include <cstdlib> // For malloc, free
#include <cassert> // For assert
#include <cstring> // For memcpy

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
    u8* buffer;
    size_t offset;
    size_t capacity;

public:
    /**
     * @brief Constructs an ArenaAllocator with a given capacity.
     * @param capacity The total size of the memory arena in bytes.
     */
    ArenaAllocator(size_t capacity) : offset(0), capacity(capacity) {
        buffer = (u8*)malloc(capacity);
    }


    /**
     * @brief Allocates a block of memory of a given size.
     * @param size The number of bytes to allocate.
     * @return A pointer to the allocated memory, or nullptr if the arena is full.
     */
    void* alloc(size_t size) {
        // Overflow-safe check: ensure size doesn't exceed remaining capacity.
        if (size > capacity - offset) {
            return NULL;
        }
        u8* ptr = buffer + offset;
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
            return NULL;
        }

        u8* ptr = buffer + new_offset;
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
     * @param min_cap The minimum required capacity.
     */
    void ensure_capacity(size_t min_cap) {
        if (cap < min_cap) {
            size_t new_cap = (cap == 0) ? 8 : cap * 2;
            if (new_cap < min_cap) {
                new_cap = min_cap;
            }
            T* new_data = static_cast<T*>(allocator.alloc(new_cap * sizeof(T)));
            assert(new_data);
            if (data) {
                memcpy(new_data, data, len * sizeof(T));
            }
            data = new_data;
            cap = new_cap;
        }
    }

    /**
     * @brief Appends an item to the end of the array.
     * @param item The item to append.
     */
    void append(const T& item) {
        if (len == cap) {
            size_t new_cap = (cap == 0) ? 8 : cap * 2;
            T* new_data = static_cast<T*>(allocator.alloc(new_cap * sizeof(T)));

            // If the allocation fails, we can't proceed. This is considered a
            // fatal error for this compiler, as the arena is expected to be
            // large enough for the compilation unit.
            assert(new_data);

            // Copy existing data to the new buffer.
            if (data) {
                memcpy(new_data, data, len * sizeof(T));
            }
            data = new_data;
            cap = new_cap;
        }
        data[len++] = item;
    }

    /**
     * @brief Returns the number of elements in the array.
     */
    size_t length() const {
        return len;
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
