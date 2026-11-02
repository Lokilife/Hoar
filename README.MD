# Hoar

Hoar is a hobby OS written in D. And like almost every hobby OS, it also aims to support the oldest technologies while maintaining minimal weight and maximum speed. 

Early stages of development, here is the list I follow:

- [x] GDT
- [x] IDT
- [x] Dumb VM debug port
- [x] 8259A
- [x] PMM
- [x] Paging and VMM
- [x] Heap
- [x] kthreads cooperative
- [x] kthreads preemptive
- [x] Ring 3 + int 80h:
    - [x] TSS
    - [x] Address space switching
    - [x] Syscall dispatch
    - [x] User program run
    - [x] Base Fault handling

The great milestone No.1
- [x] primitive initrd (Note: initrd isn't planned to be a part of the kernel architecture and only needed as basic FS for tests of other things)
- [ ] ELF loader
- [ ] Process model
- [ ] A shell: The first real one that reads from keyboard, and performs work by command
- [ ] IDE disks
- [ ] VFS
- [ ] FAT32

Deffered:
- [ ] Switch from 8259A to APIC
- [ ] HPET
- [ ] Serial terminal driver
- [ ] VGA driver
