fn fallible() !i32 { return 10; }
fn caller() !i32 {
    const x = try fallible();
    return x + 5;
}
