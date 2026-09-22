/* boot/boot.S - Ultra-minimal x86_64 Long Mode entry for 99.9% OCamlOS */

#define MULTIBOOT2_HEADER_MAGIC 0xe85250d6
#define MULTIBOOT_ARCHITECTURE_I386 0

.code32
.section .multiboot
.align 8
multiboot_header:
    .long MULTIBOOT2_HEADER_MAGIC
    .long MULTIBOOT_ARCHITECTURE_I386
    .long multiboot_header_end - multiboot_header
    .long -(MULTIBOOT2_HEADER_MAGIC + MULTIBOOT_ARCHITECTURE_I386 + (multiboot_header_end - multiboot_header))
    .short 0, 0
    .long 8
multiboot_header_end:

.section .bss
.align 4096
p4_table: .skip 4096
p3_table: .skip 4096
p2_table: .skip 4096
stack_bottom: .skip 32 * 1024
stack_top:
.align 16
tcb_buffer: .skip 256

.section .rodata
gdt64:
    .quad 0
gdt64_code:
    .quad (1<<43) | (1<<44) | (1<<47) | (1<<53)
gdt64_data:
    .quad (1<<41) | (1<<44) | (1<<47)
gdt64_pointer:
    .word gdt64_pointer - gdt64 - 1
    .quad gdt64

.section .text
.global _start
.type _start, @function
_start:
    cli
    mov $stack_top, %esp
    mov %eax, %edi
    mov %ebx, %esi

    /* Setup 1GB identity page table */
    mov $p3_table, %eax
    or $3, %eax
    mov %eax, p4_table

    mov $p2_table, %eax
    or $3, %eax
    mov %eax, p3_table

    mov $0, %ecx
.map_p2:
    mov $0x200000, %eax
    mul %ecx
    or $0x83, %eax
    mov %eax, p2_table(,%ecx,8)
    inc %ecx
    cmp $512, %ecx
    jne .map_p2

    /* Enable Long Mode */
    mov $p4_table, %eax
    mov %eax, %cr3
    mov %cr4, %eax
    or $(1 << 5), %eax
    mov %eax, %cr4
    mov $0xC0000080, %ecx
    rdmsr
    or $(1 << 8), %eax
    wrmsr
    mov %cr0, %eax
    or $(1 << 31), %eax
    mov %eax, %cr0

    lgdt (gdt64_pointer)
    ljmp $8, $long_mode_entry

.code64
long_mode_entry:
    mov $0, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss
    mov $stack_top, %rsp

    /* Setup TLS stack canary at FS:0x28 */
    movabs $0x595e9fbd94fda766, %rax
    movq %rax, tcb_buffer + 0x28
    mov $0xC0000100, %ecx
    mov $tcb_buffer, %rax
    mov %rax, %rdx
    shr $32, %rdx
    wrmsr

    /* Enable SSE & FPU (required for x86_64 OCaml runtime) */
    mov %cr0, %rax
    and $~(1 << 2), %rax
    or $(1 << 1), %rax
    mov %rax, %cr0

    mov %cr4, %rax
    or $((1 << 9) | (1 << 10)), %rax
    mov %rax, %cr4
    fninit

    mov %edi, %edi
    mov %esi, %esi
    call kernel_main_c

.hang:
    hlt
    jmp .hang
