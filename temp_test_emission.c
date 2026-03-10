unsigned int sum_up_to(unsigned int n) {
    unsigned int i;
    unsigned int total;
    i = 0;
    total = 0;
    __zig_label_unnamed_0_start: ;
    if (!(i < n)) goto __zig_label_unnamed_0_end;
    {
        total += i;
    }
    __zig_label_unnamed_0_continue: ;
    (void)(i += 1);
    goto __zig_label_unnamed_0_start;
    __zig_label_unnamed_0_end: ;
    return total;
}
