#ifndef STD_PAGE_PRELUDE_H
#define STD_PAGE_PRELUDE_H
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 199309L
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE 1
#endif
#include <sys/mman.h>
#include <unistd.h>
#endif
#endif
