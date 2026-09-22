/* drivers/vga.c - ANSI-aware VGA 80x25 text mode driver with hardware cursor */

#include <stdint.h>
#include <stddef.h>
#include "../arch/x86_64/io.h"

#define VGA_BUFFER ((volatile uint16_t *)0xB8000)
#define VGA_WIDTH  80
#define VGA_HEIGHT 25

static size_t vga_row = 0;
static size_t vga_col = 0;

/* Active colors */
static uint8_t vga_fg = 0x07; /* Light grey */
static uint8_t vga_bg = 0x00; /* Black */
static int vga_bold   = 0;
static uint8_t vga_color = 0x07;

/* ANSI Parser State */
#define ANSI_STATE_NORMAL 0
#define ANSI_STATE_ESC    1
#define ANSI_STATE_CSI    2

static int ansi_state = ANSI_STATE_NORMAL;
#define ANSI_MAX_PARAMS 8
static int ansi_params[ANSI_MAX_PARAMS];
static int ansi_param_idx = 0;
static int ansi_has_param = 0;

static uint16_t vga_entry(unsigned char uc, uint8_t color) {
    return (uint16_t)uc | ((uint16_t)color << 8);
}

static void vga_update_color(void) {
    uint8_t effective_fg = vga_fg;
    if (vga_bold && effective_fg < 8) {
        effective_fg |= 0x08; /* Brighten foreground on bold */
    }
    vga_color = (vga_bg << 4) | (effective_fg & 0x0F);
}

static void vga_update_hw_cursor(void) {
    uint16_t pos = (uint16_t)(vga_row * VGA_WIDTH + vga_col);
    outb(0x3D4, 0x0F);
    outb(0x3D5, (uint8_t)(pos & 0xFF));
    outb(0x3D4, 0x0E);
    outb(0x3D5, (uint8_t)((pos >> 8) & 0xFF));
}

static void vga_scroll(void) {
    for (size_t y = 1; y < VGA_HEIGHT; y++) {
        for (size_t x = 0; x < VGA_WIDTH; x++) {
            VGA_BUFFER[(y - 1) * VGA_WIDTH + x] = VGA_BUFFER[y * VGA_WIDTH + x];
        }
    }
    for (size_t x = 0; x < VGA_WIDTH; x++) {
        VGA_BUFFER[(VGA_HEIGHT - 1) * VGA_WIDTH + x] = vga_entry(' ', vga_color);
    }
    vga_row = VGA_HEIGHT - 1;
}

void vga_clear(void) {
    vga_row = 0;
    vga_col = 0;
    for (size_t y = 0; y < VGA_HEIGHT; y++) {
        for (size_t x = 0; x < VGA_WIDTH; x++) {
            VGA_BUFFER[y * VGA_WIDTH + x] = vga_entry(' ', vga_color);
        }
    }
    vga_update_hw_cursor();
}

void vga_init(void) {
    vga_fg = 0x07;
    vga_bg = 0x00;
    vga_bold = 0;
    vga_update_color();
    vga_clear();

    /* Enable hardware blinking underline cursor */
    outb(0x3D4, 0x0A);
    outb(0x3D5, (inb(0x3D5) & 0xC0) | 13); /* Cursor start scanline */
    outb(0x3D4, 0x0B);
    outb(0x3D5, (inb(0x3D5) & 0xE0) | 15); /* Cursor end scanline */
    vga_update_hw_cursor();
}

/* SGR: Handle Select Graphic Rendition (Colors & Attributes) */
static void handle_sgr(void) {
    int count = ansi_has_param ? (ansi_param_idx + 1) : 1;
    for (int i = 0; i < count; i++) {
        int code = ansi_params[i];
        switch (code) {
            case 0: /* Reset */
                vga_fg = 0x07;
                vga_bg = 0x00;
                vga_bold = 0;
                break;
            case 1: /* Bold */
                vga_bold = 1;
                break;
            case 2: /* Dim */
            case 22: /* Normal intensity */
                vga_bold = 0;
                break;

            /* Standard Foreground Colors */
            case 30: vga_fg = 0x00; break; /* Black */
            case 31: vga_fg = 0x04; break; /* Red */
            case 32: vga_fg = 0x02; break; /* Green */
            case 33: vga_fg = 0x06; break; /* Yellow / Brown */
            case 34: vga_fg = 0x01; break; /* Blue */
            case 35: vga_fg = 0x05; break; /* Magenta */
            case 36: vga_fg = 0x03; break; /* Cyan */
            case 37: vga_fg = 0x07; break; /* White / Light Grey */
            case 39: vga_fg = 0x07; break; /* Default FG */

            /* Standard Background Colors */
            case 40: vga_bg = 0x00; break; /* Black */
            case 41: vga_bg = 0x04; break; /* Red */
            case 42: vga_bg = 0x02; break; /* Green */
            case 43: vga_bg = 0x06; break; /* Yellow */
            case 44: vga_bg = 0x01; break; /* Blue */
            case 45: vga_bg = 0x05; break; /* Magenta */
            case 46: vga_bg = 0x03; break; /* Cyan */
            case 47: vga_bg = 0x07; break; /* White */
            case 49: vga_bg = 0x00; break; /* Default BG */

            /* Bright Foreground Colors (AIXterm / Modern ANSI) */
            case 90: vga_fg = 0x08; break; /* Dark Grey / Bright Black */
            case 91: vga_fg = 0x0C; break; /* Bright Red */
            case 92: vga_fg = 0x0A; break; /* Bright Green */
            case 93: vga_fg = 0x0E; break; /* Bright Yellow */
            case 94: vga_fg = 0x09; break; /* Bright Blue */
            case 95: vga_fg = 0x0D; break; /* Bright Magenta */
            case 96: vga_fg = 0x0B; break; /* Bright Cyan */
            case 97: vga_fg = 0x0F; break; /* Bright White */

            /* Bright Background Colors */
            case 100: vga_bg = 0x08; break;
            case 101: vga_bg = 0x0C; break;
            case 102: vga_bg = 0x0A; break;
            case 103: vga_bg = 0x0E; break;
            case 104: vga_bg = 0x09; break;
            case 105: vga_bg = 0x0D; break;
            case 106: vga_bg = 0x0B; break;
            case 107: vga_bg = 0x0F; break;

            default:
                break;
        }
    }
    vga_update_color();
}

