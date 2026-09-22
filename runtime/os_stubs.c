/* runtime/os_stubs.c - OCaml FFI stubs for hardware I/O and kernel entry hook */

#include <stddef.h>
#include <stdint.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include "../arch/x86_64/io.h"

extern void serial_init(void);
extern void serial_puts(const char *s);
extern char serial_getchar(void);
extern int serial_received(void);
extern void vga_init(void);
extern void vga_puts(const char *s);

/* FFI bindings for OCaml Port I/O */
CAMLprim value caml_outb(value v_port, value v_val) {
    outb((uint16_t)Int_val(v_port), (uint8_t)Int_val(v_val));
    return Val_unit;
}

CAMLprim value caml_inb(value v_port) {
    uint8_t ret = inb((uint16_t)Int_val(v_port));
    return Val_int(ret);
}

CAMLprim value caml_outw(value v_port, value v_val) {
    outw((uint16_t)Int_val(v_port), (uint16_t)Int_val(v_val));
    return Val_unit;
}

CAMLprim value caml_inw(value v_port) {
    uint16_t ret = inw((uint16_t)Int_val(v_port));
    return Val_int(ret);
}

CAMLprim value caml_outl(value v_port, value v_val) {
    outl((uint16_t)Int_val(v_port), (uint32_t)Int32_val(v_val));
    return Val_unit;
}

CAMLprim value caml_inl(value v_port) {
    uint32_t ret = inl((uint16_t)Int_val(v_port));
    return caml_copy_int32(ret);
}

CAMLprim value caml_cli(value v_unit) {
    (void)v_unit;
    cli();
    return Val_unit;
}

CAMLprim value caml_sti(value v_unit) {
    (void)v_unit;
    sti();
    return Val_unit;
}

CAMLprim value caml_hlt(value v_unit) {
    (void)v_unit;
    hlt();
    return Val_unit;
}

CAMLprim value caml_read_cr3(value v_unit) {
    (void)v_unit;
    uint64_t cr3;
    __asm__ __volatile__("mov %%cr3, %0" : "=r"(cr3));
    return caml_copy_int64(cr3);
}

CAMLprim value caml_write_cr3(value v_cr3) {
    uint64_t cr3 = Int64_val(v_cr3);
    __asm__ __volatile__("mov %0, %%cr3" : : "r"(cr3));
    return Val_unit;
}

/* Full VGA text-mode state — color-aware, scrolling */
static volatile uint16_t *vga_buf = (volatile uint16_t *)0xB8000;
#define VGA_W 80
#define VGA_H 25

static void vga_scroll_up(void) {
    for (int y = 1; y < VGA_H; y++)
        for (int x = 0; x < VGA_W; x++)
            vga_buf[(y-1)*VGA_W + x] = vga_buf[y*VGA_W + x];
    for (int x = 0; x < VGA_W; x++)
        vga_buf[(VGA_H-1)*VGA_W + x] = (uint16_t)' ' | (0x0F << 8);
}

CAMLprim value caml_write_vga_mem(value v_offset, value v_char, value v_color) {
    int byte_off = Int_val(v_offset);
    unsigned char c     = (unsigned char)Int_val(v_char);
    unsigned char color = (unsigned char)Int_val(v_color);
    /* sentinel -1 = scroll */
    if (byte_off < 0) {
        vga_scroll_up();
    } else {
        /* byte_off is word offset * 2; convert to cell index */
        size_t idx = (size_t)byte_off / 2;
        vga_buf[idx] = (uint16_t)c | ((uint16_t)color << 8);
    }
    return Val_unit;
}

CAMLprim value caml_vga_update_cursor(value v_x, value v_y) {
    /* Hardware cursor update via CRTC ports */
    uint16_t pos = (uint16_t)(Int_val(v_y) * VGA_W + Int_val(v_x));
    outb(0x3D4, 0x0F); outb(0x3D5, (uint8_t)(pos & 0xFF));
    outb(0x3D4, 0x0E); outb(0x3D5, (uint8_t)((pos >> 8) & 0xFF));
    return Val_unit;
}

CAMLprim value caml_serial_write(value v_str) {
    CAMLparam1(v_str);
    const char *str = String_val(v_str);
    serial_puts(str);
    CAMLreturn(Val_unit);
}

CAMLprim value caml_serial_getchar(value v_unit) {
    (void)v_unit;
    return Val_int((unsigned char)serial_getchar());
}

/* ══════════════════════════════════════════════════════════════════
   PS/2 Keyboard and Serial Terminal Hardware Driver
   ══════════════════════════════════════════════════════════════════ */

static int shift_down = 0;
static int ctrl_down  = 0;
static int alt_down   = 0;
static int caps_lock  = 0;
static int ext_code   = 0;

#define KEY_RING_SIZE 128
static int key_ring[KEY_RING_SIZE];
static int key_head = 0;
static int key_tail = 0;

static void key_push(int k) {
    int next = (key_head + 1) % KEY_RING_SIZE;
    if (next != key_tail) {
        key_ring[key_head] = k;
        key_head = next;
    }
}

