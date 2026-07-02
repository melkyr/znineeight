extern fn extFn() ?*u32;

pub fn get() ?*u32 {
    return extFn();
}
