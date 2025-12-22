#ifndef MEMORY_HPP
#define MEMORY_HPP

#include "common.hpp"
#include <cstddef> // For size_t
#include <cstdlib> // For malloc, free
#include <cassert> // For assert
#include <cstring> // For memcpy
#include <new>     // For placement new

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
     * @brief Destroys the ArenaAllocator, freeing the entire memory arena.
     */
    ~ArenaAllocator() {
        free(buffer);
    }

    /**
     * @brief Allocates a block of memory with a default 8-byte alignment.
     *
     * This method is the primary, simplified interface for allocation. It guarantees
     * that the returned pointer is aligned to at least 8 bytes, which is safe for
     * most data types, including `double` and `__int64`. For specific alignment
     * needs, use `alloc_aligned`.
     *
     * @param size The number of bytes to allocate.
     * @return A pointer to the allocated memory, or nullptr if the allocation fails.
     */
    void* alloc(size_t size) {
        return alloc_aligned(size, 8);  // Default to 8-byte alignment
    }

    /**
     * @brief Allocates a block of memory with a specific alignment and overflow protection.
     * @param size The number of bytes to allocate.
     * @param align The desired alignment of the memory block. Must be a power of two.
     * @return A pointer to the allocated, aligned memory, or nullptr if the arena is full.
     */
    void* alloc_aligned(size_t size, size_t align) {
        if (size == 0) {
            return NULL;
        }
        assert(align != 0 && (align & (align - 1)) == 0);

        const size_t mask = align - 1;
        size_t new_offset = (offset + mask) & ~mask;

        // Check overflow and capacity
        if (new_offset < offset || new_offset > capacity - size) {
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

    /**
     * @brief Returns the current memory offset within the arena.
     * @return The number of bytes currently allocated.
     */
    size_t getOffset() const {
        return offset;
    }

private:
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
     *
     * @warning This operation can be expensive. It allocates a new memory block
     * and copy-constructs all existing elements into it using placement new.
     * This is safe for non-POD types but does not call destructors on the old
     * objects, as is standard for arena-based allocators.
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
        assert(new_data);

        // Use placement new to copy-construct elements into the new buffer
        for (size_t i = 0; i < len; ++i) {
            new (&new_data[i]) T(data[i]);
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
