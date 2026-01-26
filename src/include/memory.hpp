#ifndef MEMORY_HPP
#define MEMORY_HPP

#include "common.hpp"
#include <cstddef> // For size_t
#include <cstdlib> // For malloc, free
#include <cassert> // For assert
#include <cstring> // For memcpy
#include <new>     // For placement new

#ifdef _WIN32
#include <windows.h> // For OutputDebugStringA
#endif

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
#ifdef DEBUG
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
    memmove(buffer, buffer + i, len + 1);
}
#endif // DEBUG


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
#ifdef DEBUG
static void safe_append(char*& dest_ptr, size_t& remaining, const char* src) {
    if (remaining <= 1) return; // Not enough space for content + null terminator
    size_t len = strlen(src);
    size_t to_copy = len;
    if (to_copy >= remaining) {
        to_copy = remaining - 1;
    }
    memcpy(dest_ptr, src, to_copy);
    dest_ptr += to_copy;
    remaining -= to_copy;
    *dest_ptr = '\0'; // Always keep the buffer null-terminated
}

static void report_out_of_memory(const char* context, size_t requested, size_t p1, size_t p2, size_t p3) {
#ifdef _WIN32
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

    OutputDebugStringA(buffer);
#endif
}

/**
 * @brief Generic out-of-memory reporter for callsites that do not provide context.
 */
static void report_out_of_memory() {
    report_out_of_memory("Unknown", 0, 0, 0, 0);
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
#ifdef DEBUG
            report_out_of_memory("ArenaAllocator::alloc_aligned", size, new_offset, offset, capacity);
#endif
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
     * @brief Resets the allocator to a specific offset.
     * @param checkpoint The offset to restore the arena to.
     */
    void reset(size_t checkpoint) {
        offset = checkpoint;
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
