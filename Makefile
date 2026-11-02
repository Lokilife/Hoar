
#  Bare-metal D kernel - top-level Makefile
#
#  Usage:
#     make                       # build for x86 / multiboot1
#     make x86_64                # target a different architecture
#     make ARCH=riscv64          # equivalent, via variable
#     make BOOT=multiboot2       # (not yet implemented)
#     make clean
#     make help
#
#  Layout:
#     source/                    D sources (common)
#     source/kernel/             kernel sources, incl. multiboot*.d
#     source/arch/<arch>/        arch-specific .asm and .d

#  1. Toolchain (override with `make VAR=value`)
D_COMPILER      ?= gdc
ASM_COMPILER    ?= nasm
LINKER          ?= ld
CPP             ?= cpp

D_FLAGS         ?=
ASM_FLAGS       ?=
LINKER_FLAGS    ?=
CPPFLAGS        ?= -P -I.
LIBS            ?=

#  2. Build selection
ARCH ?= x86
BOOT ?= multiboot1

#  3. Paths
SOURCE_DIR          := source
ARCH_DIR            := $(SOURCE_DIR)/arch
KERNEL_DIR          := $(SOURCE_DIR)/kernel
BUILD_DIR           := build
ARCH_BUILD          := $(BUILD_DIR)/$(ARCH)
KERNEL_ELF          := $(ARCH_BUILD)/kernel.elf
LINKER_SCRIPT_SRC   := linker.lds.S
LINKER_SCRIPT       := $(ARCH_BUILD)/linker.ld

#  4. Architecture-specific flags
#     (add new architectures here)
ifeq ($(ARCH),x86)
    ARCH_ASM_FLAGS := -f elf32
    ARCH_D_FLAGS   := -m32 -mno-red-zone -mno-sse -mno-sse2 -mno-mmx -mno-80387
    ARCH_LD_FLAGS  := -m elf_i386
else ifeq ($(ARCH),x86_64)
    ARCH_ASM_FLAGS := -f elf64
    ARCH_D_FLAGS   := -m64 -mno-red-zone -mno-sse -mno-sse2 -mno-mmx -mno-80387
    ARCH_LD_FLAGS  := -m elf_x86_64
else ifeq ($(ARCH),aarch64)
    ARCH_ASM_FLAGS := -f elf64
    ARCH_D_FLAGS   :=
    ARCH_LD_FLAGS  := -m aarch64elf
else ifeq ($(ARCH),arm)
    ARCH_ASM_FLAGS := -f elf32
    ARCH_D_FLAGS   :=
    ARCH_LD_FLAGS  := -m armelf
else ifeq ($(ARCH),riscv32)
    ARCH_ASM_FLAGS := -f elf32
    ARCH_D_FLAGS   :=
    ARCH_LD_FLAGS  := -m elf32lriscv
else ifeq ($(ARCH),riscv64)
    ARCH_ASM_FLAGS := -f elf64
    ARCH_D_FLAGS   :=
    ARCH_LD_FLAGS  := -m elf64lriscv
else
    $(error Unsupported ARCH '$(ARCH)'. Supported: \
        x86 x86_64 aarch64 arm riscv32 riscv64)
endif

#  5. Boot protocol selection
ifeq ($(BOOT),multiboot1)
    BOOT_ASM_FILE := $(ARCH_DIR)/$(ARCH)/kernel/multiboot1.asm
    BOOT_D_FILE   := $(KERNEL_DIR)/core/multiboot1.d
    BOOT_DEFINES  := -DBOOT_MULTIBOOT1
else ifeq ($(BOOT),multiboot2)
    BOOT_ASM_FILE := $(ARCH_DIR)/$(ARCH)/kernel/multiboot2.asm
    BOOT_D_FILE   := $(KERNEL_DIR)/core/multiboot2.d
    BOOT_DEFINES  := -DBOOT_MULTIBOOT2
else
    $(error Unsupported BOOT '$(BOOT)'. Supported: multiboot1 multiboot2)
endif

#  6. Source discovery
#     Exclude the boot-specific files from the generic scan and
#     re-add only the ones selected by $(BOOT).
D_SOURCES   := $(shell find $(SOURCE_DIR) -name '*.d'   ! -name 'multiboot*.d')
D_SOURCES   += $(BOOT_D_FILE)

ASM_SOURCES := $(shell find $(SOURCE_DIR) -name '*.asm' ! -name 'multiboot*.asm')
ASM_SOURCES += $(BOOT_ASM_FILE)

D_OBJECTS   := $(patsubst $(SOURCE_DIR)/%.d,   $(ARCH_BUILD)/%.d.o, $(D_SOURCES))
ASM_OBJECTS := $(patsubst $(SOURCE_DIR)/%.asm, $(ARCH_BUILD)/%.asm.o, $(ASM_SOURCES))
OBJECTS     := $(D_OBJECTS) $(ASM_OBJECTS)

