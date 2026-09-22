/* runtime/freestanding.c - Freestanding C runtime stubs for OCaml runtime */

#include <stddef.h>
#include <stdint.h>

/* Early kernel heap bump allocator */
#define HEAP_SIZE (16 * 1024 * 1024) /* 16 MB early heap */
static uint8_t early_heap[HEAP_SIZE];
static size_t heap_offset = 0;

void *malloc(size_t size) {
    /* Align allocations to 16 bytes */
    size_t aligned_size = (size + 15) & ~15;
    if (heap_offset + aligned_size > HEAP_SIZE) {
        return NULL; /* Out of memory */
    }
    void *ptr = &early_heap[heap_offset];
    heap_offset += aligned_size;
    return ptr;
}

void free(void *ptr) {
    (void)ptr; /* Bump allocator does not free early allocations */
}

void *calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *ptr = malloc(total);
    if (ptr) {
        uint8_t *p = (uint8_t *)ptr;
        for (size_t i = 0; i < total; i++) {
            p[i] = 0;
        }
    }
    return ptr;
}

void *realloc(void *ptr, size_t size) {
    if (!ptr) return malloc(size);
    void *new_ptr = malloc(size);
    if (new_ptr && ptr) {
        /* Conservative copy of up to size bytes */
        uint8_t *src = (uint8_t *)ptr;
        uint8_t *dst = (uint8_t *)new_ptr;
        for (size_t i = 0; i < size; i++) {
            dst[i] = src[i];
        }
    }
    return new_ptr;
}

void *memcpy(void *dest, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dest;
    const uint8_t *s = (const uint8_t *)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dest;
}

void *memset(void *s, int c, size_t n) {
    uint8_t *p = (uint8_t *)s;
    for (size_t i = 0; i < n; i++) {
        p[i] = (uint8_t)c;
    }
    return s;
}

void *memmove(void *dest, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dest;
    const uint8_t *s = (const uint8_t *)src;
    if (d < s) {
        for (size_t i = 0; i < n; i++) d[i] = s[i];
    } else {
        for (size_t i = n; i > 0; i--) d[i - 1] = s[i - 1];
    }
    return dest;
}

int memcmp(const void *s1, const void *s2, size_t n) {
    const uint8_t *p1 = (const uint8_t *)s1;
    const uint8_t *p2 = (const uint8_t *)s2;
    for (size_t i = 0; i < n; i++) {
        if (p1[i] != p2[i]) return p1[i] - p2[i];
    }
    return 0;
}

size_t strlen(const char *s) {
    size_t len = 0;
    while (s[len]) len++;
    return len;
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
    while (n && *s1 && (*s1 == *s2)) {
        s1++;
        s2++;
        n--;
    }
    if (n == 0) return 0;
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

extern void serial_putchar(char c);

void abort(void) {
    const char *msg = "\n[OCamlOS PANIC] abort() called!\n";
    for (size_t i = 0; msg[i]; i++) serial_putchar(msg[i]);
    while (1) {
        __asm__ __volatile__("cli; hlt");
    }
}

void exit(int status) {
    (void)status;
    abort();
}

/* Dummy signal/system hooks for OCaml runtime */
int raise(int sig) { (void)sig; return 0; }
