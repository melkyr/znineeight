#ifndef PLATFORM_WIN98_H
#define PLATFORM_WIN98_H

#ifdef _WIN32

/* Force Windows 98 API level (0x0410) */
#ifndef _WIN32_WINDOWS
#define _WIN32_WINDOWS 0x0410
#endif
#ifndef WINVER
#define WINVER 0x0410
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0400   /* Win95/98 base */
#endif
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x04000000
#endif

/* Reduce header bloat */
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

/* Avoid bringing in the Unicode layer unless explicitly linked with unicows.lib */
#ifndef _UNICODE
#define _MBCS
#endif

#endif /* _WIN32 */

#endif /* PLATFORM_WIN98_H */
