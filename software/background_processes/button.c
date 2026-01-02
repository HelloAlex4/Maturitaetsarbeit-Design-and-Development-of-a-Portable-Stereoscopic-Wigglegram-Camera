/*
 * Script Name: button.c
 * Description:
 *   This script interfaces with the GPIO system on a Raspberry Pi using
 * libgpiod. It monitors a specific GPIO pin (configured as input with pull-up)
 * for button presses. When the button is pressed (signal low), it outputs
 * "BUTTON_PRESSED" to stdout. This is designed to be run as a background
 * process, with its output monitored by the main application (e.g., a Flutter
 * app).
 */
// all code written by me with minimal AI assistance, comments added using AI
// and verified by me

#include <gpiod.h>
#include <stdio.h>
#include <unistd.h>

// Configuration constants
#define CHIPNAME "/dev/gpiochip0" // The specific GPIO chip device path
#define LINE 6 // BCM GPIO pin number where the button is connected

/**
 * @brief Main execution loop for button monitoring.
 *
 * Initializes the GPIO chip and line, configures the input with a pull-up
 * resistor, and enters an infinite loop to poll the button state. Outputs a
 * message on press.
 *
 * @return int Exit status code.
 */
int main(void) {
  struct gpiod_chip *chip;
  struct gpiod_line *line;
  int val;

  // Open the GPIO chip to establish connection with the hardware
  chip = gpiod_chip_open(CHIPNAME);
  if (!chip) {
    perror("Open chip failed");
    return 1;
  }

  // Retrieve the handle for the specific GPIO line (pin) we want to monitor
  line = gpiod_chip_get_line(chip, LINE);
  if (!line) {
    perror("Get line failed");
    gpiod_chip_close(chip);
    return 1;
  }

  // Request the line to be used as an input.
  // GPIOD_LINE_REQUEST_FLAG_BIAS_PULL_UP ensures the pin is pulled high when
  // button is open. The label "button" identifies this consumer of the GPIO
  // line.
  if (gpiod_line_request_input_flags(
          line, "button", GPIOD_LINE_REQUEST_FLAG_BIAS_PULL_UP) < 0) {
    perror("Request line as input failed");
    gpiod_chip_close(chip);
    return 1;
  }

  // Disable stdout buffering.
  // This is critical so that the "BUTTON_PRESSED" message is sent immediately
  // to the listening parent process without waiting for a buffer flush.
  setbuf(stdout, NULL);

  printf("Press the button (CTRL+C to exit)\n");

  // Infinite loop to continuously poll the button state
  while (1) {
    // Read the current logic level of the line (0 or 1)
    val = gpiod_line_get_value(line);
    if (val < 0) {
      perror("Read line failed");
      break;
    }

    // Check for button press.
    // Since we use a pull-up resistor, the default state is High (1).
    // Pressing the button connects the pin to Ground, making it Low (0).
    if (val == 0) {
      printf("BUTTON_PRESSED\n");

      // Debounce logic: wait 200ms to prevent multiple detections for a single
      // physical press
      usleep(200000);
    }
  }

  // Release resources before exiting (reached if loop breaks on error)
  gpiod_line_release(line);
  gpiod_chip_close(chip);
  return 0;
}

// all code written by me with minimal AI assistance, comments added using AI
// and verified by me