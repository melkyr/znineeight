unsigned int zF_0_sum_up_to(unsigned int n) {
    unsigned int i;
    unsigned int total;
    i = 0;
    total = 0;
    __loop_0_start: ;
    if (!(i < n)) goto __loop_0_end;
    {
        total += i;
    }
    __loop_0_continue: ;
    (void)(i += 1);
    goto __loop_0_start;
    __loop_0_end: ;
    return total;
}
