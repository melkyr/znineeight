#ifndef COMMON_HPP
#define COMMON_HPP

#include "compat.hpp"

/* Assertion support */
#define Z98_STRINGIFY_HELPER(x) #x
#define Z98_STRINGIFY(x) Z98_STRINGIFY_HELPER(x)

#ifndef NDEBUG
    /* Forward declarations to avoid including platform.hpp here */
    void plat_print_error(const char* s);
    void plat_abort();

    #define Z98_ASSERT(cond) do { \
        if (!(cond)) { \
            plat_print_error("Assertion failed: " #cond " at " __FILE__ ":" Z98_STRINGIFY(__LINE__) "\n"); \
            plat_abort(); \
        } \
    } while(0)
#else
    #define Z98_ASSERT(cond) ((void)0)
#endif

#endif // COMMON_HPP
