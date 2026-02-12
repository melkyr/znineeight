#ifndef PLATFORM_HPP
#define PLATFORM_HPP

#include "common.hpp"
#include <cstddef>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

// Memory allocation
void* plat_alloc(size_t size);
void plat_free(void* ptr);
void* plat_realloc(void* ptr, size_t new_size);

// File I/O
#ifdef _WIN32
typedef HANDLE PlatFile;
#define PLAT_INVALID_FILE INVALID_HANDLE_VALUE
#else
typedef int PlatFile;
#define PLAT_INVALID_FILE (-1)
#endif

PlatFile plat_open_file(const char* path, bool write);
void plat_write_file(PlatFile file, const void* data, size_t size);
size_t plat_read_file_raw(PlatFile file, void* buffer, size_t size);
void plat_close_file(PlatFile file);
bool plat_file_read(const char* path, char** buffer, size_t* size);

// Console output
void plat_print_info(const char* message);  // stdout
void plat_print_error(const char* message); // stderr
void plat_print_debug(const char* message); // debugger only

// String operations (CRT-free on Windows)
size_t plat_strlen(const char* str);
void plat_memcpy(void* dest, const void* src, size_t n);
void plat_memmove(void* dest, const void* src, size_t n);
void plat_strcpy(char* dest, const char* src);
void plat_strncpy(char* dest, const char* src, size_t n);
int plat_strcmp(const char* s1, const char* s2);
int plat_strncmp(const char* s1, const char* s2, size_t n);
char* plat_strchr(const char* s, int c);
char* plat_strrchr(const char* s, int c);
int plat_memcmp(const void* s1, const void* s2, size_t n);
void plat_memset(void* s, int c, size_t n);

// Process execution
int plat_run_command(const char* cmd, char** output, size_t* output_size);

// Temporary files
char* plat_create_temp_file(const char* prefix, const char* suffix);

// Deletes a file. Returns 0 on success, -1 on failure.
int plat_delete_file(const char* path);

#endif // PLATFORM_HPP
