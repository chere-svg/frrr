/* libc/stubs.c - Complete POSIX, Signal, Math, and C library stubs for OCaml runtime on bare-metal */

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>

/* Stack canary protection stub */
uintptr_t __stack_chk_guard = 0x595e9fbd94fda766ULL;

void __stack_chk_fail(void) {
    extern void abort(void);
    abort();
}

/* Errno stub */
static int global_errno = 0;
int *__errno_location(void) {
    return &global_errno;
}

char *strerror(int errnum) {
    (void)errnum;
    return "Unknown error";
}

/* Signal stubs */
typedef uint64_t sigset_t;

int __sigsetjmp(void *env, int savemask) { (void)env; (void)savemask; return 0; }
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset) { (void)how; (void)set; (void)oldset; return 0; }
int sigemptyset(sigset_t *set) { if (set) *set = 0; return 0; }
int sigaddset(sigset_t *set, int signum) { if (set) *set |= (1ULL << signum); return 0; }
int sigdelset(sigset_t *set, int signum) { if (set) *set &= ~(1ULL << signum); return 0; }
int sigismember(const sigset_t *set, int signum) { return set ? ((*set & (1ULL << signum)) != 0) : 0; }
int sigaction(int signum, const void *act, void *oldact) { (void)signum; (void)act; (void)oldact; return 0; }
int sigaltstack(const void *ss, void *old_ss) { (void)ss; (void)old_ss; return 0; }
long sysconf(int name) { (void)name; return 4096; }

/* File stream stubs */
void *stderr = (void*)1;
void *stdout = (void*)2;
void *stdin = (void*)3;

extern void serial_putchar(char c);

size_t fwrite(const void *ptr, size_t size, size_t nmemb, void *stream) {
    (void)stream;
    const char *p = (const char *)ptr;
    size_t total = size * nmemb;
    for (size_t i = 0; i < total; i++) {
        if (p[i] == '\n') serial_putchar('\r');
        serial_putchar(p[i]);
    }
    return nmemb;
}

int fputc(int c, void *stream) {
    (void)stream;
    if (c == '\n') serial_putchar('\r');
    serial_putchar((char)c);
    return c;
}

int fputs(const char *s, void *stream) {
    (void)stream;
    while (*s) {
        if (*s == '\n') serial_putchar('\r');
        serial_putchar(*s);
        s++;
    }
    return 0;
}

int fflush(void *stream) {
    (void)stream;
    return 0;
}

int __vfprintf_chk(void *fp, int flag, const char *format, va_list ap) {
    (void)flag;
    for (const char *p = format; *p; p++) {
        if (*p == '%' && *(p + 1) == 's') {
            const char *s = va_arg(ap, const char *);
            if (s) fputs(s, fp);
            else fputs("(null)", fp);
            p++;
        } else {
            char buf[2] = {*p, '\0'};
            fputs(buf, fp);
        }
    }
    return 0;
}

int __fprintf_chk(void *fp, int flag, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = __vfprintf_chk(fp, flag, format, ap);
    va_end(ap);
    return ret;
}

static void int_to_str(char *buf, size_t bsize, int64_t val, int base, int is_signed) {
    char tmp[32];
    int pos = 0;
    uint64_t uval;
    if (is_signed && val < 0) {
        uval = (uint64_t)(-val);
    } else {
        uval = (uint64_t)val;
    }
    if (uval == 0) {
        tmp[pos++] = '0';
    } else {
        while (uval > 0 && pos < 30) {
            int rem = uval % base;
            tmp[pos++] = (rem < 10) ? ('0' + rem) : ('a' + rem - 10);
            uval /= base;
        }
    }
    size_t out = 0;
    if (is_signed && val < 0 && out + 1 < bsize) {
        buf[out++] = '-';
    }
    while (pos > 0 && out + 1 < bsize) {
        buf[out++] = tmp[--pos];
    }
    buf[out] = '\0';
}

