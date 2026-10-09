/* Sample the main executable without changing its Rust code or Ruby workload. */
#define _GNU_SOURCE
#include <link.h>
#include <stddef.h>
#include <sys/gmon.h>

static int sample_executable(struct dl_phdr_info *info, size_t size, void *data) {
    (void)size;
    (void)data;
    if (info->dlpi_name[0] != '\0') return 0;
    unsigned long low = ~0UL, high = 0;
    for (size_t index = 0; index < info->dlpi_phnum; index++) {
        const ElfW(Phdr) *header = &info->dlpi_phdr[index];
        if (header->p_type != PT_LOAD || !(header->p_flags & PF_X)) continue;
        unsigned long start = info->dlpi_addr + header->p_vaddr;
        unsigned long end = start + header->p_memsz;
        if (start < low) low = start;
        if (end > high) high = end;
    }
    if (high > low) monstartup(low, high);
    return 1;
}

__attribute__((constructor)) static void start_sampling(void) {
    dl_iterate_phdr(sample_executable, NULL);
}

__attribute__((destructor)) static void stop_sampling(void) {
    _mcleanup();
}
