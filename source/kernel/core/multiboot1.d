module kernel.core.multiboot1;

import kernel.core.debugging;
import kernel.core.init;
import arch.cpu;

import pmm = kernel.core.pmm;
import vmm = kernel.core.vmm;

extern (C) void ia32_early_kernel_init() @nogc nothrow;

extern(C) void multiboot1Entry() @nogc nothrow
{
    disableInterrupts();

    uint magic = *cast(uint*)0xC0007000;
    uint mb_info_ptr  = *cast(uint*)0xC0007004;

    if (magic != MULTIBOOT_BOOTLOADER_MAGIC)
    {
        debugPrintln("multiboot1 boot failed\nError: invalid magic number passed\nKernel halted");
        waitForInterrupt();
        return;
    }

    MultibootInfo* info = cast(MultibootInfo*)mb_info_ptr;

    // pmm.MmapEntry is identical to the multiboot1 mmap so simply cast it and pack into a D slice
    pmm.MmapEntry* mmapEntires = cast(pmm.MmapEntry*)info.mmapAddr;
    size_t mmapCount = info.mmapLength / MultibootMmapEntry.sizeof;
    pmm.MmapEntry[] mmapSlice = mmapEntires[0 .. mmapCount];

    size_t highestPhys = cast(size_t)info.memUpper * 1024 + 0x100000;

    KernelInitOptions opts = KernelInitOptions(highestPhys, mmapSlice, 0, 0);
    
    debug {
        assert(mb_info_ptr < 4 * 1024 * 1024, "Multiboot info above 4 MB");
        assert(info.mmapAddr < 4 * 1024 * 1024, "Mmap above 4 MB");
    }

    if ((info.flags & MULTIBOOT_INFO_MODS) == MULTIBOOT_INFO_MODS && info.modsCount > 0)
    {
        uint modsAddr = vmm.physToVirt(info.modsAddr);

        MultibootModList[] modList = (cast(MultibootModList*)modsAddr)[0 .. info.modsCount];

        opts.initrdAddrStart = modList[0].mod_start;
        opts.initrdAddrEnd = modList[0].mod_end;
    }

    ia32_early_kernel_init();

    kernelInit(opts);
}

