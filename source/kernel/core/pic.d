module kernel.core.pic;

import arch.cpu;
import arch.x86.cpu;
import kernel.core.debugging;
import kernel.core.pit;

import idt = kernel.core.idt;

pragma(inline, true) // I love inlining and CTFE
public pure bool irqIsSlave(uint irq) nothrow @nogc
{
    return irq >= 8;
}

// 8259A chip driver

/// IO base address for master PIC
enum PIC1 = 0x20;
enum PIC1_COMMAND = PIC1;
enum PIC1_DATA = PIC1+1;

/// IO base address for slave PIC
enum PIC2 = 0xA0;
enum PIC2_COMMAND = PIC2;
enum PIC2_DATA = PIC2+1;

// End-of-interrupt command
enum PIC_EOI = 0x20;

/// Indicates that ICW4 will be present
enum ICW1_ICW4 = 0x01;
/// Single (cascade) mode
enum ICW1_SINGLE = 0x02;
/// Call address interval 4 (8)
enum ICW1_INTERVAL4 = 0x04;
/// Level triggered (edge) mode
enum ICW1_LEVEL = 0x08;
/// Initialization - required!
enum ICW1_INIT = 0x10;

/// 8086/88 (MCS-80/85) mode
enum ICW4_8086 = 0x01;
/// Auto (normal) EOI
enum ICW4_AUTO = 0x20;
/// Buffered mode/slave
enum ICW4_BUF_SLAVE = 0x08;
/// Buffered mode/master
enum ICW4_BUF_MASTER = 0x0C;
/// Special fully nested (not)
enum ICW4_SFNM = 0x10;

enum CASCADE_IRQ = 2;

enum IRQ_OFFSET = 0x20;
enum ICW2_MASTER_OFFSET = IRQ_OFFSET;
enum ICW2_SLAVE_OFFSET = IRQ_OFFSET+8;

enum PIC_READ_IRR = 0x0A; // OCW3 irq ready next CMD read
enum PIC_READ_ISR = 0x0B; // OCW2 irq service next CMD read

public:

void setup() nothrow @nogc
{
    // // Hardware interrupts - 32 - 47
    // idt[32] = makeIDTEntry32(cast(uint)&interrupt32,    INTERRUPT_INTR_GATE);    // Timer
    // idt[33] = makeIDTEntry32(cast(uint)&interrupt33,    INTERRUPT_INTR_GATE);    // Keyboard
    // idt[34] = makeIDTEntry32(cast(uint)&interrupt34,    INTERRUPT_INTR_GATE);    // Cascade for 8259A Slave
    // idt[35] = makeIDTEntry32(cast(uint)&interrupt35,    INTERRUPT_INTR_GATE);    // Serial port 2
    // idt[36] = makeIDTEntry32(cast(uint)&interrupt36,    INTERRUPT_INTR_GATE);    // Serial port 1
    // idt[37] = makeIDTEntry32(cast(uint)&interrupt37,    INTERRUPT_INTR_GATE);    // AT systems: Parallel Port 2. PS/2 systems: reserved.
    // idt[38] = makeIDTEntry32(cast(uint)&interrupt38,    INTERRUPT_INTR_GATE);    // Diskette drive
    // idt[39] = makeIDTEntry32(cast(uint)&interrupt39,    INTERRUPT_INTR_GATE);    // Parallel Port 1 #7
    // idt[40] = makeIDTEntry32(cast(uint)&interrupt40,    INTERRUPT_INTR_GATE);    // CMOS Real time clock
    // idt[41] = makeIDTEntry32(cast(uint)&interrupt41,    INTERRUPT_INTR_GATE);    // CGA vertical retrace
    // idt[42] = makeIDTEntry32(cast(uint)&interrupt42,    INTERRUPT_INTR_GATE);    // Reserved
    // idt[43] = makeIDTEntry32(cast(uint)&interrupt43,    INTERRUPT_INTR_GATE);    // Reserved
    // idt[44] = makeIDTEntry32(cast(uint)&interrupt44,    INTERRUPT_INTR_GATE);    // AT systems: reserved. PS/2: auxiliary device
    // idt[45] = makeIDTEntry32(cast(uint)&interrupt45,    INTERRUPT_INTR_GATE);    // FPU
    // idt[46] = makeIDTEntry32(cast(uint)&interrupt46,    INTERRUPT_INTR_GATE);    // Hard disk controller
    // idt[47] = makeIDTEntry32(cast(uint)&interrupt47,    INTERRUPT_INTR_GATE);    // Reserved #15
    idt.setInterrupt(32, &timerHandler);
    idt.setInterrupt(33, &keyboardHandler);

    remap();

    debugPrintln("[PIC]: Set up");
}