#  7. Full flag sets
D_COMPILE_FLAGS := \
    $(D_FLAGS) \
    $(ARCH_D_FLAGS) \
    $(BOOT_DEFINES) \
    -I$(SOURCE_DIR) \
    -nophoboslib \
    -fno-moduleinfo \
    -fno-builtin \
    -fno-druntime \
    -fno-exceptions \
    -fno-asynchronous-unwind-tables \
    -g \
    -fdebug \
    -fassert \
    -fno-unwind-tables \
    -fno-rtti \
    -fno-pic -fno-pie \
    -fno-stack-protector \
    -Wall -Wextra \
    -O2 \
    -c

ASM_COMPILE_FLAGS := $(ASM_FLAGS) $(ARCH_ASM_FLAGS)

LINK_FLAGS := \
    $(LINKER_FLAGS) \
    $(ARCH_LD_FLAGS) \
    -T $(LINKER_SCRIPT)

#  8. Default target
.PHONY: all
all: $(KERNEL_ELF)

#  9. Link
$(KERNEL_ELF): $(OBJECTS) $(LINKER_SCRIPT)
	@mkdir -p $(dir $@)
	@echo "  LD      $@"
	@$(LINKER) $(LINK_FLAGS) -o $@ $(OBJECTS) $(LIBS)

$(ARCH_BUILD)/kernel/core/string.d.o: source/kernel/core/string.d
	@mkdir -p $(dir $@)
	@echo "  GDC     $<"
	@$(D_COMPILER) $(D_COMPILE_FLAGS) -fno-builtin -fno-tree-loop-distribute-patterns -c $< -o $@

$(LINKER_SCRIPT): $(LINKER_SCRIPT_SRC) source/arch/x86/kernel/init.data.ldh
	@mkdir -p $(dir $@)
	@echo "  CPP     $< -> $@"
	@$(CPP) $(CPPFLAGS) $(LINKER_SCRIPT_SRC) -o $@

# 10. Compile D  ->  object
$(ARCH_BUILD)/%.d.o: $(SOURCE_DIR)/%.d
	@mkdir -p $(dir $@)
	@echo "  GDC     $<"
	@$(D_COMPILER) $(D_COMPILE_FLAGS) $< -o $@

# 11. Assemble ASM  ->  object
$(ARCH_BUILD)/%.asm.o: $(SOURCE_DIR)/%.asm
	@mkdir -p $(dir $@)
	@echo "  NASM    $<"
	@$(ASM_COMPILER) $(ASM_COMPILE_FLAGS) $< -o $@

# 12. Per-architecture entry points ("functions")
#     Each one recurses into make with ARCH set, so the whole
#     build picks up the correct flags automatically.
.PHONY: x86 x86_64 aarch64 arm riscv32 riscv64
x86:     ; @$(MAKE) --no-print-directory ARCH=x86     all
x86_64:  ; @$(MAKE) --no-print-directory ARCH=x86_64  all
aarch64: ; @$(MAKE) --no-print-directory ARCH=aarch64 all
arm:     ; @$(MAKE) --no-print-directory ARCH=arm     all
riscv32: ; @$(MAKE) --no-print-directory ARCH=riscv32 all
riscv64: ; @$(MAKE) --no-print-directory ARCH=riscv64 all

# 13. Clean / help
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: help
help:
	@echo "Usage: make [target] [VAR=value]"
	@echo ""
	@echo "Targets:"
	@echo "  all        Build the kernel (default)"
	@echo "  x86        Build for 32-bit x86         (default)"
	@echo "  x86_64     Build for 64-bit x86"
	@echo "  aarch64    Build for AArch64"
	@echo "  arm        Build for 32-bit ARM"
	@echo "  riscv32    Build for 32-bit RISC-V"
	@echo "  riscv64    Build for 64-bit RISC-V"
	@echo "  run        Run kernel in QEMU"
	@echo "  clean      Remove the build directory"
	@echo "  help       Show this message"
	@echo ""
	@echo "Variables (override on the command line):"
	@echo "  ARCH           Target architecture    (default: x86)"
	@echo "  BOOT           Boot protocol          (default: multiboot1)"
	@echo "  D_COMPILER     D compiler             (default: gdc)"
	@echo "  ASM_COMPILER   Assembler              (default: nasm)"
	@echo "  LINKER         Linker                 (default: ld)"
	@echo "  D_FLAGS        Extra D flags"
	@echo "  ASM_FLAGS      Extra assembler flags"
	@echo "  LINKER_FLAGS   Extra linker flags"
	@echo "  LIBS           Extra libraries"

run: $(KERNEL_ELF)
	qemu-system-i386 -kernel $(KERNEL_ELF) -debugcon stdio

run-debug: $(KERNEL_ELF)
	qemu-system-i386 -kernel $(KERNEL_ELF) -debugcon stdio -initrd initrd.bin -no-reboot -no-shutdown -d int -D debug.log