// The code below is a modification for D of https://www.gnu.org/software/grub/manual/multiboot/html_node/multiboot_002eh.html
/* Copyright (C) 1999,2003,2007,2008,2009,2010  Free Software Foundation, Inc.
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 *  sell copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL ANY
 *  DEVELOPER OR DISTRIBUTOR BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
 *  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/// How many bytes from the start of the file we search for the header.
enum MULTIBOOT_SEARCH = 8192;
enum MULTIBOOT_HEADER_ALIGN = 4;

/// The magic field should contain this.
enum MULTIBOOT_HEADER_MAGIC = 0x1BADB002;

/// This should be in %eax.
enum MULTIBOOT_BOOTLOADER_MAGIC = 0x2BADB002;

/// Alignment of multiboot modules.
enum MULTIBOOT_MOD_ALIGN = 0x00001000;
/// Alignment of the multiboot info structure.
enum MULTIBOOT_INFO_ALIGN = 0x00000004;

/// Flags set in the 'flags' member of the multiboot header.

/// Align all boot modules on i386 page (4KB) boundaries.
enum MULTIBOOT_PAGE_ALIGN = 0x00000001;

/// Must pass memory information to OS.
enum MULTIBOOT_MEMORY_INFO = 0x00000002;

/// Must pass video information to OS.
enum MULTIBOOT_VIDEO_MODE = 0x00000004;

/// This flag indicates the use of the address fields in the header.
enum MULTIBOOT_AOUT_KLUDGE = 0x00010000;

// Flags to be set in the 'flags' member of the multiboot info structure.

/// is there basic lower/upper memory information?
enum MULTIBOOT_INFO_MEMORY = 0x00000001;
/// is there a boot device set?
enum MULTIBOOT_INFO_BOOTDEV = 0x00000002;
/// is the command-line defined?
enum MULTIBOOT_INFO_CMDLINE = 0x00000004;
/// are there modules to do something with?
enum MULTIBOOT_INFO_MODS = 0x00000008;

// These next two are mutually exclusive

/// is there a symbol table loaded?
enum MULTIBOOT_INFO_AOUT_SYMS = 0x00000010;
/// is there an ELF section header table?
enum MULTIBOOT_INFO_ELF_SHDR = 0x00000020;

/// is there a full memory map?
enum MULTIBOOT_INFO_MEM_MAP = 0x00000040;
/// Is there drive info?
enum MULTIBOOT_INFO_DRIVE_INFO = 0x00000080;

/// Is there a config table?
enum MULTIBOOT_INFO_CONFIG_TABLE = 0x00000100;

/// Is there a boot loader name?
enum MULTIBOOT_INFO_BOOT_LOADER_NAME = 0x00000200;

/// Is there a APM table?
enum MULTIBOOT_INFO_APM_TABLE = 0x00000400;

/// Is there video information?
enum MULTIBOOT_INFO_VBE_INFO = 0x00000800;
enum MULTIBOOT_INFO_FRAMEBUFFER_INFO = 0x00001000;

struct MultibootHeader
{
    /// Must be MULTIBOOT_MAGIC - see above.
    uint magic;
    /// Feature flags.
    uint flags;

    /// The above fields plus this one must equal 0 mod 2^32.
    uint checksum;

    // These are only valid if MULTIBOOT_AOUT_KLUDGE is set.
    uint headerAddr;
    uint loadAddr;
    uint loadEndAddr;
    uint bssEndAddr;
    uint entryAddr;

    // These are only valid if MULTIBOOT_VIDEO_MODE is set.
    uint modeType;
    uint width;
    uint height;
    uint depth;
}

/// The symbol table for a.out.
struct MultibootAoutSymbolTable
{
    uint tabsize;
    uint strsize;
    uint addr;
    uint reserved;
}

/// The section header table for ELF.
struct MultibootElfSectionHeaderTable
{
    uint num;
    uint size;
    uint addr;
    uint shndx;
}

struct MultibootInfo
{
    /// Multiboot info version number
    uint flags;

    /// Available memory from BIOS
    uint memLower;
    uint memUpper;

    /// "root" partition
    uint bootDevice;

    /// Kernel command line
    uint cmdline;

    /// Boot-Module list
    uint modsCount;
    uint modsAddr;

    union
    {
        MultibootAoutSymbolTable aoutSym;
        MultibootElfSectionHeaderTable elfSec;
    }

    /// Memory Mapping buffer
    uint mmapLength;
    uint mmapAddr;

    /// Drive Info buffer
    uint drivesLength;
    uint drivesAddr;

    /// ROM configuration table
    uint configTable;

    /// Boot Loader Name
    uint bootLoaderName;

    /// APM table
    uint apmTable;

    /// Video
    uint vbeControlInfo;
    uint vbeModeInfo;
    ushort vbeMode;
    ushort vbeInterfaceSeg;
    ushort vbeInterfaceOff;
    ushort vbeInterfaceLen;

    long framebufferAddr;
    uint framebufferPitch;
    uint framebufferWidth;
    uint framebufferHeight;
    ubyte framebufferBpp;
    enum MULTIBOOT_FRAMEBUFFER_TYPE_INDEXED = 0;
    enum MULTIBOOT_FRAMEBUFFER_TYPE_RGB = 1;
    enum MULTIBOOT_FRAMEBUFFER_TYPE_EGA_TEXT = 2;
    ubyte framebufferType;

    union
    {
        struct
        {
            uint framebufferPaletteAddr;
            ushort framebufferPaletteNumColors;
        }
        struct
        {
            ubyte framebufferRedFieldPosition;
            ubyte framebufferRedMaskSize;
            ubyte framebufferGreenFieldPosition;
            ubyte framebufferGreenMaskSize;
            ubyte framebufferBlueFieldPosition;
            ubyte framebufferBlueMaskSize;
        }
    }
}

struct MultibootColor
{
    ubyte red;
    ubyte green;
    ubyte blue;
}

struct MultibootMmapEntry
{
    uint size;
    long addr;
    long len;
    enum AVAILABLE = 1;
    enum RESERVED = 2;
    enum ACPI_RECLAIMABLE = 3;
    enum NVS = 4;
    enum BADRAM = 5;
    uint type;
}

struct MultibootModList
{
    // the memory used goes from bytes 'mod_start' to 'mod_end-1' inclusive
    uint mod_start;
    uint mod_end;

    /// Module command line
    uint cmdline;

    /// padding to take it to 16 bytes (must be zero)
    uint pad;
}

/// APM BIOS info.
struct MultibootApmInfo
{
    /// version
    ushort ver;
    ushort cseg;
    uint offset;
    ushort cseg_16;
    ushort dseg;
    ushort flags;
    ushort cseg_len;
    ushort cseg_16_len;
    ushort dseg_len;
}
