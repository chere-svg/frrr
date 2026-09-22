# AGENTS.md — Codebase Guide for AI Agents

Welcome to **OCamlOS**, an experimental bare-metal 64-bit operating system for x86_64 written primarily in **OCaml**. This guide provides AI agents and human contributors with an exhaustive technical blueprint, system layout, boot flow, subsystem architecture, build commands, and coding guidelines.

---

## 1. Project Overview & Design Philosophy

OCamlOS demonstrates that operating system kernels, process schedulers, device drivers, virtual filesystems, and network stacks can be built in a type-safe, functional language (OCaml) with minimal C and assembly code strictly reserved for low-level hardware bootstrapping and CPU instructions.

- **Primary Language**: OCaml (native x86_64 code via `ocamlopt`)
- **Boot Target**: x86_64 Long Mode (64-bit) booted via Multiboot2 (GRUB2 / Limine)
- **Runtime**: OCaml GC runtime (`libasmrun.a`) integrated with a freestanding C glue layer (`runtime/freestanding.c`, `runtime/os_stubs.c`, `libc/stubs.c`)
- **User Interface**: Interactive Linux-like terminal shell in OCaml (`user/shell.ml`) supporting full line editing, command history, auto-completion, ANSI color output, and standard UNIX tools.

---

## 2. System Architecture & Boot Sequence

### 2.1 Complete Execution Flow

```
1. Firmware (BIOS/UEFI)
   └─► Bootloader (GRUB2 / Limine)
         └─► Multiboot2 32-bit Header Entry (_start in boot/boot.S)
               ├─► Disable Interrupts (cli), Setup Initial 32-bit Stack
               ├─► Build Early Page Tables (P4 -> P3 -> P2 2MB Identity Mapping)
               ├─► Set CR3, Enable PAE (CR4.PAE), Enable Long Mode (EFER.LME), Enable Paging (CR0.PG)
               ├─► Load 64-bit Global Descriptor Table (GDT)
               ├─► Far Jump to 64-bit Code Segment (long_mode_entry)
               └─► Long Mode Execution (boot/boot.S)
                     ├─► Reset Segment Registers (DS, ES, FS, GS, SS)
                     ├─► Setup 64-bit Kernel Stack
                     ├─► Initialize Stack Canary Buffer (FS:0x28)
                     └─► Call C Kernel Entry Point: kernel_main_c(magic, mb_info_addr)
                           └─► Freestanding C Runtime (runtime/os_stubs.c)
                                 ├─► Early Serial COM1 & VGA Text Mode Initialization
                                 ├─► Early Bump Allocator Setup (malloc/calloc)
                                 ├─► OCaml Runtime Initialization: caml_startup(argv)
                                 └─► Execute OCaml Kernel Entry Point: Kernel.kmain (kernel/kmain.ml)
```

---

## 3. Directory Structure & Subsystem Map

```
/app/
├── boot/                   # Assembly Bootstrap & Bootloader
│   └── boot.S              # Multiboot2 entry, page table setup, 32-to-64 bit transition
├── arch/x86_64/            # Hardware & CPU Abstraction
│   ├── io.h                # Low-level inline assembly port I/O macros (inb, outb, inw, outw, inl, outl)
│   ├── ioport.ml           # OCaml FFI declarations for port I/O
│   ├── mmu.ml              # Page table entry packing/unpacking and page flags
│   └── cpu.ml              # Control register and CPU instruction wrappers
├── runtime/                # OCaml Runtime Support & C FFI Stubs
│   ├── os_stubs.c          # FFI stubs for port I/O, VGA memory, serial, keyboard driver, shutdown/reboot
│   ├── freestanding.c      # Freestanding C standard library functions (memcpy, memset, malloc, free)
│   └── baremetal_runtime.ml# OCaml bare-metal runtime initialization hook
├── libc/                   # Freestanding C Math & POSIX Stubs
│   └── stubs.c             # C stubs required by OCaml runtime libasmrun.a (signal, stdio, math)
├── memory/                 # Memory Management Subsystem (OCaml)
│   ├── pmm.ml              # Physical Frame Allocator managing 128MB RAM via bitmap
│   ├── vmm.ml              # Page table manipulation (PML4, PDPT, PD, PT)
│   └── heap.ml             # High-level OCaml kernel heap allocator
├── scheduler/              # Preemptive Multitasking (OCaml)
│   └── scheduler.ml        # Round-robin process run-queue scheduler
├── process/                # Process Control & Context Management (OCaml)
│   ├── pcb.ml              # Process Control Block definition
│   └── process.ml          # Process creation, state management, and memory context
├── drivers/                # Hardware Device Drivers (C & OCaml)
│   ├── serial.c / uart.ml  # 16550 UART COM1 serial driver
│   ├── vga.c / vga.ml      # 80x25 VGA text mode driver with color formatting
│   ├── pci.ml              # PCI bus enumeration and device discovery
│   ├── virtio_blk.ml       # VirtIO block storage device driver
│   └── virtio_net.ml       # VirtIO network device driver
├── fs/                     # Virtual File System & Filesystems (OCaml)
│   ├── vfs.ml              # VFS node tree, permissions, path lookup, listing
│   ├── ramfs.ml            # In-memory filesystem implementation with default /etc, /tmp, /var hierarchy
│   └── ext2.ml             # Disk-based Ext2 filesystem reader/writer
├── net/                    # Networking Stack (OCaml)
│   ├── ethernet.ml         # Ethernet II frame parser & builder
│   ├── arp.ml              # ARP table and protocol handling
│   ├── ipv4.ml             # IPv4 packet parsing and routing
│   ├── icmp.ml             # ICMP ping echo responder
│   ├── udp.ml              # UDP datagram handling
│   ├── tcp.ml              # TCP connection state machine (LISTEN, ESTABLISHED)
│   └── socket.ml           # Functional Socket abstraction (Stream / Datagram)
├── syscall/                # System Call Interface (OCaml)
│   └── syscall.ml          # Syscall dispatcher
├── user/                   # Interactive Userland & Terminal Shell (OCaml)
│   ├── shell.ml            # Full Linux-compatible interactive terminal shell & utility suite
│   └── utils.ml            # Userland utility functions
├── kernel/                 # Kernel Core Entry Point (OCaml)
│   └── kmain.ml            # kmain entry point, terminal input loop, sub-system boot sequence
├── tools/                  # Developer & Audit Tools
│   └── count_languages.sh  # Source line count and language audit tool
├── docs/                   # Architectural Documentation
│   ├── ARCHITECTURE.md     # In-depth technical architecture specification
│   └── non_ocaml_code.md   # Non-OCaml code inventory and minimization strategy
├── Makefile                # Build system configuration
├── linker.ld               # Kernel ELF linker script
└── dune-project            # Dune project metadata
```

