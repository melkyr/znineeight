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
int plat_memcmp(const void* s1, const void* s2, size_t n);
void plat_memset(void* s, int c, size_t n);

#endif // PLATFORM_HPP