void vga_putchar(char c) {
    if (ansi_state == ANSI_STATE_NORMAL) {
        if (c == '\027') {
            ansi_state = ANSI_STATE_ESC;
            return;
        }

        switch (c) {
            case '\r':
                vga_col = 0;
                break;

            case '\n':
                vga_col = 0;
                vga_row++;
                if (vga_row >= VGA_HEIGHT) {
                    vga_scroll();
                }
                break;

            case '\b':
                if (vga_col > 0) {
                    vga_col--;
                    VGA_BUFFER[vga_row * VGA_WIDTH + vga_col] = vga_entry(' ', vga_color);
                }
                break;

            case '\t':
                vga_col = (vga_col + 8) & ~7;
                if (vga_col >= VGA_WIDTH) {
                    vga_col = 0;
                    vga_row++;
                    if (vga_row >= VGA_HEIGHT) {
                        vga_scroll();
                    }
                }
                break;

            default:
                if ((unsigned char)c >= 32) {
                    VGA_BUFFER[vga_row * VGA_WIDTH + vga_col] = vga_entry(c, vga_color);
                    vga_col++;
                    if (vga_col >= VGA_WIDTH) {
                        vga_col = 0;
                        vga_row++;
                        if (vga_row >= VGA_HEIGHT) {
                            vga_scroll();
                        }
                    }
                }
                break;
        }
    } else if (ansi_state == ANSI_STATE_ESC) {
        if (c == '[') {
            ansi_state = ANSI_STATE_CSI;
            ansi_param_idx = 0;
            ansi_has_param = 0;
            for (int i = 0; i < ANSI_MAX_PARAMS; i++) {
                ansi_params[i] = 0;
            }
        } else {
            ansi_state = ANSI_STATE_NORMAL;
        }
    } else if (ansi_state == ANSI_STATE_CSI) {
        if (c >= '0' && c <= '9') {
            ansi_params[ansi_param_idx] = ansi_params[ansi_param_idx] * 10 + (c - '0');
            ansi_has_param = 1;
        } else if (c == ';') {
            if (ansi_param_idx < ANSI_MAX_PARAMS - 1) {
                ansi_param_idx++;
                ansi_params[ansi_param_idx] = 0;
            }
        } else {
            /* Command terminator character */
            switch (c) {
                case 'm': /* SGR Colors */
                    handle_sgr();
                    break;

                case 'J': /* Clear Screen */
                    if (ansi_params[0] == 2 || !ansi_has_param) {
                        vga_clear();
                    }
                    break;

                case 'K': /* Clear in Line */
                    /* 2K or 0K: clear entire current line */
                    for (size_t x = 0; x < VGA_WIDTH; x++) {
                        VGA_BUFFER[vga_row * VGA_WIDTH + x] = vga_entry(' ', vga_color);
                    }
                    break;

                case 'H':
                case 'f': /* Cursor position */
                    if (!ansi_has_param) {
                        vga_row = 0;
                        vga_col = 0;
                    } else {
                        int r = ansi_params[0] > 0 ? ansi_params[0] - 1 : 0;
                        int col = (ansi_param_idx > 0 && ansi_params[1] > 0) ? ansi_params[1] - 1 : 0;
                        if (r >= (int)VGA_HEIGHT) r = VGA_HEIGHT - 1;
                        if (col >= (int)VGA_WIDTH) col = VGA_WIDTH - 1;
                        vga_row = (size_t)r;
                        vga_col = (size_t)col;
                    }
                    break;

                case 'D': { /* Cursor Left */
                    int n = ansi_has_param ? ansi_params[0] : 1;
                    if ((int)vga_col >= n) vga_col -= n;
                    else vga_col = 0;
                    break;
                }

                case 'C': { /* Cursor Right */
                    int n = ansi_has_param ? ansi_params[0] : 1;
                    vga_col += n;
                    if (vga_col >= VGA_WIDTH) vga_col = VGA_WIDTH - 1;
                    break;
                }

                case 'A': { /* Cursor Up */
                    int n = ansi_has_param ? ansi_params[0] : 1;
                    if ((int)vga_row >= n) vga_row -= n;
                    else vga_row = 0;
                    break;
                }

                case 'B': { /* Cursor Down */
                    int n = ansi_has_param ? ansi_params[0] : 1;
                    vga_row += n;
                    if (vga_row >= VGA_HEIGHT) vga_row = VGA_HEIGHT - 1;
                    break;
                }

                default:
                    break;
            }
            ansi_state = ANSI_STATE_NORMAL;
        }
    }

    vga_update_hw_cursor();
}

void vga_puts(const char *s) {
    while (*s) {
        vga_putchar(*s);
        s++;
    }
}
