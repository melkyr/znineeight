#include <windows.h>
#include <stdio.h>

typedef int (__stdcall *Z98_CB)(unsigned int);
typedef int (__stdcall *Z98_CB2)(unsigned int, unsigned int);

int __stdcall cb(unsigned int x);
int __stdcall cb2(unsigned int x, unsigned int y);

int main(void) {
    HANDLE h;
    DWORD tid = 0;
    DWORD code = 0;
    volatile Z98_CB p = cb;
    volatile Z98_CB2 p2 = cb2;
    unsigned int before = 0;
    unsigned int after = 0;
    int r1 = 0;
    int r2 = 0;

    h = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)cb, (LPVOID)41u, 0, &tid);
    if (h == NULL) {
        printf("CreateThread failed\n");
        return 1;
    }
    WaitForSingleObject(h, INFINITE);
    GetExitCodeThread(h, &code);
    CloseHandle(h);

    __asm__ __volatile__ ("movl %%esp, %0" : "=r"(before));
    r1 = p(41u);
    __asm__ __volatile__ ("movl %%esp, %0" : "=r"(after));
    r2 = p2(20u, 22u);

    printf("thread_exit=%lu direct=%d cb2=%d esp_delta=%d\n",
           (unsigned long)code, r1, r2, (int)(before - after));
    if (code != 42u || r1 != 42 || r2 != 42 || before != after) return 2;
    printf("stdcall callback ok\n");
    return 0;
}
