desc: --massif-out-file=massif.out.lisp
cmd: ./zig0 examples/lisp_interpreter/main.zig -o o_lisp/main.c
time_unit: i
#-----------
snapshot=0
#-----------
time=0
mem_heap_B=0
mem_heap_extra_B=0
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=1
#-----------
time=1988242
mem_heap_B=73728
mem_heap_extra_B=8
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=2
#-----------
time=1990396
mem_heap_B=78936
mem_heap_extra_B=24
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=3
#-----------
time=2000619
mem_heap_B=1127512
mem_heap_extra_B=32
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=4
#-----------
time=2232569
mem_heap_B=2176088
mem_heap_extra_B=40
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=5
#-----------
time=4225234
mem_heap_B=2176088
mem_heap_extra_B=40
mem_stacks_B=0
heap_tree=detailed
n2: 2176088 (heap allocation functions) malloc/new/new[], --alloc-fns, etc.
 n2: 2102360 0x17365F: plat_alloc(unsigned long) (in /app/zig0)
  n1: 2097152 0x1754E3: ArenaAllocator::alloc_aligned(unsigned long, unsigned long) (in /app/zig0)
   n2: 2097152 0x17520F: ArenaAllocator::alloc(unsigned long) (in /app/zig0)
    n1: 1048576 0x1187A4: SymbolTable::enterScope() (in /app/zig0)
     n1: 1048576 0x118755: SymbolTable::SymbolTable(ArenaAllocator&) (in /app/zig0)
      n1: 1048576 0x13CF0A: CompilationUnit::CompilationUnit(ArenaAllocator&, StringInterner&) (in /app/zig0)
       n0: 1048576 0x174E28: main (in /app/zig0)
    n1: 1048576 0x17D11C: DynamicArray<TokenStream>::ensure_capacity(unsigned long) (in /app/zig0)
     n1: 1048576 0x178E94: DynamicArray<TokenStream>::append(TokenStream const&) (in /app/zig0)
      n1: 1048576 0x14280C: TokenSupplier::getTokensForFile(unsigned int) (in /app/zig0)
       n1: 1048576 0x13DA51: CompilationUnit::createParser(unsigned int) (in /app/zig0)
        n1: 1048576 0x140182: CompilationUnit::performFullPipeline(unsigned int) (in /app/zig0)
         n1: 1048576 0x174574: runCompilationPipeline(CompilationUnit&, unsigned int) (in /app/zig0)
          n0: 1048576 0x174F65: main (in /app/zig0)
  n0: 5208 in 1 place, below massif's threshold (1.00%)
 n1: 73728 0x491438E: ??? (in /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.33)
  n1: 73728 0x400571E: call_init.part.0 (dl-init.c:74)
   n1: 73728 0x4005823: call_init (dl-init.c:120)
    n1: 73728 0x4005823: _dl_init (dl-init.c:121)
     n1: 73728 0x401F59F: ??? (in /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2)
      n1: 73728 0x3: ???
       n1: 73728 0x1FFF00024A: ???
        n1: 73728 0x1FFF000251: ???
         n1: 73728 0x1FFF000274: ???
          n0: 73728 0x1FFF000277: ???
