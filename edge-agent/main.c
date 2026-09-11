#include <math.h>
#include <stdio.h>

int main(void)
{
    FILE *file = fopen("/proc/uptime", "r");
    if (file == NULL) {
        perror("open /proc/uptime");
        return 1;
    }

    /* 第一列是本次启动以来的秒数；第二列暂时不用。 */
    double uptime_s = 0.0;
    int fields = fscanf(file, "%lf", &uptime_s);
    int close_result = fclose(file);

    if (fields != 1 || !isfinite(uptime_s) || uptime_s < 0.0) {
        fputs("invalid uptime value\n", stderr);
        return 1;
    }
    if (close_result != 0) {
        perror("close /proc/uptime");
        return 1;
    }

    if (printf("{\"version\":\"0.1.0\",\"uptime_s\":%.2f}\n", uptime_s) < 0 ||
        fflush(stdout) == EOF) {
        perror("write stdout");
        return 1;
    }
    return 0;
}
