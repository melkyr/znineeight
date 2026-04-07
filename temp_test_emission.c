unsigned int zF_0_sum_up_to(unsigned int n) {
    unsigned int i = 0;
    unsigned int total = 0;
    __loop_0_start: ;
    if (!(i < n)) goto __loop_0_end;
    {
        (void)(total += i);
    }
    (void)(i += 1);
    goto __loop_0_start;
    __loop_0_end: ;
    return total;
}
