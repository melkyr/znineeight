#ifndef SOURCE_MANAGER_HPP
#define SOURCE_MANAGER_HPP

#include "common.hpp"
#include "memory.hpp"

/**
 * @struct SourceLocation
 * @brief Represents a specific location within a source file.
 *
 * This struct is used throughout the compiler to pinpoint the exact location
 * of tokens, AST nodes, and errors, using a file identifier, line number,
 * and column number.
 */
struct SourceLocation {
    /** @brief The unique identifier of the source file. */
    u32 file_id;
    /** @brief The line number within the file (1-based). */
    u32 line;
    /** @brief The column number within the line (1-based). */
    u32 column;

    SourceLocation() : file_id(0), line(0), column(0) {}
    SourceLocation(u32 id, u32 l, u32 c) : file_id(id), line(l), column(c) {}
};

/**
 * @struct SourceFile
 * @brief Represents a single source file managed by the SourceManager.
 *
 * This struct stores the filename, a pointer to its content, and the size of the content.
 */
struct SourceFile {
    /** @brief The name of the source file. */
    const char* filename;
    /** @brief A pointer to the memory buffer containing the file's content. */
    const char* content;
    /** @brief The size of the content buffer in bytes. */
    size_t size;
};

/**
 * @class SourceManager
 * @brief Manages all source files being compiled.
 *
 * The SourceManager is responsible for loading and storing the content of source files,
 * mapping offsets to line and column numbers, and providing a centralized point of access
 * for all source-related information.
 */
class SourceManager {
    ArenaAllocator& allocator;
    DynamicArray<SourceFile> files;

public:
    /**
     * @brief Constructs a SourceManager.
     * @param alloc The ArenaAllocator to be used for storing file information.
     */
    SourceManager(ArenaAllocator& alloc) : allocator(alloc), files(alloc) {}

    /**
     * @brief Adds a new source file to the manager.
     * @param filename The name of the file.
     * @param content A pointer to the file's content.
     * @param size The size of the content in bytes.
     * @return The unique file identifier for the newly added file.
     */
    u32 addFile(const char* filename, const char* content, size_t size);

    /**
     * @brief Converts a file ID and offset into a SourceLocation (line and column).
     * @param file_id The unique identifier of the file.
     * @param offset The character offset from the beginning of the file.
     * @return A SourceLocation struct with the corresponding line and column.
     */
    SourceLocation getLocation(u32 file_id, size_t offset);

    /**
     * @brief Retrieves a pointer to a SourceFile struct by its ID.
     * @param file_id The unique identifier of the file.
     * @return A const pointer to the SourceFile, or NULL if the ID is invalid.
     */
    const SourceFile* getFile(u32 file_id) const;
};

#endif // SOURCE_MANAGER_HPP
