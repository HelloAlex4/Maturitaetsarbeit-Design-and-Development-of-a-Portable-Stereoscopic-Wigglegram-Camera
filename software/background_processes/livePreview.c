/*
 * Script Name: livePreview.c
 * Description:
 *   High-performance service for capturing live preview frames from an STM32
 * camera over a serial/USB connection. It polls a SQLite database for a 'live'
 * flag, initiates a handshake with the camera, decodes YVYU raw data to BMP
 * format, and saves the output for the UI to display. Optimised with integer
 * math for fast color conversion.
 */

// all code written by me with minimal AI assistance, comments added using AI
// and verified by me

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <sqlite3.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h> // <--- ADDED: Required for gettimeofday
#include <sys/types.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

// --- CONFIGURATION ---
#define CAM_DEVICE "/dev/stm32_cam_1"
#define CAM_ID 1
#define DB_PATH "./camera.db"
#define OUT_DIR "../images/live"

// Output file is now .bmp
#define OUT_FILE "../images/live/live.bmp"

#define WIDTH 320
#define HEIGHT 240
#define BYTES_PER_PIXEL 2
#define FRAME_SIZE (WIDTH * HEIGHT * BYTES_PER_PIXEL)
#define BAUD_RATE B115200

#ifndef CLAMP
#define CLAMP(x) ((x) < 0 ? 0 : ((x) > 255 ? 255 : (x)))
#endif

// --- HELPER: CLIP ---
// Matches Python: return 0 if x < 0 else (255 if x > 255 else x)
/**
 * @brief Clamps an integer value to the 0-255 range.
 *
 * @param x The value to clamp.
 * @return int The clamped value.
 */
static inline int clip(int x) {
  if (x < 0)
    return 0;
  if (x > 255)
    return 255;
  return x;
}

// --- BITMAP HEADER HELPER ---
/**
 * @brief Populates a 54-byte BMP file header for a 24-bit RGB bitmap.
 *
 * @param header Pointer to the 54-byte buffer to populate.
 */
void create_bmp_header(unsigned char *header) {
  int image_size = WIDTH * HEIGHT * 3;
  int file_size = 54 + image_size;
  int ppm = 2835;

  memset(header, 0, 54);
  header[0] = 'B';
  header[1] = 'M';
  *((int *)(header + 2)) = file_size;
  *((int *)(header + 10)) = 54;
  *((int *)(header + 14)) = 40;
  *((int *)(header + 18)) = WIDTH;
  *((int *)(header + 22)) =
      -HEIGHT; // Negative height = Top-Down (standard for most buffers)
  *((short *)(header + 26)) = 1;
  *((short *)(header + 28)) = 24; // 24-bit RGB
  *((int *)(header + 30)) = 0;
  *((int *)(header + 34)) = image_size;
  *((int *)(header + 38)) = ppm;
  *((int *)(header + 42)) = ppm;
}

// --- EXACT PYTHON MATH CONVERSION ---
// Input Packing: YVYU (Matches Python config PACKING="YVYU")
// Output Packing: BGR (Required for standard .BMP files)

/**
 * @brief Converts YVYU422 bytes to 24-bit RGB using fast integer math.
 *
 * This function processes two pixels at a time from the raw YVYU buffer.
 * It maps YVYU values to RGB using an approximation of the standard
 * BT.601 color space transformation.
 *
 * @param raw Input buffer containing YVYU data.
 * @param rgb_out Output buffer for 24-bit RGB data (BGR order for BMP).
 */
void yvyu_to_rgb_int_math(unsigned char *raw, unsigned char *rgb_out) {
  int y0, u, y1, v;
  int u_signed, v_signed;

  // Variables holding the raw formula results:
  // py_r0 = Result of standard Blue formula (Y + 1.772 * U)
  // py_g0 = Result of standard Red formula  (Y + 1.402 * V)
  // py_b0 = Result of standard Green formula
  int py_r0, py_g0, py_b0;
  int py_r1, py_g1, py_b1;

  int i, j;

  for (i = 0, j = 0; i < FRAME_SIZE; i += 4, j += 6) {

    // 1. EXTRACT BYTES
    y0 = raw[i];
    u = raw[i + 1];
    y1 = raw[i + 2];
    v = raw[i + 3];

    // 2. INTEGER MATH PREP
    u_signed = u - 128;
    v_signed = v - 128;

    // 3. CALCULATE PIXEL 0
    // py_g0 (Red formula): 1436/1024 approx 1.402
    py_g0 = y0 + ((1436 * v_signed) >> 10);

    // py_b0 (Green formula): Standard G conversion
    py_b0 = y0 - ((352 * u_signed) >> 10) - ((731 * v_signed) >> 10);

    // py_r0 (Blue formula): 1815/1024 approx 1.772
    py_r0 = y0 + ((1815 * u_signed) >> 10);

    // 4. CALCULATE PIXEL 1
    py_g1 = y1 + ((1436 * v_signed) >> 10);
    py_b1 = y1 - ((352 * u_signed) >> 10) - ((731 * v_signed) >> 10);
    py_r1 = y1 + ((1815 * u_signed) >> 10);

    // 5. WRITE TO BUFFER (Order: Green, Red, Blue)

    // Pixel 0
    rgb_out[j] = (unsigned char)CLAMP(
        py_b0); // Green Value (Fixes "Red interpreted as Green")
    rgb_out[j + 1] = (unsigned char)CLAMP(
        py_g0); // Red Value   (Fixes "Blue interpreted as Red")
    rgb_out[j + 2] = (unsigned char)CLAMP(py_r0); // Blue Value

    // Pixel 1
    rgb_out[j + 3] = (unsigned char)CLAMP(py_b1); // Green Value
    rgb_out[j + 4] = (unsigned char)CLAMP(py_g1); // Red Value
    rgb_out[j + 5] = (unsigned char)CLAMP(py_r1); // Blue Value
  }
}

