/*
 * Script Name: readVoltage.c
 * Description:
 *   Reads the bus voltage from an INA226 power monitor over I2C and calculates
 *    the battery percentage based on a predefined voltage range (6.8V to 8.1V).
 *   Outputs the percentage to stdout.
 */

// all code written by me with minimal AI assistance, comments added using AI
// and verified by me

#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

/**
 * @brief Reads a 16-bit value from a specific INA226 register.
 *
 * @param fd File descriptor for the I2C device.
 * @param reg The register address to read from.
 * @param value Pointer to store the 16-bit retrieved value.
 * @return int 0 on success, -1 on failure.
 */
int read_register(int fd, uint8_t reg, uint16_t *value) {
  if (write(fd, &reg, 1) != 1) {
    perror("Failed to write register address");
    return -1;
  }

  uint8_t data[2];
  if (read(fd, data, 2) != 2) {
    perror("Failed to read data");
    return -1;
  }

  // Combine MSB and LSB
  *value = ((uint16_t)data[0] << 8) | data[1];
  return 0;
}

/**
 * @brief Main execution for reading battery voltage and calculating percentage.
 *
 * Connects to the INA226 sensor on I2C bus 3, reads the bus voltage,
 * maps it to a 0-100% range, and prints the result.
 */
int main(void) {
  // --- Bus 3 (GPIO 4 & 5) ---
  const char *i2c_device = "/dev/i2c-3";

  // --- Address 0x40 (Detected by your scan) ---
  int i2c_addr = 0x40;

  int fd = open(i2c_device, O_RDWR);
  if (fd < 0) {
    perror("Failed to open I2C device");
    return 1;
  }

  if (ioctl(fd, I2C_SLAVE, i2c_addr) < 0) {
    perror("Failed to set I2C address");
    close(fd);
    return 1;
  }

  // INA226 Bus Voltage Register is 0x02
  uint16_t busRaw;
  if (read_register(fd, 0x02, &busRaw) < 0) {
    close(fd);
    return 1;
  }
  close(fd);

  // INA226 LSB is 1.25mV
  double volts = busRaw * 1.25e-3;
  double v_effective = volts;

  // Battery percentage calculation
  const double min_volts = 6.8;
  const double max_volts = 8.1;
  double percent;

  if (v_effective <= min_volts) {
    percent = 0.0;
  } else if (v_effective >= max_volts) {
    percent = 100.0;
  } else {
    percent = (v_effective - min_volts) / (max_volts - min_volts) * 100.0;
  }

  printf("%.2f\n", percent);
  return 0;
}

// all code written by me with minimal AI assistance, comments added using AI
// and verified by me
