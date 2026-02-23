void foo(void) {
    {
        size_t __for_idx_1 = 0;
        size_t __for_len_1 = 10;
        __zig_label_outer_0_start: ;
        while (__for_idx_1 < __for_len_1) {
            unsigned int item = __for_idx_1;
{
                /* defers for break */
                goto __zig_label_outer_0_end;
            }
            __for_idx_1++;
            goto __zig_label_outer_0_start;
        }
        __zig_label_outer_0_end: ;
    }
}