int __vsnprintf_chk(char *str, size_t maxlen, int flag, size_t slen, const char *format, va_list ap) {
    (void)flag; (void)slen;
    if (!str || maxlen == 0) return 0;
    size_t out = 0;
    for (const char *p = format; *p && out + 1 < maxlen; ) {
        if (*p == '%') {
            p++;
            int is_long = 0;
            if (*p == 'l') { is_long = 1; p++; }
            if (*p == 's') {
                const char *s = va_arg(ap, const char *);
                if (!s) s = "(null)";
                while (*s && out + 1 < maxlen) str[out++] = *s++;
                p++;
            } else if (*p == 'd' || *p == 'i') {
                int64_t v = is_long ? va_arg(ap, long) : va_arg(ap, int);
                char num_buf[32];
                int_to_str(num_buf, sizeof(num_buf), v, 10, 1);
                for (char *nb = num_buf; *nb && out + 1 < maxlen; nb++) str[out++] = *nb;
                p++;
            } else if (*p == 'u') {
                uint64_t v = is_long ? va_arg(ap, unsigned long) : va_arg(ap, unsigned int);
                char num_buf[32];
                int_to_str(num_buf, sizeof(num_buf), (int64_t)v, 10, 0);
                for (char *nb = num_buf; *nb && out + 1 < maxlen; nb++) str[out++] = *nb;
                p++;
            } else if (*p == 'x' || *p == 'p') {
                uint64_t v = is_long ? va_arg(ap, unsigned long) : va_arg(ap, unsigned int);
                char num_buf[32];
                int_to_str(num_buf, sizeof(num_buf), (int64_t)v, 16, 0);
                for (char *nb = num_buf; *nb && out + 1 < maxlen; nb++) str[out++] = *nb;
                p++;
            } else if (*p == 'c') {
                char c = (char)va_arg(ap, int);
                str[out++] = c;
                p++;
            } else if (*p == '%') {
                str[out++] = '%';
                p++;
            } else {
                str[out++] = '%';
                if (out + 1 < maxlen && *p) str[out++] = *p++;
            }
        } else {
            str[out++] = *p++;
        }
    }
    str[out] = '\0';
    return (int)out;
}

int __snprintf_chk(char *str, size_t maxlen, int flag, size_t slen, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = __vsnprintf_chk(str, maxlen, flag, slen, format, ap);
    va_end(ap);
    return ret;
}

int __isoc99_sscanf(const char *str, const char *format, ...) {
    (void)str; (void)format;
    return 0;
}

int __isoc23_sscanf(const char *str, const char *format, ...) {
    (void)str; (void)format;
    return 0;
}

double trunc(double x) {
    return (double)(long long)x;
}

extern void *memmove(void *dest, const void *src, size_t n);
void *__memmove_chk(void *dest, const void *src, size_t len, size_t destlen) {
    (void)destlen;
    return memmove(dest, src, len);
}

extern void *memcpy(void *dest, const void *src, size_t n);
void *__memcpy_chk(void *dest, const void *src, size_t len, size_t destlen) {
    (void)destlen;
    return memcpy(dest, src, len);
}

/* Memory allocation / mmap stubs using early bump allocator */
extern void *malloc(size_t size);

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, int64_t offset) {
    (void)addr; (void)prot; (void)flags; (void)fd; (void)offset;
    return malloc(length);
}

int munmap(void *addr, size_t length) {
    (void)addr; (void)length;
    return 0;
}