static int key_pop(void) {
    if (key_head == key_tail) return 0;
    int k = key_ring[key_tail];
    key_tail = (key_tail + 1) % KEY_RING_SIZE;
    return k;
}

/* Complete standard US QWERTY Scan Code Set 1 Table */
static const char scancode_normal[128] = {
    /* 0x00 */ 0,   27,  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\b',
    /* 0x0F */ '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n',
    /* 0x1D */ 0,   'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`',
    /* 0x2A */ 0,   '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0,
    /* 0x37 */ '*', 0,   ' ',  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    /* 0x44 */ 0,   0,   0,   '7', '8', '9', '-', '4', '5', '6', '+', '1', '2',
    /* 0x51 */ '3', '0', '.',  0,   0,   0,   0,   0
};

static const char scancode_shifted[128] = {
    /* 0x00 */ 0,   27,  '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', '\b',
    /* 0x0F */ '\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\n',
    /* 0x1D */ 0,   'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~',
    /* 0x2A */ 0,   '|', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0,
    /* 0x37 */ '*', 0,   ' ',  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    /* 0x44 */ 0,   0,   0,   '7', '8', '9', '-', '4', '5', '6', '+', '1', '2',
    /* 0x51 */ '3', '0', '.',  0,   0,   0,   0,   0
};

/* Serial ANSI escape sequence decoder state */
static int serial_esc_state = 0;
static int serial_esc_param = 0;

static void poll_input_hardware(void) {
    /* 1. Poll PS/2 Keyboard port */
    while (inb(0x64) & 1) {
        uint8_t status = inb(0x64);
        if (!(status & 1)) break;
        uint8_t data = inb(0x60);

        /* Discard auxiliary mouse data */
        if (status & 0x20) {
            continue;
        }

        /* Extended scancode prefix */
        if (data == 0xE0) {
            ext_code = 1;
            continue;
        }

        if (ext_code) {
            ext_code = 0;
            if (data & 0x80) {
                /* Release of extended key */
                if (data == 0x9D) ctrl_down = 0;
                else if (data == 0xB8) alt_down = 0;
            } else {
                /* Press of extended key */
                switch (data) {
                    case 0x1D: ctrl_down = 1; break; /* Right Ctrl */
                    case 0x38: alt_down = 1;  break; /* Right Alt */
                    case 0x48: key_push(1001); break; /* Up */
                    case 0x50: key_push(1002); break; /* Down */
                    case 0x4B: key_push(1003); break; /* Left */
                    case 0x4D: key_push(1004); break; /* Right */
                    case 0x47: key_push(1005); break; /* Home */
                    case 0x4F: key_push(1006); break; /* End */
                    case 0x53: key_push(1007); break; /* Delete */
                    case 0x49: key_push(1008); break; /* PageUp */
                    case 0x51: key_push(1009); break; /* PageDown */
                    default: break;
                }
            }
            continue;
        }

        /* Break code (key release) for standard keys */
        if (data & 0x80) {
            if (data == 0xAA || data == 0xB6) {
                shift_down = 0;
            } else if (data == 0x9D) {
                ctrl_down = 0;
            } else if (data == 0xB8) {
                alt_down = 0;
            }
            continue;
        }

        /* Make code (key press) for standard keys */
        if (data == 0x2A || data == 0x36) {
            shift_down = 1;
            continue;
        }
        if (data == 0x1D) {
            ctrl_down = 1;
            continue;
        }
        if (data == 0x38) {
            alt_down = 1;
            continue;
        }
        if (data == 0x3A) {
            caps_lock = !caps_lock;
            continue;
        }

        /* If Alt is down, don't emit garbage text */
        if (alt_down) {
            continue;
        }

        /* If Ctrl is down, only emit supported control keys */
        if (ctrl_down) {
            char base = scancode_normal[data & 0x7F];
            if (base == 'c' || base == 'C') key_push(3);       /* Ctrl+C */
            else if (base == 'd' || base == 'D') key_push(4);  /* Ctrl+D */
            else if (base == 'l' || base == 'L') key_push(12); /* Ctrl+L */
            else if (base == 'a' || base == 'A') key_push(1);  /* Ctrl+A */
            else if (base == 'e' || base == 'E') key_push(5);  /* Ctrl+E */
            else if (base == 'u' || base == 'U') key_push(21); /* Ctrl+U */
            else if (base == 'k' || base == 'K') key_push(11); /* Ctrl+K */
            else if (base == 'w' || base == 'W') key_push(23); /* Ctrl+W */
            continue;
        }

        /* Normal typing */
        char base = scancode_normal[data & 0x7F];
        int is_alpha = (base >= 'a' && base <= 'z');
        int shift_eff = is_alpha ? (shift_down ^ caps_lock) : shift_down;
        char c = shift_eff ? scancode_shifted[data & 0x7F] : scancode_normal[data & 0x7F];
        if (c) {
            key_push((unsigned char)c);
        }
    }

    /* 2. Poll Serial COM1 input with ANSI escape sequence parser */
    while (serial_received()) {
        char sc = serial_getchar();
        if (!sc) continue;

        if (serial_esc_state == 0) {
            if (sc == 27) {
                serial_esc_state = 1;
            } else if (sc == '\r') {
                key_push('\n');
            } else if (sc == 127) {
                key_push('\b');
            } else {
                key_push((unsigned char)sc);
            }
        } else if (serial_esc_state == 1) {
            if (sc == '[') {
                serial_esc_state = 2;
                serial_esc_param = 0;
            } else if (sc == 'O') {
                serial_esc_state = 3;
            } else {
                key_push(27);
                key_push((unsigned char)sc);
                serial_esc_state = 0;
            }
        } else if (serial_esc_state == 2) {
            if (sc >= '0' && sc <= '9') {
                serial_esc_param = serial_esc_param * 10 + (sc - '0');
            } else if (sc == '~') {
                switch (serial_esc_param) {
                    case 1: key_push(1005); break; /* Home */
                    case 3: key_push(1007); break; /* Delete */
                    case 4: key_push(1006); break; /* End */
                    case 5: key_push(1008); break; /* PageUp */
                    case 6: key_push(1009); break; /* PageDown */
                    default: break;
                }
                serial_esc_state = 0;
            } else {
                switch (sc) {
                    case 'A': key_push(1001); break; /* Up */
                    case 'B': key_push(1002); break; /* Down */
                    case 'C': key_push(1004); break; /* Right */
                    case 'D': key_push(1003); break; /* Left */
                    case 'H': key_push(1005); break; /* Home */
                    case 'F': key_push(1006); break; /* End */
                    default: break;
                }
                serial_esc_state = 0;
            }
        } else if (serial_esc_state == 3) {
            switch (sc) {
                case 'H': key_push(1005); break; /* Home */
                case 'F': key_push(1006); break; /* End */
                default: break;
            }
            serial_esc_state = 0;
        }
    }
}

