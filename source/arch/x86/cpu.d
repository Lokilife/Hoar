module arch.x86.cpu;

pragma(inline, true)
public void ia32_hlt() @nogc nothrow
{
    asm @nogc nothrow { "hlt"; }
}

pragma(inline, true)
public void ia32_cli() @nogc nothrow
{
    asm @nogc nothrow { "cli"; }
}

pragma(inline, true)
public void ia32_sti() @nogc nothrow
{
    asm @nogc nothrow { "sti"; }
}

pragma(inline, true)
public size_t ia32_save_if() @nogc nothrow
{
    size_t savedFlags;
    asm @nogc nothrow {
        "pushfl; popl %0"
        : "=r" (savedFlags)
        :
        : "memory";
    }
    return savedFlags;
}

pragma(inline, true)
public void ia32_restore_if(size_t flags) @nogc nothrow
{
    asm @nogc nothrow {
        "pushl %0; popfl"
        :
        : "r" (flags)
        : "memory", "cc";
    }
}

pragma(inline, true)
public void ia32_outb(ushort port, ubyte value) @nogc nothrow
{
    asm @nogc nothrow {
        "outb %1, %0"
        :
        : "dN" (port), "a" (value)
        : "memory";
    }
}

pragma(inline, true)
public ubyte ia32_inb(ushort port) @nogc nothrow
{
    ubyte value;
    asm @nogc nothrow {
        "inb %1, %0"
        : "=a" (value)
        : "dN" (port)
        : "memory";
    }
    return value;
}

private string hexByte(ubyte v) pure @safe @nogc nothrow
{
    enum digits = "0123456789abcdef";
    return "0x"
         ~ digits[(v >> 4) .. (v >> 4) + 1]
         ~ digits[(v & 0xF) .. (v & 0xF) + 1];
}

pragma(inline, true)
public void ia32_int(ubyte intNo)(int eax, int ebx = 0, int ecx = 0, int edx = 0) @nogc nothrow
{
    enum asmInstruction = "int $" ~ hexByte(intNo);

    asm @nogc nothrow {
        (asmInstruction)
        :
        : "a" (eax), "b" (ebx), "c" (ecx), "d" (edx)
        : "memory";
    }
}

public struct IdtRegister
{
    align(1):
    ushort  limit;
    void*   base; // may be a size_t but used void* to describe all IDT in compile-time
}

// IDT Entry
//  64                    57    56                    49    48                    41    40                    33    32                    25    24                    17    16                     9    8                     1
//  0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0
// | --- offset high                                 ---|  |P||DPL| |0|  |-gate type-| | --- zero            --- | | --- segment selector                            --- | | --- offset low                                 --- |

public struct IdtEntry32
{
    align(1):
    ushort offset_low;
    ushort segment;
    ubyte  zero; // unused, set to 0
    ubyte  attributes;
    ushort offset_high;
}

static assert(IdtRegister.sizeof == 2 + size_t.sizeof,
    "IdtRegister must be 2-byte limit followed by a native-size base");
static assert(IdtEntry32.sizeof == 8, "IdtEntry32 must be exactly 8 bytes");

public enum IdtEntryAttributes
{
    // Gate type (bits 3–0)
    TaskGate        = 0b0000_0101,  // 0x05 // Task Gate switches current task context to the specified segment, handler is ignored
    InterruptGate16 = 0b0000_0110,  // 0x06
    TrapGate16      = 0b0000_0111,  // 0x07
    InterruptGate32 = 0b0000_1110,  // 0x0E // Interrupt Gate   does resets IF what means maskable interrupts WILL be disabled
    TrapGate32      = 0b0000_1111,  // 0x0F // Trap Gate        does NOT resets IF what means maskable interrupts WONT be disabled

    // DPL (bits 6–5)
    Ring0           = 0b0000_0000,  // 0x00
    Ring1           = 0b0010_0000,  // 0x20
    Ring2           = 0b0100_0000,  // 0x40
    Ring3           = 0b0110_0000,  // 0x60

    // Present (bit 7)
    Present         = 0b1000_0000,  // 0x80
}