/* Math stubs */
double fmin(double x, double y) { return x < y ? x : y; }
double fmod(double x, double y) { (void)y; return x; }
double floor(double x) { return x; }
double ceil(double x) { return x; }
double tanh(double x) { return x; }
double tan(double x) { return x; }
double sqrt(double x) { return x; }
double sinh(double x) { return x; }
double sin(double x) { return x; }
double log10(double x) { return x; }
double log(double x) { return x; }
double cosh(double x) { return x; }
double cos(double x) { return x; }
double atan2(double y, double x) { (void)y; return x; }
double atan(double x) { return x; }
double asin(double x) { return x; }
double acos(double x) { return x; }
double exp(double x) { return x; }
double pow(double x, double y) { (void)y; return x; }
double copysign(double x, double y) { (void)y; return x; }
double exp2(double x) { return x; }
double round(double x) { return x; }
double nextafter(double x, double y) { (void)y; return x; }
double fma(double x, double y, double z) { return x * y + z; }
double frexp(double x, int *exp) { if (exp) *exp = 0; return x; }
double ldexp(double x, int exp) { (void)exp; return x; }
double log2(double x) { return x; }
double modf(double x, double *iptr) { if (iptr) *iptr = 0; return x; }
double cbrt(double x) { return x; }
double asinh(double x) { return x; }
double acosh(double x) { return x; }
double atanh(double x) { return x; }
double hypot(double x, double y) { (void)y; return x; }
double expm1(double x) { return x; }
double log1p(double x) { return x; }
double erf(double x) { return x; }
double erfc(double x) { return x; }

/* System calls and environment stubs */
char *getenv(const char *name) { (void)name; return NULL; }
char *secure_getenv(const char *name) { (void)name; return NULL; }
int stat64(const char *pathname, void *statbuf) { (void)pathname; (void)statbuf; return -1; }
int readlink(const char *pathname, char *buf, size_t bufsiz) { (void)pathname; (void)buf; (void)bufsiz; return -1; }
int ioctl(int fd, unsigned long request, ...) { (void)fd; (void)request; return -1; }
int open64(const char *pathname, int flags, ...) { (void)pathname; (void)flags; return -1; }
int close(int fd) { (void)fd; return 0; }
int64_t lseek64(int fd, int64_t offset, int whence) { (void)fd; (void)offset; (void)whence; return 0; }
int read(int fd, void *buf, size_t count) { (void)fd; (void)buf; (void)count; return -1; }
int write(int fd, const void *buf, size_t count) {
    (void)fd;
    const char *p = (const char *)buf;
    for (size_t i = 0; i < count; i++) {
        if (p[i] == '\n') serial_putchar('\r');
        serial_putchar(p[i]);
    }
    return count;
}
int unlink(const char *pathname) { (void)pathname; return -1; }
int rename(const char *oldpath, const char *newpath) { (void)oldpath; (void)newpath; return -1; }
int chdir(const char *path) { (void)path; return -1; }
int mkdir(const char *pathname, unsigned int mode) { (void)pathname; (void)mode; return -1; }
int rmdir(const char *pathname) { (void)pathname; return -1; }
char *getcwd(char *buf, size_t size) { (void)size; if (buf) buf[0] = '\0'; return buf; }
int isatty(int fd) { (void)fd; return 0; }
int system(const char *command) { (void)command; return -1; }
int getrusage(int who, void *usage) { (void)who; (void)usage; return 0; }
int gettimeofday(void *tv, void *tz) { (void)tv; (void)tz; return 0; }
int getpid(void) { return 1; }
int getppid(void) { return 0; }

/* Locale stubs */
void *newlocale(int category_mask, const char *locale, void *base) { (void)category_mask; (void)locale; (void)base; return NULL; }
void freelocale(void *locobj) { (void)locobj; }
void *uselocale(void *newloc) { (void)newloc; return NULL; }
double strtod_l(const char *nptr, char **endptr, void *loc) { (void)loc; (void)endptr; (void)nptr; return 0.0; }
long __isoc23_strtol(const char *nptr, char **endptr, int base) { (void)nptr; (void)endptr; (void)base; return 0; }

/* Dynamic linker stubs */
void *dlopen(const char *filename, int flag) { (void)filename; (void)flag; return NULL; }
int dlclose(void *handle) { (void)handle; return 0; }
void *dlsym(void *handle, const char *symbol) { (void)handle; (void)symbol; return NULL; }
char *dlerror(void) { return "Dynamic linking disabled in bare-metal OCamlOS"; }

/* Directory stubs */
void *opendir(const char *name) { (void)name; return NULL; }
void *readdir64(void *dirp) { (void)dirp; return NULL; }
int closedir(void *dirp) { (void)dirp; return 0; }
