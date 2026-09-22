# OCamlOS: Technical Architecture & Implementation Specification

## 1. Executive Summary & Design Philosophy
**OCamlOS** is an experimental, bare-metal 64-bit operating system for x86_64 written primarily in OCaml. The system design minimizes C and assembly code to the lowest possible hardware primitives (bootstrapping, context switching, interrupt handlers, and low-level I/O instructions), delegating memory management, process scheduling, virtual filesystem (VFS), device driver abstractions, and network protocol stacks to type-safe, functional OCaml code.

---

## 2. Boot Architecture & Sequence

### Complete Execution Flow
```
Firmware (BIOS/UEFI)
  └─► Bootloader (GRUB2 / Limine)
        └─► 32-bit Multiboot2 Header Entry (_start in boot/boot.S)
              ├─► Disable Interrupts (cli), Setup Initial 32-bit Stack
              ├─► Build Early Page Tables (P4 -> P3 -> P2 2MB Huge Pages, 1GB Identity Map)
              ├─► Set CR3, Enable PAE (CR4.PAE), Enable Long Mode (EFER.LME), Enable Paging (CR0.PG)
              ├─► Load 64-bit Global Descriptor Table (GDT)
              ├─► Far Jump to 64-bit Code Segment (long_mode_entry)
              └─► Long Mode Setup (boot/boot.S)
                    ├─► Reset Segment Registers (DS, ES, FS, GS, SS)
                    ├─► Setup 64-bit Kernel Stack
                    ├─► Initialize TLS/TCB Buffer for Stack Canary (FS:0x28)
                    └─► Call C Kernel Entry Point: kernel_main_c(magic, mb_info_addr)
                          └─► Freestanding C Runtime (runtime/os_stubs.c)
                                ├─► Early Hardware Init: COM1 UART Serial & 80x25 VGA Drivers
                                ├─► Early Memory Init: 16 MB Bump Allocator (malloc/calloc)
                                ├─► OCaml Runtime Init: caml_startup(argv)
                                └─► Jump to High-Level OCaml Entry Point: Kernel.kmain (kernel/kmain.ml)
```

### Language Boundaries
- **Assembly (`boot/boot.S`, `arch/x86_64/context.S`)**: Multiboot2 header, 32-to-64 bit transition, page table creation, GDT/IDT register loading, context switching (`swap_context`).
- **C (`runtime/freestanding.c`, `runtime/os_stubs.c`, `libc/stubs.c`)**: Freestanding libc stubs (`memcpy`, `memset`, `malloc`, `fputc`), OCaml GC C runtime bindings, early driver wrappers.
- **OCaml (`kernel/kmain.ml`, `memory/`, `scheduler/`, `fs/`, `net/`)**: Entire high-level kernel logic, physical/virtual page allocators, OCaml heap management, thread scheduling, IPC, VFS, device drivers, network stack, and shell.

---

## 3. Kernel Subsystems Architecture

### 3.1 Architecture & CPU Control (`arch/x86_64/`)
- **GDT & TSS**: Sets up Kernel Code (RPL 0), Kernel Data (RPL 0), User Code (RPL 3), User Data (RPL 3), and Task State Segment (TSS) containing IST1 for Double Fault stack and IST2 for NMI.
- **IDT & Interrupt Handling**: 256 interrupt gates. Vectors 0-31 map to CPU exceptions. Exceptions save registers, construct an exception frame, and dispatch to OCaml exception handlers via FFI.
- **Syscall Gate**: `IA32_STAR` and `IA32_LSTAR` MSRs are configured to point to `syscall_entry`. Fast privilege transition without interrupt overhead.

### 3.2 Memory Management Subsystem (`memory/`)
- **Physical Page Allocator**: Bitmap allocator managing 4KB physical frames beyond kernel memory limits.
- **Virtual Memory & Page Tables**: Manage PML4 -> PDPT -> PD -> PT mapping structures. Supports 4KB standard pages and 2MB huge pages. Higher-half kernel mapping (`0xFFFF800000000000`).
- **OCaml Heap & GC Integration**:
  - The OCaml runtime uses a two-space generational GC:
    - **Minor Heap**: Bump-allocated, small fixed-size arena (e.g., 2MB). Fast allocation. Collected via copying GC.
    - **Major Heap**: Mark-and-sweep GC managing larger and long-lived objects.
  - **GC & Interrupt Safety**: During interrupt handler execution, GC allocation is strictly prohibited to prevent re-entrancy and heap corruption. Interrupt handlers execute on separate C kernel stacks.

### 3.3 Process Management & Scheduler (`scheduler/`, `process/`)
- **Thread Abstraction**: `type process = { pid: int; mutable state: process_state; page_table: int64; context: cpu_context }`.
- **Preemptive Scheduler**: Round-robin run queue triggered by LAPIC/PIT timer interrupt.
- **Context Switching**: Assembly helper `swap_context(old_ctx, new_ctx)` saves and restores Callee-Saved Registers (`RBX`, `RBP`, `R12`, `R13`, `R14`, `R15`, `RSP`, `RIP`).

