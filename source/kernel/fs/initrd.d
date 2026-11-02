module kernel.fs.initrd;

import kernel.core.debugging;

import pmm = kernel.core.pmm;
import vmm = kernel.core.vmm;

struct InitrdFile
{
    const(char)[] name;
    const(ubyte)[] data;
}

private enum MAX_FILES = 8;

private __gshared InitrdFile[MAX_FILES] initrdFiles;
private __gshared uint initrdFileCount = 0;

public void initrdInit(size_t physicalStart) @nogc nothrow
{
    if (physicalStart == 0)
    {
        debugPrintln("[initrd]: zero physical start address passed");
        return;
    }

    const(ubyte)* p = cast(const(ubyte)*) vmm.physToVirt(physicalStart);
    uint count = *cast(const(uint)*) p;
    p += 4;

    debugPrint("[initrd]: files: ");
    debugPrintUint(count);
    debugPrintln();

    for (uint i = 0; i < count && i < 8; i++)
    {
        uint nameLen = *cast(const(uint)*) p;  p += 4;
        const(char)[] name = (cast(const(char)*) p)[0 .. nameLen];
        p += nameLen;

        uint dataLen = *cast(const(uint)*) p;  p += 4;
        const(ubyte)[] data = p[0 .. dataLen];
        p += dataLen;

        initrdFiles[i] = InitrdFile(name, data);
        initrdFileCount = i + 1;

        debugPrint("[initrd]: ");
        debugPrint(name);
        debugPrint(" (");
        debugPrintUint(dataLen);
        debugPrintln(" bytes)");
    }
}

public const(InitrdFile)* findFile(scope const(char)[] name) @nogc nothrow
{
    foreach (i; 0 .. initrdFileCount)
        if (initrdFiles[i].name == name)
            return &initrdFiles[i];
    return null;
}
