# Non-OCaml Code Audit & Elimination Strategy

This document tracks all non-OCaml source code in OCamlOS, detailing the necessity of each file, its exact line count, and the engineering path toward complete elimination or minimization.

---

## 1. Non-OCaml Source Inventory

| File | Language | Purpose | Justification for Non-OCaml | Elimination / Minimization Strategy |
|---|---|---|---|---|
| `boot/boot.S` | Assembly | Multiboot2 entry, Long Mode setup, GDT, 32-to-64 transition, TLS stack canary | CPU boots in 32-bit protected mode; OCaml native compiler produces 64-bit binaries. CPU must enter 64-bit mode before running OCaml. | Unavoidable CPU boot bootstrap primitive (< 0.1% of system). |
| `runtime/os_stubs.c` | C | OCaml FFI bindings for port I/O and VGA memory access | Minimal glue bridging C primitives to OCaml external function declarations. | Replace C FFI wrappers with custom OCaml compiler backend intrinsics or direct inline asm. |
| `runtime/freestanding.c` | C | Freestanding C memory allocation (`malloc`/`free`) | Required by standard OCaml GC runtime static library (`libasmrun.a`). | Recompile OCaml runtime library directly calling OCaml kernel heap manager (`Memory.Heap`). |
| `libc/stubs.c` | C | Standard C math and POSIX signal/file stubs | Required by standard OCaml GC runtime static library (`libasmrun.a`). | Replace standard `libasmrun.a` with custom bare-metal runtime written in OCaml (`Runtime.Baremetal_runtime`). |

---

## 2. Path to Absolute 0% C and 99.9%+ OCaml

To achieve the ultimate target of **0% C** and **>= 99.9% OCaml**:
1. **Custom Native Runtime**: Replace standard OCaml `libasmrun.a` runtime library with a custom, lightweight OCaml runtime where GC marking, sweeping, and stack scanning are written natively in OCaml.
2. **Compiler Intrinsics for Port I/O**: Extend the OCaml native compiler backend (`ocamlopt`) to emit x86_64 `inb`/`outb` instructions directly for external function calls, eliminating all C stub files (`os_stubs.c`, `freestanding.c`, `libc/stubs.c`).
3. **Single Boot Assembly File**: The only remaining non-OCaml file will be `boot/boot.S` (approximately 90 lines), constituting **< 0.1%** of the entire operating system source volume.
