#include "platform.hpp"

#ifdef _WIN32
// --- Windows Implementation ---

void* plat_alloc(size_t size) {
    return HeapAlloc(GetProcessHeap(), 0, size);
}

void plat_free(void* ptr) {
    if (ptr) {
        HeapFree(GetProcessHeap(), 0, ptr);
    }
}

void* plat_realloc(void* ptr, size_t new_size) {
    if (!ptr) return plat_alloc(new_size);
    return HeapReAlloc(GetProcessHeap(), 0, ptr, new_size);
}

bool plat_file_read(const char* path, char** buffer, size_t* size) {
    HANDLE hFile = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ,
                               NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return false;

    DWORD fileSize = GetFileSize(hFile, NULL);
    if (fileSize == INVALID_FILE_SIZE) {
        CloseHandle(hFile);
        return false;
    }

    *buffer = (char*)plat_alloc(fileSize + 1);
    if (!*buffer) {
        CloseHandle(hFile);
        return false;
    }

    DWORD bytesRead;
    if (!ReadFile(hFile, *buffer, fileSize, &bytesRead, NULL)) {
        plat_free(*buffer);
        CloseHandle(hFile);
        return false;
    }

    (*buffer)[fileSize] = '\0';
    if (size) *size = (size_t)fileSize;

    CloseHandle(hFile);
    return true;
}

void plat_print_info(const char* message) {
    DWORD written;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),
              message, (DWORD)plat_strlen(message),
              &written, NULL);
}

void plat_print_error(const char* message) {
    DWORD written;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE),
              message, (DWORD)plat_strlen(message),
              &written, NULL);
}

void plat_print_debug(const char* message) {
    OutputDebugStringA(message);
}

size_t plat_strlen(const char* s) {
    const char* p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

void plat_memcpy(void* dest, const void* src, size_t n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    while (n--) *d++ = *s++;
}

void plat_memmove(void* dest, const void* src, size_t n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--) *--d = *--s;
    }
}

void plat_strcpy(char* dest, const char* src) {
    while ((*dest++ = *src++))
        ;
}

void plat_strncpy(char* dest, const char* src, size_t n) {
    size_t i;
    for (i = 0; i < n && src[i] != '\0'; i++)
        dest[i] = src[i];
    for ( ; i < n; i++)
        dest[i] = '\0';
}

int plat_strcmp(const char* s1, const char* s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

int plat_strncmp(const char* s1, const char* s2, size_t n) {
    while (n && *s1 && (*s1 == *s2)) {
        s1++;
        s2++;
        n--;
    }
    if (n == 0) return 0;
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

int plat_memcmp(const void* s1, const void* s2, size_t n) {
    const unsigned char* p1 = (const unsigned char*)s1;
    const unsigned char* p2 = (const unsigned char*)s2;
    while (n--) {
        if (*p1 != *p2) return *p1 - *p2;
        p1++;
        p2++;
    }
    return 0;
}

void plat_memset(void* s, int c, size_t n) {
    unsigned char* p = (unsigned char*)s;
    while (n--) *p++ = (unsigned char)c;
}

#else
// --- Linux/POSIX Implementation ---

#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <cstdlib>
#include <cstring>

void* plat_alloc(size_t size) {
    return malloc(size);
}

void plat_free(void* ptr) {
    free(ptr);
}

void* plat_realloc(void* ptr, size_t new_size) {
    return realloc(ptr, new_size);
}

bool plat_file_read(const char* path, char** buffer, size_t* size) {
    int fd = open(path, O_RDONLY);
    if (fd == -1) return false;

    struct stat st;
    if (fstat(fd, &st) == -1) {
        close(fd);
        return false;
    }

    *buffer = (char*)plat_alloc(st.st_size + 1);
    if (!*buffer) {
        close(fd);
        return false;
    }

    ssize_t bytesRead = read(fd, *buffer, st.st_size);
    if (bytesRead == -1) {
        plat_free(*buffer);
        close(fd);
        return false;
    }

    (*buffer)[st.st_size] = '\0';
    if (size) *size = (size_t)st.st_size;

    close(fd);
    return true;
}

void plat_print_info(const char* message) {
    write(STDOUT_FILENO, message, plat_strlen(message));
}

void plat_print_error(const char* message) {
    write(STDERR_FILENO, message, plat_strlen(message));
}

void plat_print_debug(const char* message) {
    // On Linux, we just print to stderr for "debug"
    plat_print_error("[DEBUG] ");
    plat_print_error(message);
}

size_t plat_strlen(const char* s) {
    return strlen(s);
}

void plat_memcpy(void* dest, const void* src, size_t n) {
    memcpy(dest, src, n);
}

void plat_memmove(void* dest, const void* src, size_t n) {
    memmove(dest, src, n);
}

void plat_strcpy(char* dest, const char* src) {
    strcpy(dest, src);
}

void plat_strncpy(char* dest, const char* src, size_t n) {
    strncpy(dest, src, n);
}

int plat_strcmp(const char* s1, const char* s2) {
    return strcmp(s1, s2);
}

int plat_strncmp(const char* s1, const char* s2, size_t n) {
    return strncmp(s1, s2, n);
}

int plat_memcmp(const void* s1, const void* s2, size_t n) {
    return memcmp(s1, s2, n);
}

void plat_memset(void* s, int c, size_t n) {
    memset(s, c, n);
}

#endif