pragma(inline, true)
public pure IdtEntry32 ia32_make_idt_entry(uint handler, ubyte attributes, ushort segment = 0x08) nothrow @nogc
{
    IdtEntry32 entry;

    entry.offset_low    = cast(ushort)(handler & 0xFFFF);
    entry.offset_high   = cast(ushort)((handler >> 16) & 0xFFFF);
    entry.segment       = segment;
    entry.zero          = 0;
    entry.attributes    = attributes;

    return entry;
}

pragma(inline, true)
public void ia32_load_idt(const(IdtRegister)* gdt) @nogc nothrow
{
    asm @nogc nothrow {
        "lidt %0" 
        :
        : "m" (*gdt)
        : "memory";
    }
}

private @nogc @safe pure nothrow
{
    uint bfGet(uint word, uint pos, uint width)
    {
        return (word >> pos) & ((1u << width) - 1u);
    }

    uint bfSet(uint word, uint pos, uint width, uint v)
    {
        const mask = ((1u << width) - 1u) << pos;
        return (word & ~mask) | ((v << pos) & mask);
    }

    bool bitGet(uint word, uint pos)
    {
        return ((word >> pos) & 1u) != 0;
    }

    uint bitSet(uint word, uint pos, bool v)
    {
        return v ? (word | (1u << pos)) : (word & ~(1u << pos));
    }
}

// flag bit positions
enum P_BIT_PRESENT   = 0;
enum P_BIT_RW        = 1;
enum P_BIT_USER      = 2;
enum P_BIT_PWT       = 3;
enum P_BIT_PCD       = 4;
enum P_BIT_ACCESSED  = 5;
enum P_BIT_DIRTY     = 6;
enum P_BIT_PAGE_SIZE = 7;   // PDE only : 1 = 4 MiB page
enum P_BIT_GLOBAL    = 8;
enum P_BIT_PAT       = 12;  // PTE only

// low-bit masks
enum PDE4K_FLAGS_MASK = 0x00000FFFu;
enum PDE4M_FLAGS_MASK = 0x003FFFFFu;
enum PTE_FLAGS_MASK   = 0x00000FFFu;

// flag accessors shared by Pde and Pte
private mixin template PageFlags(T)
{
    @nogc @safe pure nothrow bool present () const { return bitGet(raw, P_BIT_PRESENT); }
    @nogc @safe pure nothrow T    present (bool v) const { return T(bitSet(raw, P_BIT_PRESENT, v)); }

    @nogc @safe pure nothrow bool rw() const { return bitGet(raw, P_BIT_RW); }
    @nogc @safe pure nothrow T    rw(bool v) const { return T(bitSet(raw, P_BIT_RW, v)); }

    @nogc @safe pure nothrow bool user() const { return bitGet(raw, P_BIT_USER); }
    @nogc @safe pure nothrow T    user(bool v) const { return T(bitSet(raw, P_BIT_USER, v)); }

    @nogc @safe pure nothrow bool pwt() const { return bitGet(raw, P_BIT_PWT); }
    @nogc @safe pure nothrow T    pwt(bool v) const { return T(bitSet(raw, P_BIT_PWT, v)); }

    @nogc @safe pure nothrow bool pcd() const { return bitGet(raw, P_BIT_PCD); }
    @nogc @safe pure nothrow T    pcd(bool v) const { return T(bitSet(raw, P_BIT_PCD, v)); }

    @nogc @safe pure nothrow bool accessed() const { return bitGet(raw, P_BIT_ACCESSED); }
    @nogc @safe pure nothrow T    accessed(bool v) const { return T(bitSet(raw, P_BIT_ACCESSED, v)); }

    @nogc @safe pure nothrow bool dirty() const { return bitGet(raw, P_BIT_DIRTY); }
    @nogc @safe pure nothrow T    dirty(bool v) const { return T(bitSet(raw, P_BIT_DIRTY, v)); }

    @nogc @safe pure nothrow bool global() const { return bitGet(raw, P_BIT_GLOBAL); }
    @nogc @safe pure nothrow T    global(bool v) const { return T(bitSet(raw, P_BIT_GLOBAL, v)); }
}

/// PDE - page-directory entry
struct Pde
{
    uint raw;