#-----------
snapshot=6
#-----------
time=4225234
mem_heap_B=1127512
mem_heap_extra_B=32
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=7
#-----------
time=4261181
mem_heap_B=1128291
mem_heap_extra_B=45
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=8
#-----------
time=4334750
mem_heap_B=2176867
mem_heap_extra_B=53
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=9
#-----------
time=4629394
mem_heap_B=2178499
mem_heap_extra_B=61
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=10
#-----------
time=5367739
mem_heap_B=2180666
mem_heap_extra_B=78
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=11
#-----------
time=6365531
mem_heap_B=2181861
mem_heap_extra_B=91
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=12
#-----------
time=6961033
mem_heap_B=2185377
mem_heap_extra_B=103
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=13
#-----------
time=8283513
mem_heap_B=2186219
mem_heap_extra_B=117
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=14
#-----------
time=8692275
mem_heap_B=2194173
mem_heap_extra_B=139
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=15
#-----------
time=11558368
mem_heap_B=2199080
mem_heap_extra_B=152
mem_stacks_B=0
heap_tree=detailed
n2: 2199080 (heap allocation functions) malloc/new/new[], --alloc-fns, etc.
 n2: 2125352 0x17365F: plat_alloc(unsigned long) (in /app/zig0)
  n1: 2097152 0x1754E3: ArenaAllocator::alloc_aligned(unsigned long, unsigned long) (in /app/zig0)
   n2: 2097152 0x17520F: ArenaAllocator::alloc(unsigned long) (in /app/zig0)
    n1: 1048576 0x1187A4: SymbolTable::enterScope() (in /app/zig0)
     n1: 1048576 0x118755: SymbolTable::SymbolTable(ArenaAllocator&) (in /app/zig0)
      n1: 1048576 0x13CF0A: CompilationUnit::CompilationUnit(ArenaAllocator&, StringInterner&) (in /app/zig0)
       n0: 1048576 0x174E28: main (in /app/zig0)
    n1: 1048576 0x17D11C: DynamicArray<TokenStream>::ensure_capacity(unsigned long) (in /app/zig0)
     n1: 1048576 0x178E94: DynamicArray<TokenStream>::append(TokenStream const&) (in /app/zig0)
      n1: 1048576 0x14280C: TokenSupplier::getTokensForFile(unsigned int) (in /app/zig0)
       n2: 1048576 0x13DA51: CompilationUnit::createParser(unsigned int) (in /app/zig0)
        n1: 1048576 0x142076: CompilationUnit::resolveImportsRecursive(Module*, DynamicArray<char const*>&) (in /app/zig0)
         n1: 1048576 0x141A01: CompilationUnit::resolveImports(Module*) (in /app/zig0)
          n1: 1048576 0x140304: CompilationUnit::performFullPipeline(unsigned int) (in /app/zig0)
           n1: 1048576 0x174574: runCompilationPipeline(CompilationUnit&, unsigned int) (in /app/zig0)
            n0: 1048576 0x174F65: main (in /app/zig0)
        n0: 0 in 1 place, below massif's threshold (1.00%)
  n2: 28200 0x173892: plat_file_read(char const*, char**, unsigned long*) (in /app/zig0)
   n1: 22992 0x141F1E: CompilationUnit::resolveImportsRecursive(Module*, DynamicArray<char const*>&) (in /app/zig0)
    n0: 22992 in 2 places, all below massif's threshold (1.00%)
   n0: 5208 in 1 place, below massif's threshold (1.00%)
 n1: 73728 0x491438E: ??? (in /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.33)
  n1: 73728 0x400571E: call_init.part.0 (dl-init.c:74)
   n1: 73728 0x4005823: call_init (dl-init.c:120)
    n1: 73728 0x4005823: _dl_init (dl-init.c:121)
     n1: 73728 0x401F59F: ??? (in /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2)
      n1: 73728 0x3: ???
       n1: 73728 0x1FFF00024A: ???
        n1: 73728 0x1FFF000251: ???
         n1: 73728 0x1FFF000274: ???
          n0: 73728 0x1FFF000277: ???