void remap() nothrow @nogc
{
    ia32_outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);  // starts the initialization sequence (in cascade mode)
    ioWait();
    ia32_outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    ioWait();
    ia32_outb(PIC1_DATA, ICW2_MASTER_OFFSET);      // ICW2: Master PIC vector offset
    ioWait();
    ia32_outb(PIC2_DATA, ICW2_SLAVE_OFFSET);       // ICW2: Slave PIC vector offset
    ioWait();
    ia32_outb(PIC1_DATA, 1 << CASCADE_IRQ);        // ICW3: tell Master PIC that there is a slave PIC at IRQ2
    ioWait();
    ia32_outb(PIC2_DATA, CASCADE_IRQ);             // ICW3: tell Slave PIC its cascade identity
    ioWait();
    
    ia32_outb(PIC1_DATA, ICW4_8086);               // ICW4: have the PICs use 8086 mode (and not 8080 mode)
    ioWait();
    ia32_outb(PIC2_DATA, ICW4_8086);
    ioWait();

    // Unmask both PICs.
    ia32_outb(PIC1_DATA, 0);
    ia32_outb(PIC2_DATA, 0);
}

void setMask(ubyte line) nothrow @nogc
{
    ushort port;
    ubyte value;

    if (irqIsSlave(line))
    {
        port = PIC2_DATA;
        line -= 8;
    }
    else
    {
        port = PIC1_DATA;
    }
    ubyte bit = cast(ubyte)(1 << line); // D, why???
    value = ia32_inb(port) | bit;
    ia32_outb(port, value);
}

void clearMask(ubyte line) nothrow @nogc
{
    ushort port;
    ubyte value;

    if (irqIsSlave(line))
    {
        port = PIC2_DATA;
        line -= 8;
    }
    else
    {
        port = PIC1_DATA;
    }

    value = ia32_inb(port) & ~(1 << line);
    ia32_outb(port, value);
}

void disable() nothrow @nogc
{
    ia32_outb(PIC1_DATA, 0xFF);
    ia32_outb(PIC2_DATA, 0xFF);
}

void sendEOI(ubyte irq) nothrow @nogc
{
    if(irqIsSlave(irq))
        ia32_outb(PIC2_COMMAND,PIC_EOI);

    ia32_outb(PIC1_COMMAND, PIC_EOI);
}

ushort getISR() nothrow @nogc
{
    ia32_outb(PIC1_COMMAND, PIC_READ_ISR);
    ia32_outb(PIC2_COMMAND, PIC_READ_ISR);
    return (ia32_inb(PIC2_COMMAND) << 8) | ia32_inb(PIC1_COMMAND);
}

extern(C)
{
    int timerHandler(idt.InterruptFrame32 *frame)
    {
        sendEOI(0);

        timerTick();

        return 0;
    }

    immutable char[256] scancodeToASCII = [
        0x1E: 'a', 0x30: 'b', 0x2E: 'c', 0x20: 'd',
        0x12: 'e', 0x21: 'f', 0x22: 'g', 0x23: 'h',
        0x17: 'i', 0x24: 'j', 0x25: 'k', 0x26: 'l',
        0x32: 'm', 0x31: 'n', 0x18: 'o', 0x19: 'p',
        0x10: 'q', 0x13: 'r', 0x1F: 's', 0x14: 't',
        0x16: 'u', 0x2F: 'v', 0x11: 'w', 0x2D: 'x',
        0x15: 'y', 0x2C: 'z',
        0x02: '1', 0x03: '2', 0x04: '3', 0x05: '4',
        0x06: '5', 0x07: '6', 0x08: '7', 0x09: '8',
        0x0A: '9', 0x0B: '0',
        0x39: ' ', /* Space */
    ];

    int keyboardHandler(idt.InterruptFrame32 *frame)
    {
        sendEOI(1);

        ubyte scancode = ia32_inb(0x60);

        if (scancode & 0x80) // is released
            return 0;

        if (scancode < scancodeToASCII.length && scancodeToASCII[scancode])
        {
            debugPutc(scancodeToASCII[scancode]);
        }

        return 0;
    }
}