### 3.4 VFS & Filesystem (`fs/`)
- **VFS Interface**: Modular file system abstraction supporting `open`, `read`, `write`, `close`, `readdir`, `mkdir`, `mount`.
- **Memory VFS & Ext2**: In-memory tree structure for initial dev/tmp/proc filesystems, backing up to disk-based Ext2 implementation over VirtIO block devices.

### 3.5 Device Drivers (`drivers/`)
- **UART Serial**: 16550 COM1 (`0x3F8`) for debug log streaming.
- **VGA Text Driver**: `0xB8000` MMIO buffer driver for 80x25 text console.
- **VirtIO Network & Storage**: PCI device discovery and VirtIO queue management for disk storage and network interfaces.

### 3.6 Network Stack (`net/`)
- **Protocols**: Ethernet II -> ARP -> IPv4 -> ICMP / UDP / TCP.
- **Sockets API**: Functional socket interface exposing non-blocking read/write operations to userland.

---

## 4. Milestone Development Roadmap

| Stage | Milestone Objective | Key Files / Subsystems | Expected Result |
|---|---|---|---|
| **0** | **Cross-Compilation & Toolchain Setup** | `Makefile`, `linker.ld`, `runtime/freestanding.c` | Freestanding OCaml build environment compiling `ocamlos.elf`. |
| **1** | **Booting & Text Mode Output** | `boot/boot.S`, `drivers/vga.c`, `drivers/serial.c` | CPU enters 64-bit Long Mode, prints banner via VGA and Serial. |
| **2** | **OCaml Bare-Metal Runtime** | `runtime/os_stubs.c`, `kernel/kmain.ml` | `caml_startup` initializes OCaml GC, executes OCaml code, closures, and exceptions. |
| **3** | **Memory Management** | `memory/pmm.ml`, `memory/vmm.ml` | Physical frame allocator and virtual memory page table manipulation in OCaml. |
| **4** | **Interrupts & Exceptions** | `arch/x86_64/idt.S`, `arch/x86_64/isr.ml` | IDT loaded, page faults and CPU exceptions caught in OCaml. |
| **5** | **Timer & Scheduler** | `arch/x86_64/timer.c`, `scheduler/sched.ml` | PIT/LAPIC timer interrupts trigger preemptive context switches between OCaml threads. |
| **6** | **Processes & Syscalls** | `syscall/syscall.ml`, `process/process.ml` | `SYSCALL`/`SYSRET` privilege separation (Ring 0 / Ring 3) and process creation. |
| **7** | **Filesystem** | `fs/vfs.ml`, `fs/ramfs.ml`, `fs/ext2.ml` | VFS hierarchy with root `/`, `/bin`, `/dev`, `/tmp` mounting ramfs and ext2. |
| **8** | **Device Drivers** | `drivers/pci.ml`, `drivers/virtio.ml` | PCI bus enumeration and VirtIO block/net device drivers in OCaml. |
| **9** | **Networking** | `net/arp.ml`, `net/ipv4.ml`, `net/tcp.ml` | ARP resolving, ICMP ping response, and active TCP socket connections in QEMU. |
| **10**| **Userland & Shell** | `user/shell.ml`, `user/bin/` | Interactive OCaml shell supporting `ls`, `cat`, `echo`, `ps`, `mem`, `ping`. |
| **11**| **SMP & Multicore OCaml** | `arch/x86_64/smp.c`, `kernel/multicore.ml` | APIC IPI initialization booting secondary cores running OCaml 5 multicore domains. |

---

## 5. Repository Tree

```
ocamlos/
├── boot/
│   └── boot.S
├── arch/
│   └── x86_64/
│       ├── io.h
│       ├── gdt.c
│       ├── idt.c
│       └── context.S
├── runtime/
│   ├── freestanding.c
│   └── os_stubs.c
├── libc/
│   └── stubs.c
├── kernel/
│   └── kmain.ml
├── memory/
│   ├── pmm.ml
│   └── vmm.ml
├── scheduler/
│   └── sched.ml
├── process/
│   └── process.ml
├── drivers/
│   ├── serial.c
│   ├── vga.c
│   ├── pci.ml
│   └── virtio.ml
├── fs/
│   ├── vfs.ml
│   └── ext2.ml
├── net/
│   ├── ethernet.ml
│   ├── ipv4.ml
│   └── tcp.ml
├── syscall/
│   └── syscall.ml
├── user/
│   └── shell.ml
├── tools/
├── tests/
├── docs/
│   └── ARCHITECTURE.md
├── scripts/
├── dune-project
├── linker.ld
├── Makefile
└── README.md
```

---

## 6. How to Build & Run Initial Baseline Implementation

### Requirements
- `gcc`, `binutils` (x86_64)
- `ocaml` (v4.14+ or 5.x), `ocamlopt`
- `qemu-system-x86_64`
- `grub-mkrescue` / `xorriso`

### Build Commands
```bash
# Build kernel ELF binary
make

# Build bootable ISO image
make iso

# Execute OCamlOS in QEMU
make run
```