#-----------
snapshot=16
#-----------
time=31673051
mem_heap_B=3247656
mem_heap_extra_B=160
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=17
#-----------
time=61876381
mem_heap_B=4296232
mem_heap_extra_B=168
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=18
#-----------
time=66964061
mem_heap_B=5344808
mem_heap_extra_B=176
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=19
#-----------
time=75622482
mem_heap_B=6393384
mem_heap_extra_B=184
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=20
#-----------
time=82833685
mem_heap_B=6393384
mem_heap_extra_B=184
mem_stacks_B=0
heap_tree=peak
n2: 6393384 (heap allocation functions) malloc/new/new[], --alloc-fns, etc.
 n2: 6319656 0x17365F: plat_alloc(unsigned long) (in /app/zig0)
  n1: 6291456 0x1754E3: ArenaAllocator::alloc_aligned(unsigned long, unsigned long) (in /app/zig0)
   n4: 6291456 0x17520F: ArenaAllocator::alloc(unsigned long) (in /app/zig0)
    n2: 3145728 0x15FD88: C89Emitter::C89Emitter(CompilationUnit&, bool) (in /app/zig0)
     n1: 2097152 0x16F579: CBackend::generateSourceFile(Module*, char const*, DynamicArray<char const*>*) (in /app/zig0)
      n1: 2097152 0x16F354: CBackend::generate(char const*) (in /app/zig0)
       n1: 2097152 0x140127: CompilationUnit::generateCode(char const*) (in /app/zig0)
        n0: 2097152 0x174F97: main (in /app/zig0)
     n1: 1048576 0x170BB5: CBackend::generateHeaderFile(Module*, char const*, DynamicArray<char const*>*) (in /app/zig0)
      n1: 1048576 0x16F319: CBackend::generate(char const*) (in /app/zig0)
       n1: 1048576 0x140127: CompilationUnit::generateCode(char const*) (in /app/zig0)
        n0: 1048576 0x174F97: main (in /app/zig0)
    n1: 1048576 0x1187A4: SymbolTable::enterScope() (in /app/zig0)
     n1: 1048576 0x118755: SymbolTable::SymbolTable(ArenaAllocator&) (in /app/zig0)
      n1: 1048576 0x13CF0A: CompilationUnit::CompilationUnit(ArenaAllocator&, StringInterner&) (in /app/zig0)
       n0: 1048576 0x174E28: main (in /app/zig0)
    n1: 1048576 0x179E4A: DynamicArray<ASTNode*>::ensure_capacity(unsigned long) (in /app/zig0)
     n1: 1048576 0x179C2A: DynamicArray<ASTNode*>::insert(unsigned long, ASTNode* const&) (in /app/zig0)
      n1: 1048576 0x154F14: ControlFlowLifter::liftNode(ASTNode**, ASTNode*, char const*, bool) (in /app/zig0)
       n1: 1048576 0x14E8ED: ControlFlowLifter::transformNode(ASTNode**, ASTNode*) (in /app/zig0)
        n1: 1048576 0x14E043: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*)::TransformVisitor::visitChild(ASTNode**) (in /app/zig0)
         n1: 1048576 0x156C07: forEachChild(ASTNode*, ChildVisitor&) (in /app/zig0)
          n1: 1048576 0x14E0F1: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*) (in /app/zig0)
           n1: 1048576 0x14EC9D: ControlFlowLifter::transformNode(ASTNode**, ASTNode*) (in /app/zig0)
            n1: 1048576 0x14E043: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*)::TransformVisitor::visitChild(ASTNode**) (in /app/zig0)
             n1: 1048576 0x156792: forEachChild(ASTNode*, ChildVisitor&) (in /app/zig0)
              n1: 1048576 0x14E0F1: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*) (in /app/zig0)
               n1: 1048576 0x14EC9D: ControlFlowLifter::transformNode(ASTNode**, ASTNode*) (in /app/zig0)
                n1: 1048576 0x14E043: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*)::TransformVisitor::visitChild(ASTNode**) (in /app/zig0)
                 n1: 1048576 0x156309: forEachChild(ASTNode*, ChildVisitor&) (in /app/zig0)
                  n1: 1048576 0x14E0F1: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*) (in /app/zig0)
                   n1: 1048576 0x14EC9D: ControlFlowLifter::transformNode(ASTNode**, ASTNode*) (in /app/zig0)
                    n1: 1048576 0x14E043: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*)::TransformVisitor::visitChild(ASTNode**) (in /app/zig0)
                     n1: 1048576 0x156BD7: forEachChild(ASTNode*, ChildVisitor&) (in /app/zig0)
                      n1: 1048576 0x14E0F1: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*) (in /app/zig0)
                       n1: 1048576 0x14EA87: ControlFlowLifter::transformNode(ASTNode**, ASTNode*) (in /app/zig0)
                        n1: 1048576 0x14E043: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*)::TransformVisitor::visitChild(ASTNode**) (in /app/zig0)
                         n1: 1048576 0x1568D2: forEachChild(ASTNode*, ChildVisitor&) (in /app/zig0)
                          n1: 1048576 0x14E0F1: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*) (in /app/zig0)
                           n1: 1048576 0x14EB1F: ControlFlowLifter::transformNode(ASTNode**, ASTNode*) (in /app/zig0)
                            n1: 1048576 0x14E043: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*)::TransformVisitor::visitChild(ASTNode**) (in /app/zig0)
                             n1: 1048576 0x1571F8: forEachChild(ASTNode*, ChildVisitor&) (in /app/zig0)
                              n0: 1048576 0x14E0F1: ControlFlowLifter::transformNode(ASTNode**, ASTNode*)::Inner::process(ControlFlowLifter*, ASTNode*) (in /app/zig0)
    n1: 1048576 0x17D11C: DynamicArray<TokenStream>::ensure_capacity(unsigned long) (in /app/zig0)
     n1: 1048576 0x178E94: DynamicArray<TokenStream>::append(TokenStream const&) (in /app/zig0)
      n1: 1048576 0x14280C: TokenSupplier::getTokensForFile(unsigned int) (in /app/zig0)
       n2: 1048576 0x13DA51: CompilationUnit::createParser(unsigned int) (in /app/zig0)
        n1: 1048576 0x142076: CompilationUnit::resolveImportsRecursive(Module*, DynamicArray<char const*>&) (in /app/zig0)
         n1: 1048576 0x141A01: CompilationUnit::resolveImports(Module*) (in /app/zig0)
          n1: 1048576 0x140304: CompilationUnit::performFullPipeline(unsigned int) (in /app/zig0)
           n1: 1048576 0x174574: runCompilationPipeline(CompilationUnit&, unsigned int) (in /app/zig0)
            n0: 1048576 0x174F65: main (in /app/zig0)
        n0: 0 in 1 place, below massif's threshold (1.00%)
  n0: 28200 in 1 place, below massif's threshold (1.00%)
 n1: 73728 0x491438E: ??? (in /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.33)
  n1: 73728 0x400571E: call_init.part.0 (dl-init.c:74)
   n1: 73728 0x4005823: call_init (dl-init.c:120)
    n1: 73728 0x4005823: _dl_init (dl-init.c:121)
     n1: 73728 0x401F59F: ??? (in /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2)
      n1: 73728 0x3: ???
       n1: 73728 0x1FFF00024A: ???
        n1: 73728 0x1FFF000251: ???
         n1: 73728 0x1FFF000274: ???
          n0: 73728 0x1FFF000277: ???
#-----------
snapshot=21
#-----------
time=82833685
mem_heap_B=6388176
mem_heap_extra_B=168
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=22
#-----------
time=82833766
mem_heap_B=5339600
mem_heap_extra_B=160
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=23
#-----------
time=82833852
mem_heap_B=4291024
mem_heap_extra_B=152
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=24
#-----------
time=82833901
mem_heap_B=3242448
mem_heap_extra_B=144
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=25
#-----------
time=82833950
mem_heap_B=2193872
mem_heap_extra_B=136
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=26
#-----------
time=82833999
mem_heap_B=1145296
mem_heap_extra_B=128
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=27
#-----------
time=82834048
mem_heap_B=96720
mem_heap_extra_B=120
mem_stacks_B=0
heap_tree=empty
#-----------
snapshot=28
#-----------
time=82847144
mem_heap_B=22992
mem_heap_extra_B=112
mem_stacks_B=0
heap_tree=empty
