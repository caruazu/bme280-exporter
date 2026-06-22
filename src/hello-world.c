#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_TEXTFILE_DIR "/var/lib/node_exporter/textfile_collector"
#define OUTPUT_FILENAME      "bme280_dummy.prom"

int main(void)
{
    const char *dir = getenv("TEXTFILE_DIR");
    if (!dir || dir[0] == '\0')
        dir = DEFAULT_TEXTFILE_DIR;

    char path[512];
    int n = snprintf(path, sizeof(path), "%s/%s", dir, OUTPUT_FILENAME);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        fprintf(stderr, "bme280-reader: path too long\n");
        return 1;
    }

    FILE *f = fopen(path, "w");
    if (!f) {
        fprintf(stderr, "bme280-reader: cannot open %s: %s\n", path, strerror(errno));
        return 1;
    }

    fprintf(f,
        "# HELP bme280_up 1 if the last read was successful, 0 otherwise\n"
        "# TYPE bme280_up gauge\n"
        "bme280_up 1\n"
        "# HELP bme280_temperature_celsius Temperature in Celsius (dummy)\n"
        "# TYPE bme280_temperature_celsius gauge\n"
        "bme280_temperature_celsius 0\n"
        "# HELP bme280_humidity_percent Relative humidity in percent (dummy)\n"
        "# TYPE bme280_humidity_percent gauge\n"
        "bme280_humidity_percent 0\n"
        "# HELP bme280_pressure_hpa Atmospheric pressure in hPa (dummy)\n"
        "# TYPE bme280_pressure_hpa gauge\n"
        "bme280_pressure_hpa 0\n");

    if (fclose(f) != 0) {
        fprintf(stderr, "bme280-reader: write failed on %s: %s\n", path, strerror(errno));
        return 1;
    }

    return 0;
}
