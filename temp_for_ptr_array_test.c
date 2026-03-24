static void foo(int (* ptr)[5]) {
    {
        int (* __for_iter_1)[5] = ptr;
        size_t __for_idx_1 = 0;
        size_t __for_len_1 = 5;
        __loop_0_start: ;
        while (__for_idx_1 < __for_len_1) {
{
                (void)(item);
            }
            __loop_0_continue: ;
            __for_idx_1++;
            goto __loop_0_start;
        }
        __loop_0_end: ;
    }
}