// --- SERIAL SETUP ---
/**
 * @brief Configures the serial port for high-speed raw data transfer.
 *
 * Sets the baud rate, 8N1 mode, disables hardware/software flow control,
 * and configures non-blocking read with a timeout.
 *
 * @param portname System path to the serial device.
 * @return int File descriptor on success, -1 on failure.
 */
int setup_serial(const char *portname) {
  int fd = open(portname, O_RDWR | O_NOCTTY | O_SYNC);
  if (fd < 0) {
    printf("[ERROR] Could not open %s: %s\n", portname, strerror(errno));
    return -1;
  }

  struct termios tty;
  if (tcgetattr(fd, &tty) != 0)
    return -1;

  cfsetospeed(&tty, BAUD_RATE);
  cfsetispeed(&tty, BAUD_RATE);

  tty.c_cflag = (tty.c_cflag & ~CSIZE) | CS8;
  tty.c_iflag &= ~IGNBRK;
  tty.c_lflag = 0;
  tty.c_oflag = 0;
  tty.c_cc[VMIN] = 0;
  tty.c_cc[VTIME] = 20; // 2.0s timeout

  tty.c_iflag &= ~(IXON | IXOFF | IXANY);
  tty.c_cflag |= (CLOCAL | CREAD);
  tty.c_cflag &= ~(PARENB | PARODD);
  tty.c_cflag &= ~CSTOPB;
  tty.c_cflag &= ~CRTSCTS;

  if (tcsetattr(fd, TCSANOW, &tty) != 0)
    return -1;
  return fd;
}

// --- READ HELPER ---
/**
 * @brief Reads exactly 'len' bytes from a file descriptor with retries.
 *
 * @param fd The serial port file descriptor.
 * @param buf Buffer to store the read data.
 * @param len Exact number of bytes to read.
 * @return int Total bytes read, or -1 if a timeout/error occurred.
 */
int read_exact(int fd, unsigned char *buf, int len) {
  int total = 0;
  int retries = 0;
  while (total < len) {
    int n = read(fd, buf + total, len - total);
    if (n > 0) {
      total += n;
      retries = 0;
    } else {
      retries++;
      if (retries > 500)
        return -1; // Timeout
      usleep(1000);
    }
  }
  return total;
}

// --- DB HELPER ---
/**
 * @brief Checks if live preview mode is enabled for a specific camera in the
 * DB.
 *
 * @param db Pointer to the open SQLite database.
 * @return int 1 if live mode is active, 0 otherwise.
 */
int check_live_status(sqlite3 *db) {
  sqlite3_stmt *res;
  const char *sql = "SELECT live FROM capture WHERE id = ?;";

  if (sqlite3_prepare_v2(db, sql, -1, &res, 0) != SQLITE_OK)
    return 0;

  sqlite3_bind_int(res, 1, CAM_ID);

  int is_live = 0;
  if (sqlite3_step(res) == SQLITE_ROW) {
    is_live = sqlite3_column_int(res, 0);
  }
  sqlite3_finalize(res);
  return is_live;
}

// --- MAIN ---
/**
 * @brief Main execution loop for the live preview service.
 *
 * Manages memory allocation, database polling, and the high-speed
 * handshake/capture loop with the camera.
 */
