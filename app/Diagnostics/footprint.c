// Read-only, external process observation. No task port, root access or UI automation.
#include <errno.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

static double monotonic(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: footprint PID SECONDS\n");
        return 2;
    }
    char *end;
    long pid = strtol(argv[1], &end, 10);
    if (*end || pid <= 0 || pid > INT32_MAX) return 2;
    long seconds = strtol(argv[2], &end, 10);
    if (*end || seconds < 1 || seconds > 3600) return 2;
    struct rusage_info_v4 first = {0}, current = {0};
    if (proc_pid_rusage((pid_t)pid, RUSAGE_INFO_V4, (rusage_info_t *)&first)) {
        fprintf(stderr, "proc_pid_rusage: %s\n", strerror(errno));
        return 1;
    }
    uint64_t peak = first.ri_phys_footprint;
    double start = monotonic();
    for (long i = 0; i < seconds; ++i) {
        struct timespec remaining = {1, 0};
        while (nanosleep(&remaining, &remaining) && errno == EINTR) {}
        if (proc_pid_rusage((pid_t)pid, RUSAGE_INFO_V4, (rusage_info_t *)&current)) return 1;
        if (current.ri_proc_start_abstime != first.ri_proc_start_abstime) return 1;
        if (current.ri_phys_footprint > peak) peak = current.ri_phys_footprint;
    }
    double elapsed = monotonic() - start;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    // rusage_info CPU counters use Mach absolute time, including on Apple Silicon.
    double cpu = ((current.ri_user_time - first.ri_user_time) +
                  (current.ri_system_time - first.ri_system_time)) *
                  ((double)timebase.numer / timebase.denom) / 1e9;
    printf("{\"pid\":%ld,\"seconds\":%.3f,\"cpu_seconds\":%.6f,\"cpu_percent_one_core\":%.3f,"
           "\"footprint_start_mib\":%.3f,\"footprint_end_mib\":%.3f,\"footprint_peak_mib\":%.3f,"
           "\"idle_wakeups_per_second\":%.3f,\"interrupt_wakeups_per_second\":%.3f,"
           "\"disk_read_bytes\":%llu,\"disk_written_bytes\":%llu}\n",
           pid, elapsed, cpu, 100 * cpu / elapsed,
           first.ri_phys_footprint / 1048576.0, current.ri_phys_footprint / 1048576.0, peak / 1048576.0,
           (current.ri_pkg_idle_wkups - first.ri_pkg_idle_wkups) / elapsed,
           (current.ri_interrupt_wkups - first.ri_interrupt_wkups) / elapsed,
           (unsigned long long)(current.ri_diskio_bytesread - first.ri_diskio_bytesread),
           (unsigned long long)(current.ri_diskio_byteswritten - first.ri_diskio_byteswritten));
    return 0;
}
