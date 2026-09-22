# OCamlOS: A Bare-Metal Operating System in OCaml

**OCamlOS** is an experimental, bare-metal 64-bit operating system for x86_64 written primarily in OCaml, minimizing C and Assembly code to bare-metal primitives and runtime hooks.

---

## Technical Features
- **Boot Sequence**: Multiboot2 header -> 32-bit entry -> Page table setup -> 64-bit Long Mode transition -> GDT setup -> C runtime stubs -> OCaml runtime `caml_startup` -> `Kernel.kmain`.
- **Primary Language**: Kernel logic, memory abstractions, processes, scheduling, VFS, drivers, network protocols, and shell implemented in OCaml.
- **Minimal Assembly/C Primitive Layer**: Multiboot2 bootstrap, TLS stack canary guard setup (`FS:0x28`), port I/O primitives, UART COM1 serial and 80x25 VGA drivers, and freestanding POSIX/C math stubs for OCaml runtime integration.
- **Bare-Metal OCaml GC Support**: Full support for OCaml minor/major heaps, higher-order functions, closures, pattern matching, and exception handling without host OS dependency.

---

## Directory Tree

```
ocamlos/
├── boot/           # Assembly bootloader & Multiboot2 entry (boot.S)
├── arch/x86_64/    # Hardware I/O and CPU control primitives (io.h)
├── runtime/        # Freestanding C library and OCaml FFI stubs
├── libc/           # C library stubs (malloc, signal, math, stdio)
├── kernel/         # OCaml kernel entry point (kmain.ml)
├── memory/         # Physical and virtual memory management stubs
├── scheduler/      # Preemptive scheduler stubs
├── process/        # Process and thread control structures
├── drivers/        # Device drivers (serial, VGA, PCI, VirtIO)
├── fs/             # VFS and file system implementation stubs
├── net/            # Network protocol stack stubs
├── syscall/        # System call dispatcher stubs
├── user/           # Userland shell and utilities
├── docs/           # Architecture and technical specification (ARCHITECTURE.md)
├── Makefile        # Build system configuration
├── linker.ld       # Kernel ELF linker script
└── README.md
```

---

## Quick Start

### Build & Run
```bash
# Compile kernel ELF binary
make

# Create bootable ISO image
make iso

# Run OCamlOS in QEMU
make run
```

### Architecture Specifications
See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for full architectural documentation, design decisions, FFI boundaries, subsystem specs, and 12-stage implementation roadmap.
