module kernel.elf;

import kernel.core.debugging;

enum ElfType : ushort
{
    None = 0,
    Relocatable = 1,
    Executable = 2,
    Shared = 3,
    Core = 4,
}

enum ElfMachine : ushort
{
    /// Not defined
    None = 0,
    /// Intel 80386
    I386 = 3,
    /// Intel 80860
    I860 = 7,
    /// MIPS
    MIPS = 8,
    /// Intel 80960
    I960 = 19,
    /// ARM (up to ARMv7/Aarch32)
    ARM = 40,
    /// Intel Architecture 64
    IA64 = 50,
    /// AMD x86-64
    AMD64 = 62,
    /// ARM 64-bits (ARMv8/Aarch64)
    AARCH64 = 183,
    /// RISC-V
    RISCV = 243
}

struct Elf32Ehdr
{
    /** 
     * File identifier:
     * - 0-3: EI_MAG_0 - EI_MAG_3: '~', 'E', 'L', 'F'
     * - 4: EI_CLASS (1 = ELF32, 2 = ELF64)
     * - 5: EI_DATA (0 = invalid, 1 = little endian, 2 = big endian)
     * - 6: EI_VERSION (always 1)
     * - 7: EI_OSABI (0 for System V)
     * - 8: EI_ABIVERSION
     * - 9-15: Padding bytes, must be ignored
     */
    char[16] ident;
    ElfType type;
    ElfMachine machine;
    /// Version: only 1 is valid currently
    uint version_;
    /// Virtual address of entry point; 0 if none entry point is present
    uint entry;
    /// The offset of the program header table from the beginning of the file in bytes, may be 0 if table not present
    uint phooff;
    /// The offset of the section header table from the beginning of the file in bytes, may be 0 if table not present
    uint shooff;
    // TODO: enum for ELF flags 
    uint flags;
    /// ELF Header size (52 for 32-bit and 64 for 64-bit)
    ushort ehsize;
    /// Size of an entry in the program header table (32 for 32-bit and 56 for 64-bit)
    ushort phentsize;
    /// Number of entries in the program header table, may be 0 if table not present
    ushort phnum;
    /// Size of an entry in the section header table (40 for 32-bit and 64 for 64-bit)
    ushort shentsize;
    /// Number of entries in the section header table, may be 0 if table not present
    ushort shnum;
    /// Section index to the section header string table, may be 0 if table not present
    ushort shstrndx;
}

// static assert(Elf64Ehdr.sizeof == 64, "ELF Header structure must be exactly 64 bytes for 64-bit");
static assert(Elf32Ehdr.sizeof == 52, "ELF Header structure must be exactly 52 bytes for 32-bit");

enum ElfPhdrType : uint
{
    Null = 0,
    Load = 1,
    Dynamic = 2,
    Interp = 3,
    Note = 4,
    Shlib = 5,
    Phdr = 6,
    Tls = 7,
}

struct Elf32Phdr
{
    uint type;
    uint offset;
    uint vaddr;
    uint paddr;
    uint filesz;
    uint memsz;
    uint flags;
    uint align_;
}

enum ElfShdrType : uint
{
    Null = 0,
    /// Program-defined bits
    Progbits = 1,
    /// Symbol Table (only one)
    Symtab = 2,
    /// String table
    Strtab = 3,
    /// Relocation Table with Append
    Rela = 4,
    /// Symbol Hash Table (only one)
    Hash = 5,
    /// Dynamic linking info (only one)
    Dynamic = 6,
    /// Note Section
    Note = 7,
    /// No Bits in File
    Nobits = 8,
    /// Relocation without Append
    Rel = 9,
    /// Reserved, must not be used
    Shlib = 10,
    /// Dynamic Symbol Table
    Dynsym = 11,
    /// Array of initialization functions
    InitArray = 14,
    /// Array of termination functions
    FiniArray = 15,
    /// Array of pre-initialization functions
    PreinitArray = 16,
    /// Section Group
    Group = 17,
    /// Extended Sections Indices
    SymtabShndx = 18,
}

enum Elf32ShdrFlags : uint
{
    Write           = 1 << 0,
    Alloc           = 1 << 1,
    Exec            = 1 << 2,
    Merge           = 1 << 3,
    Strings         = 1 << 4,
    InfoLink        = 1 << 5,
    LinkOrder       = 1 << 6,
    OsNonConforming = 1 << 7,
    Group           = 1 << 8,
    Tls             = 1 << 9,
    Compressed      = 1 << 10,
}

struct Elf32Shdr
{
    uint name;
    ElfShdrType type;
    Elf32ShdrFlags flags;
    uint addr;
    uint offset;
    uint size;
    uint link;
    uint info;
    uint addralign;
    uint entsize;
}

public void readElf(ubyte* data) nothrow @nogc
{
    Elf32Ehdr* ehdr = cast(Elf32Ehdr*)data;
    
    if (ehdr.ident[0..3] != "~ELF")
    {
        debugPrintln("No ELF magic identificator");
        return;
    }

    if (ehdr.ident[4] != 1)
    {
        debugPrintln("Only 32-bit ELF is supported");
        return;
    }

    if (ehdr.ident[5] != 2)
    {
        debugPrintln("Only big-endian ELF is supported");
        return;
    }

    if (ehdr.ident[6] != 1)
    {
        debugPrintln("ELF version always must be 1");
        return;
    }

    if (ehdr.ident[7] != 0)
    {
        debugPrintln("Only 0 OS ABI for ELF is supported");
    }

    // TODO: you stopped right here
}