---

## 4. Key Subsystems in Detail

### 4.1 Memory Management (`memory/`)
- **Physical Memory Manager (`pmm.ml`)**: Bitmap allocator managing 128 MB physical frame space in 4KB chunks (`alloc_frame`, `free_frame`).
- **Virtual Memory Manager (`vmm.ml`)**: Maps PML4 page directory structures to manage virtual spaces (`create_kernel_space`).
- **Kernel Heap (`heap.ml`)**: Provides kernel dynamic allocation primitives.

### 4.2 Terminal Shell & Userland (`user/shell.ml`)
- **Supported Commands**: `ls`, `cd`, `pwd`, `cat`, `head`, `tail`, `wc`, `grep`, `find`, `tree`, `stat`, `touch`, `mkdir`, `rm`, `cp`, `mv`, `chmod`, `chown`, `diff`, `file`, `nano`/`edit`, `more`/`less`, `uname`, `uptime`, `whoami`, `id`, `hostname`, `date`, `ps`, `top`, `kill`, `free`, `df`, `du`, `dmesg`, `mount`, `lscpu`, `lspci`, `env`, `export`, `history`, `alias`, `which`, `echo`, `ifconfig`, `ping`, `netstat`, `arp`, `route`, `reboot`, `poweroff`, `calc`, `base64`, `sleep`, `cmatrix`, `fortune`, `cowsay`, `man`, `help`, `clear`, `exit`.
- **Features**: Single/double quote parsing, variable expansion (`$USER`, `$PWD`), redirection (`>`, `>>`), command history navigation (Up/Down arrows), tab auto-completion, ANSI color styling.

### 4.3 Hardware I/O & FFI Boundary (`runtime/os_stubs.c` <-> `arch/x86_64/ioport.ml`)
- Port I/O instructions (`inb`, `outb`, `inw`, `outw`, `inl`, `outl`) are defined as C primitives (`caml_inb`, `caml_outb`) and exposed to OCaml via `external`.
- Hardware polling (`caml_poll_hardware`) handles PS/2 keyboard scancodes and COM1 serial ANSI escape sequences into unified keycodes.

---

## 5. Build System & Tooling

### 5.1 Build Commands
```bash
# Compile kernel ELF binary (build/ocamlos.elf)
make

# Create bootable ISO image (build/ocamlos.iso)
make iso

# Launch OCamlOS inside QEMU
make run

# Execute Language Composition Audit
bash tools/count_languages.sh

# Clean build artifacts
make clean
```

### 5.2 Linker Script (`linker.ld`)
The kernel is linked at `0x100000` (1MB physical memory mark), reserving space above Multiboot headers for the `.text`, `.rodata`, `.data`, and `.bss` sections.

---

## 6. Language Audit & Minimization Strategy

Run `bash tools/count_languages.sh` to see the current codebase breakdown:
- **OCaml (`.ml`)**: ~64.65% (kernel, shell, drivers, vfs, net, memory, process)
- **C (`.c`)**: ~32.23% (freestanding libc stubs, hardware I/O FFI wrappers)
- **Assembly (`.S`)**: ~3.11% (32-to-64 bit bootstrap in `boot/boot.S`)

Refer to `docs/non_ocaml_code.md` for the roadmap toward eliminating non-OCaml glue.

---

## 7. Guidelines for AI Agents Modifying Code

When modifying or adding features to OCamlOS:
1. **Maintain Type Safety**: Implement new drivers, protocols, or utilities in OCaml whenever possible rather than adding C code.
2. **Interrupt & Allocator Safety**: Avoid OCaml allocations inside low-level interrupt handlers.
3. **Dual Output Support**: Ensure display output goes through unified helpers (e.g., `term_write` or `write` in `shell.ml`) so messages render on both VGA text console and COM1 serial log.
4. **Build Verification**: Ensure `Makefile` includes any new `.ml` or `.c` files in `ML_SRCS` or `C_SRCS`.
5. **Git Hygiene**: Keep temporary artifacts (`build/`, `*.o`, `*.cm*`) out of git.
