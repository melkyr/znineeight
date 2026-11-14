// types module for lirrepro_global_reloc_xmod_xmod (R-3): the cross-module
// storage global under test. `g` is the single storage cell; bumpAndGet()
// mutates it (a `.call` ORDERED writer); read() snapshots it for the importer.
pub var g: i32 = 0;

pub fn bumpAndGet() i32 {
    g = g + 1;
    return g;
}

pub fn read() i32 {
    return g;
}
