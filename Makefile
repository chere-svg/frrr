# OCamlOS Build System Makefile

CC = gcc
AS = gcc
OCAMLOPT = ocamlopt
LD = ld

CFLAGS = -Wall -Wextra -ffreestanding -fno-stack-protector -fno-pie -no-pie -mno-red-zone -m64 -mcmodel=kernel -I. -I$(shell ocamlopt -where)
ASFLAGS = -c -x assembler-with-cpp -m64 -fno-pie -no-pie -mcmodel=kernel
OCAMLFLAGS = -output-complete-obj -I arch/x86_64 -I memory -I drivers -I process -I scheduler -I fs -I net -I syscall -I user -I runtime

BUILD_DIR = build
ISO_DIR = $(BUILD_DIR)/isodir

C_SRCS = runtime/freestanding.c runtime/os_stubs.c drivers/serial.c drivers/vga.c libc/stubs.c
ASM_SRCS = boot/boot.S

ML_SRCS = arch/x86_64/ioport.ml arch/x86_64/cpu.ml arch/x86_64/mmu.ml \
          memory/pmm.ml memory/vmm.ml memory/heap.ml \
          drivers/uart.ml drivers/vga.ml drivers/pci.ml drivers/virtio_blk.ml drivers/virtio_net.ml \
          process/pcb.ml process/process.ml scheduler/scheduler.ml \
          fs/vfs.ml fs/ramfs.ml fs/ext2.ml \
          net/ethernet.ml net/arp.ml net/ipv4.ml net/icmp.ml net/udp.ml net/tcp.ml net/socket.ml \
          syscall/syscall.ml user/shell.ml user/utils.ml runtime/baremetal_runtime.ml \
          kernel/kmain.ml

C_OBJS = $(patsubst %.c, $(BUILD_DIR)/%.o, $(C_SRCS))
ASM_OBJS = $(patsubst %.S, $(BUILD_DIR)/%.o, $(ASM_SRCS))
KERNEL_ML_OBJ = $(BUILD_DIR)/kernel_ml.o

KERNEL_ELF = $(BUILD_DIR)/ocamlos.elf
KERNEL_ISO = $(BUILD_DIR)/ocamlos.iso

.PHONY: all run iso debug clean measure

all: $(KERNEL_ELF)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)/boot $(BUILD_DIR)/runtime $(BUILD_DIR)/drivers $(BUILD_DIR)/kernel $(BUILD_DIR)/libc

$(BUILD_DIR)/%.o: %.S | $(BUILD_DIR)
	$(AS) $(ASFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(KERNEL_ML_OBJ): $(ML_SRCS) | $(BUILD_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) -o $@ $(ML_SRCS)

$(KERNEL_ELF): $(ASM_OBJS) $(C_OBJS) $(KERNEL_ML_OBJ) linker.ld
	$(LD) -n -T linker.ld -o $@ $(ASM_OBJS) $(C_OBJS) $(KERNEL_ML_OBJ) $(shell ocamlopt -where)/libasmrun.a

iso: $(KERNEL_ISO)

$(KERNEL_ISO): $(KERNEL_ELF)
	mkdir -p $(ISO_DIR)/boot/grub
	cp $(KERNEL_ELF) $(ISO_DIR)/boot/ocamlos.elf
	echo 'set timeout=0' > $(ISO_DIR)/boot/grub/grub.cfg
	echo 'set default=0' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo 'menuentry "OCamlOS" {' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '  multiboot2 /boot/ocamlos.elf' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '  boot' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '}' >> $(ISO_DIR)/boot/grub/grub.cfg
	grub-mkrescue -o $(KERNEL_ISO) $(ISO_DIR) 2>/dev/null || xorriso -as mkisofs -R -b boot/grub/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table -o $(KERNEL_ISO) $(ISO_DIR)

run: $(KERNEL_ELF)
	qemu-system-x86_64 -kernel $(KERNEL_ELF) -serial stdio -display none -no-reboot

measure:
	./tools/count_languages.sh

clean:
	rm -rf $(BUILD_DIR) *.o *.cm* arch/x86_64/*.cm* memory/*.cm* drivers/*.cm* process/*.cm* scheduler/*.cm* fs/*.cm* net/*.cm* syscall/*.cm* user/*.cm* runtime/*.cm* kernel/*.cm* gui/*.cm*
