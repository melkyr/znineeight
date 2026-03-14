static void foo(void) {
    int i;
    i = 0;
    __loop_0_start: ;
    if (!(i < 10)) goto __loop_0_end;
    {
        if (i == 5) {
            /* defers for continue */
            {
                cleanup();
            }
            goto __loop_0_continue;
        }
        {
            cleanup();
        }
    }
    __loop_0_continue: ;
    (void)(i += 1);
    goto __loop_0_start;
    __loop_0_end: ;
}