    mixin PageFlags!Pde;

    @nogc @safe pure nothrow:

    // 4 KiB interpretation: phys address of a page table
    uint pageTable() const { return raw & 0xFFFFF000u; }
    Pde  pageTable(uint phys) const
    {
        return Pde((raw & 0x00000FFFu) | ((phys >> 12) << 12));
    }

    // 4 MiB interpretation
    bool isPageSize4M()      const { return bitGet(raw, P_BIT_PAGE_SIZE); }
    Pde  pageSize4M(bool v)  const { return Pde(bitSet(raw, P_BIT_PAGE_SIZE, v)); }
    Pde  pat(bool v)         const { return Pde(bitSet(raw, P_BIT_PAT, v)); }

    uint page4M() const { return raw & 0xFFC00000u; }
    Pde  page4M(uint phys) const
    {
        return Pde((raw & 0x003FFFFFu) | ((phys >> 22) << 22));
    }

    Pde withFlags(uint flags, uint mask) const
    {
        return Pde((raw & ~mask) | (flags & mask));
    }
}

static assert(Pde.sizeof == 4);

/// PTE - page-table entry
struct Pte
{
    uint raw;

    mixin PageFlags!Pte;

    @nogc @safe pure nothrow:

    Pte pat(bool v) const { return Pte(bitSet(raw, P_BIT_PAT, v)); }

    uint page() const { return raw & 0xFFFFF000u; }
    Pte  page(uint phys) const
    {
        return Pte((raw & 0x00000FFFu) | ((phys >> 12) << 12));
    }

    Pte withFlags(uint flags, uint mask) const
    {
        return Pte((raw & ~mask) | (flags & mask));
    }
}

static assert(Pte.sizeof == 4);

pragma(inline, true)
public void ia32_load_cr3(size_t value) nothrow @nogc
{
    asm nothrow @nogc {
        "mov %0, %%cr3"
        :
        : "r"(value);
    }
}

pragma(inline, true)
public size_t ia32_read_cr2() @nogc nothrow
{
    size_t v;
    asm @nogc nothrow {
        "mov %%cr2, %0"
        : "=r" (v);
    }
    return v;
}

pragma(inline, true)
public void ia32_enable_paging() nothrow @nogc
{
    uint cr0;
    asm nothrow @nogc {
        "mov %%cr0, %0"
        :"=r"(cr0);
    }
    cr0 |= 0x80000000; // PG (paging) bit
    // cr0 |= 0x00010000; // maybe? WP (write protect) to catch kernel if it will write to read-only

    asm nothrow @nogc {
        "mov %0, %%cr0"
        :
        : "r"(cr0);
    }
}

pragma(inline, true)
public void ia32_invlpg(size_t virt) @nogc nothrow
{
    asm @nogc nothrow {
        "invlpg (%0)"
        :
        : "r" (virt)
        : "memory";
    }
}


public struct TssSegment
{
    align(1):
    ushort  previousTaskLink; // Selector of the previous task (for nested tasks)
    ushort  reserved_1;
    uint    esp0;           // Stack pointer for DPL 0
    ushort  ss0;            // Stack segment for DPL 0
    ushort  reserved_2;
    uint    esp1;           // Stack pointer for DPL 1
    ushort  ss1;            // Stack segment for DPL 1
    ushort  reserved_3;
    uint    esp2;           // Stack pointer for DPL 2
    ushort  ss2;            // Stack segment for DPL 2
    ushort  reserved_4;
    uint    cr3;
    uint    eip;
    uint    eflags;
    uint    eax, ecx, edx, ebx;
    uint    esp, ebp, esi, edi;
    ushort  es;
    ushort  reserved_5;
    ushort  cs;
    ushort  reserved_6;
    ushort  ss;
    ushort  reserved_7;
    ushort  ds;
    ushort  reserved_8;
    ushort  fs;
    ushort  reserved_9;
    ushort  gs;
    ushort  reserved_10;
    ushort  ldtSegmentSelector;
    ushort  reserved_11;
    ushort  reserved_12;
    ushort  ioMapBaseAddress;   // Base address of the I/O permission bitmap
    uint    shadowStackPointer;
}