int main() {
  // 1. Allocate Memory
  unsigned char *raw_buf = malloc(FRAME_SIZE);
  unsigned char *rgb_buf = malloc(WIDTH * HEIGHT * 3);
  unsigned char bmp_header[54];

  // --- TIMING VARIABLES ---
  struct timeval t_cycle_start, t_read_end, t_process_end;
  double total_cycle_ms, read_ack_ms, process_save_ms, fps;

  // Create Header once
  create_bmp_header(bmp_header);

  if (!raw_buf || !rgb_buf) {
    fprintf(stderr, "Memory allocation failed\n");
    return 1;
  }

  // 2. Prepare Output Directory
  struct stat st = {0};
  if (stat(OUT_DIR, &st) == -1)
    mkdir(OUT_DIR, 0700);

  // 3. Open Database
  sqlite3 *db;
  if (sqlite3_open(DB_PATH, &db)) {
    fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
    return 1;
  }

  printf("Live Service Started for %s (DB ID: %d)...\n", CAM_DEVICE, CAM_ID);

  while (1) {
    // 4. Poll Database
    if (check_live_status(db)) {

      // 5. Open Serial Port
      int serial_fd = setup_serial(CAM_DEVICE);
      if (serial_fd < 0) {
        sleep(1);
        continue;
      }

      printf("Live Mode Triggered. Sending 'L\\n'...\n");

      // Flush and Send Start (With Newline)
      tcflush(serial_fd, TCIFLUSH);
      write(serial_fd, "L\n", 2);
      tcdrain(serial_fd);

      // --- INIT TIMER: Set the baseline for the first cycle ---
      gettimeofday(&t_cycle_start, NULL);

      // 6. Streaming Handshake Loop
      while (1) {
        // A. Read Frame (153.6 KB)
        int n = read_exact(serial_fd, raw_buf, FRAME_SIZE);
        if (n != FRAME_SIZE) {
          printf("Frame Error (Read %d/%d). Retrying connection...\n", n,
                 FRAME_SIZE);
          break;
        }

        // --- MEASURE 1: End of Read ---
        gettimeofday(&t_read_end, NULL);

        // B. **IMMEDIATELY SEND ACK (Critical Speedup)**
        // The STM32 starts CAPTURING the next frame now.
        if (check_live_status(db)) {
          // Send ACK ('A\n') -> Request next frame
          write(serial_fd, "A\n", 2);
          tcdrain(serial_fd);
        } else {
          // Send STOP ('X\n') -> Stop STM32
          printf("Stop Requested. Sending 'X\\n'...\n");
          write(serial_fd, "X\n", 2);
          tcdrain(serial_fd);

          usleep(50000); // Give STM32 time to process X
          break;
        }

        // C. Process and Save (Runs in parallel with STM32's capture)
        yvyu_to_rgb_int_math(raw_buf, rgb_buf);

        FILE *f = fopen(OUT_FILE, "wb");
        if (f) {
          fwrite(bmp_header, 1, 54, f);
          fwrite(rgb_buf, 1, WIDTH * HEIGHT * 3, f);
          fclose(f);
        }

        // --- MEASURE 2: End of Processing/Save ---
        gettimeofday(&t_process_end, NULL);

        // --- MEASURE 3: CALCULATE TIMING ---
        // Calculate Total Cycle Time (t_cycle_start to t_process_end)
        total_cycle_ms = (t_process_end.tv_sec - t_cycle_start.tv_sec) * 1000.0;
        total_cycle_ms +=
            (t_process_end.tv_usec - t_cycle_start.tv_usec) / 1000.0;

        // Calculate Read/ACK Time (t_cycle_start to t_read_end)
        // This is the critical STM32+USB transfer time
        read_ack_ms = (t_read_end.tv_sec - t_cycle_start.tv_sec) * 1000.0;
        read_ack_ms += (t_read_end.tv_usec - t_cycle_start.tv_usec) / 1000.0;

        // Calculate Process/Save Time (t_read_end to t_process_end)
        process_save_ms = (t_process_end.tv_sec - t_read_end.tv_sec) * 1000.0;
        process_save_ms +=
            (t_process_end.tv_usec - t_read_end.tv_usec) / 1000.0;

        // Calculate FPS (using the corrected cycle time)
        if (read_ack_ms > 0) {
          fps = 1000.0 / read_ack_ms; // FPS is limited by the Read/ACK portion
        } else {
          fps = 0.0;
        }

        // --- SUCCESS PRINT WITH STATS ---
        printf("SUCCESS | FPS: %.2f | READ/ACK (STM32 Bottleneck): %.2f ms | "
               "PROCESS/SAVE (PC Overhead): %.2f ms\n",
               fps, read_ack_ms, process_save_ms);

        // --- RESET TIMER FOR NEXT CYCLE ---
        // The start of the next cycle is the time of the ACK (t_read_end).
        // For the next cycle, t_cycle_start is now t_read_end.
        t_cycle_start = t_read_end;
      }

      close(serial_fd);
      printf("Session ended. Idle.\n");
    }

    // Idle Poll Rate (100ms)
    usleep(100000);
  }

  free(raw_buf);
  free(rgb_buf);
  sqlite3_close(db);
  return 0;
}

// all code written by me with minimal AI assistance, comments added using AI
// and verified by me