CAMLprim value caml_poll_hardware(value v_unit) {
    (void)v_unit;
    poll_input_hardware();
    return Val_unit;
}

CAMLprim value caml_has_input(value v_unit) {
    (void)v_unit;
    poll_input_hardware();
    return Val_bool(key_head != key_tail);
}

CAMLprim value caml_get_input(value v_unit) {
    (void)v_unit;
    poll_input_hardware();
    return Val_int(key_pop());
}

CAMLprim value caml_cpu_halt(value v_unit) {
    (void)v_unit;
    for (int i = 0; i < 1000; i++) {
        __asm__ __volatile__("pause");
    }
    return Val_unit;
}

CAMLprim value caml_reboot(value v_unit) {
    (void)v_unit;
    /* Reset via 8042 keyboard controller */
    outb(0x64, 0xFE);
    /* Fallback triple-fault */
    uint8_t zero_idt[6] = {0};
    __asm__ __volatile__("lidt %0; int3" : : "m"(zero_idt));
    return Val_unit;
}

CAMLprim value caml_poweroff(value v_unit) {
    (void)v_unit;
    /* QEMU modern ACPI shutdown */
    outw(0x604, 0x2000);
    /* Bochs / older QEMU shutdown */
    outw(0xB004, 0x2000);
    /* VirtualBox shutdown */
    outw(0x4004, 0x3400);
    /* Cloud-hypervisor / QEMU debug exit */
    outb(0x501, 0x31);
    while (1) {
        __asm__ __volatile__("cli; hlt");
    }
    return Val_unit;
}

CAMLprim value caml_rdtsc(value v_unit) {
    (void)v_unit;
    uint32_t lo, hi;
    __asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
    uint64_t val = ((uint64_t)hi << 32) | lo;
    return caml_copy_int64(val);
}

CAMLprim value caml_vga_print(value v_str) {
    CAMLparam1(v_str);
    const char *str = String_val(v_str);
    vga_puts(str);
    CAMLreturn(Val_unit);
}

extern void vga_clear(void);

CAMLprim value caml_vga_clear(value v_unit) {
    (void)v_unit;
    vga_clear();
    return Val_unit;
}

/* Stubs kept for backward ABI compatibility */
CAMLprim value caml_mouse_get_x(value v_unit) { (void)v_unit; return Val_int(0); }
CAMLprim value caml_mouse_get_y(value v_unit) { (void)v_unit; return Val_int(0); }
CAMLprim value caml_mouse_get_buttons(value v_unit) { (void)v_unit; return Val_int(0); }

extern void caml_startup(char **argv);

/* C entry point called from boot.S long_mode_entry */
void kernel_main_c(uint32_t magic, uint32_t mb_info_addr) {
    (void)magic;
    (void)mb_info_addr;

    serial_init();
    serial_puts("[OCamlOS C Runtime] Serial initialized.\n");
    vga_init();
    serial_puts("[OCamlOS C Runtime] VGA text console initialized.\n");
    serial_puts("[OCamlOS C Runtime] Starting OCaml Runtime...\n");

    char *argv[] = { "ocamlos", NULL };
    caml_startup(argv);

    serial_puts("[OCamlOS C Runtime] Execution returned from OCaml startup.\n");
    while (1) {
        __asm__ __volatile__("cli; hlt");
    }
}
