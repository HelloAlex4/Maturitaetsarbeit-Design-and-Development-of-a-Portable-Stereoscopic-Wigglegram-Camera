"""
Script Name: streamUSB.py
Description:
    Multi-threaded utility for controlling and capturing images from one or more
    STM32-based camera modules. It supports register updates (e.g., exposure control),
    camera resetting, and frame capture with YUV422 to RGB decoding.
    It can operate on individual cameras or in persistent/batch modes.
"""

#all code written by me with minimal AI assistance, comments added using AI and verified by me

import serial
import time
import argparse
import sys
import threading
import uuid
import sqlite3
import numpy as np
from pathlib import Path
from PIL import Image

# --- CONFIGURATION ---
WIDTH = 320
HEIGHT = 240
BYTES_PER_PIXEL = 2
FRAME_SIZE = WIDTH * HEIGHT * BYTES_PER_PIXEL
PACKING = "UYVY"
BAUD_RATE = 115200
TIMEOUT = 5

# --- NEW: REGISTERS TO UPDATE ---
# Add your I2C registers here. Format: { 0xRegister : 0xValue }
REGISTRY_UPDATES = {
0x3503: 0x01,  # AEC PK MANUAL: AEC manual enable (Bit 0=1), AGC auto enable (Bit 1=0)
    0x350A: 0x00,  # AEC PK REAL GAIN: Real gain [9:8] (High bits of manual gain)
    0x350B: 0x10,  # AEC PK REAL GAIN: Real gain [7:0] (Low bits of manual gain)

    0x5001: 0x23,  # ISP CONTROL 01: AWB Enable (Bit 0), CMX Enable (Bit 1), Scale Enable (Bit 5)
    0x5005: 0x32,  # ISP CONTROL 05: AWB Bias Enable (Bit 5), AWB Bias Plus (Bit 4), Gamma Bias (Bit 1)

    0x4302: 0x03,  # YMAX VALUE: Y max clip value [9:8] (High bits)
    0x4303: 0xFF,  # YMAX VALUE: Y max clip value [7:0] (Low bits) - Set to 1023 (0x3FF)
    0x4306: 0x03,  # UMAX VALUE: U max clip value [9:8] (High bits)
    0x4307: 0xFF,  # UMAX VALUE: U max clip value [7:0] (Low bits) - Set to 1023 (0x3FF)
    0x430A: 0x03,  # VMAX VALUE: V max clip value [9:8] (High bits)
    0x430B: 0xFF,  # VMAX VALUE: V max clip value [7:0] (Low bits) - Set to 1023 (0x3FF)

    0x5000: 0x21,  # ISP CONTROL 00: RAW Gamma Enable (Bit 5), Color Interpolation Enable (Bit 0)
    0x5481: 0x26,  # GAMMA YST00: Raw Gamma Curve Point 0
    0x5482: 0x35,  # GAMMA YST01: Raw Gamma Curve Point 1
    0x5483: 0x48,  # GAMMA YST02: Raw Gamma Curve Point 2
    0x5484: 0x57,  # GAMMA YST03: Raw Gamma Curve Point 3
    0x5485: 0x63,  # GAMMA YST04: Raw Gamma Curve Point 4
    0x5486: 0x6E,  # GAMMA YST05: Raw Gamma Curve Point 5
    0x5487: 0x77,  # GAMMA YST06: Raw Gamma Curve Point 6
    0x5488: 0x80,  # GAMMA YST07: Raw Gamma Curve Point 7
    
    0x3801: 0x01,  # TIMING HS: X address start [7:0] (Low byte)
    0x3821: 0x07,  # TIMING TC REG21: ISP mirror (Bit 2), Sensor mirror (Bit 1), Horiz binning (Bit 0)

    # 0xA3 = 1010 0011 (SDE Enable, Scale Enable, CMX Enable, AWB Enable)
    0x5001: 0xA3,  # ISP CONTROL 01: SDE (Bit 7), Scale (Bit 5), CMX (Bit 1), AWB (Bit 0) enabled
    0x3812: 0x00,  # TIMING VOFFSET: ISP vertical offset [10:8] (High byte)
    0x3811: 0x01,  # TIMING HOFFSET: ISP horizontal offset [7:0] (Low byte)

    # Sign bits (Critical for Green Channel subtractions)
    0x501F: 0x00, # FORMAT MUX CONTROL: Select ISP YUV422 (0x00)
    0x4300: 0x30, # FORMAT CONTROL 00: Output YUV422 (Bit 7:4=0x3), Sequence YUYV (Bit 3:0=0x0)
    #0x5020: 0x2A, # DITHER CTRL 0: Dither control settings
    0x503D: 0x00, # PRE ISP TEST SETTING 1: Color bar disable (Bit 7=0)

    # 1. Fix the Window Phase (The original solution)
    0x3800: 0x00,  # TIMING HS: X address start [11:8] (High byte)
    0x3801: 0x01,  # TIMING HS: X address start [7:0] (Low byte)
    0x3802: 0x00,  # TIMING VS: Y address start [10:8] (High byte)
    0x3803: 0x01,  # TIMING VS: Y address start [7:0] (Low byte)
    
    # 2. Keep Mirror/Binning (As you had originally)
    0x3820: 0x00,  # TIMING TC REG20: Vertical flip disable (Bit 2=0, Bit 1=0)
    0x3821: 0x07,  # TIMING TC REG21: ISP mirror, Sensor mirror, and Horizontal binning enabled
    
    # 3. Output Format
    0x4300: 0x30,  # FORMAT CONTROL 00: Output YUV422, YUYV Sequence
    0x501f: 0x00,  # FORMAT MUX CONTROL: ISP YUV422 select
    
    # 4. Revert Color Settings (To what worked before)
    # 0xA3 = 1010 0011. Note: Bit 1 is CMX Enable. 
    0x5001: 0xA3,  # ISP CONTROL 01: SDE on, Scale on, CMX on, AWB on
    0x5580: 0x02,  # SDE CTRL 0: SDE Manual Control/UV Adjust Enable (Bit 1=1)
    0x5583: 0x40,  # SDE CTRL 3: Saturation U (or Fixed U) value
    0x5584: 0x40,  # SDE CTRL 4: Saturation V (or Fixed V) value
    0x5587: 0x00,  # SDE CTRL 7: Y bright for contrast (Brightness)
}

# Paths anchored to script location
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
BATCH_OUTPUT_DIR = PROJECT_ROOT / "images" / "raws"
SINGLE_OUTPUT_DIR = SCRIPT_DIR
LIVE_OUTPUT_DIR = PROJECT_ROOT / "images" / "live"
IMAGES_DIR = PROJECT_ROOT / "images"
DB_PATH = SCRIPT_DIR / "camera.db"

# Track first frame duplication to images/ folder
first_image_saved = False
first_image_lock = threading.Lock()

# Map IDs to Udev Fixed Paths
CAMERA_MAP = {
    2: '/dev/stm32_cam_1',
    3: '/dev/stm32_cam_2',
    1: '/dev/stm32_cam_3',
    4: '/dev/stm32_cam_4'
}

# Synchronization Tools
trigger_event = threading.Event()
print_lock = threading.Lock()

def set_exposure_config(updates: dict, desired_lines_scale: int) -> dict:
    """
    Maps an exposure scale (1-10) to sensor line periods and updates registers.

    Calculates the 20-bit exposure value required by the sensor and updates
    the 0x3500, 0x3501, and 0x3502 registers in the provided updates dictionary.

    Args:
        updates (dict): Local registry update dictionary.
        desired_lines_scale (int): 1-10 scale for exposure brightness.

    Returns:
        dict: Updated registry dictionary.
    """
    if not (1 <= desired_lines_scale <= 10):
        print(f"Warning: Exposure scale {desired_lines_scale} is outside the range of 1 to 10.")
        desired_lines_scale = max(1, min(10, desired_lines_scale))

    # --- Define Target Range (Actual lines) ---
    MIN_LINES = 5  # Very dark baseline
    MAX_LINES = 5000 # Near max stable exposure lines (1964 rows)
    
    LINE_RANGE_DELTA = MAX_LINES - MIN_LINES
    SCALE_FACTOR = (desired_lines_scale - 1) / 9.0

    # Calculate actual lines using linear interpolation
    actual_lines = int(MIN_LINES + LINE_RANGE_DELTA * SCALE_FACTOR)

    # --- Convert Actual Lines to Sensor Register Units (units of 1/16th of a line) ---
    exposure_value = actual_lines * 16

    # --- Extract Exposure Components (20 bits total) ---
    
    # High Byte (Bits 19-16) - 0x3500
    high_byte = (exposure_value >> 16) & 0xFF  
    
    # Middle Byte (Bits 15-8) - 0x3501
    middle_byte = (exposure_value >> 8) & 0xFF
    
    # Low Byte (Bits 7-0) - 0x3502
    low_byte = exposure_value & 0xFF

    # Update the dictionary directly
    updates[0x3500] = high_byte
    updates[0x3501] = middle_byte
    updates[0x3502] = low_byte
    
    print(f"Set exposure scale {desired_lines_scale} -> {actual_lines} lines -> 0x3501/0x3502: 0x{middle_byte:02X} 0x{low_byte:02X}")
    return updates

def disable_live_mode(cam_id):
    """Disables the 'live' flag in the SQLite database for a specific camera ID."""
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cursor = conn.cursor()
        cursor.execute("UPDATE capture SET live = 0 WHERE id = ?", (cam_id,))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[DB ERROR] Could not update database for Camera {cam_id}: {e}")

def yuv422_to_rgb(raw_data, width, height):
    """
    Converts raw YUYV422 data to an RGB888 NumPy array.
    Uses high-precision full-scale conversion (JFIF standard).
    """
    # OV5640 YUYV: [Y0, U0, Y1, V0]
    data = np.frombuffer(raw_data, dtype=np.uint8).reshape(height, width // 2, 4)

    # 1. Extract raw components
    y0 = data[..., 0].astype(np.float32)
    u  = data[..., 1].astype(np.float32)
    y1 = data[..., 2].astype(np.float32)
    v  = data[..., 3].astype(np.float32)

    # 2. Shift Chroma to signed range (-128 to 127)
    # This is the most common failure point for black/white balance
    u_signed = u - 128.0
    v_signed = v - 128.0

    # 3. High-Precision Full-Scale Conversion (JFIF/JPEG Standard)
    # This math ensures that U=0, V=0 (after shift) results in R=G=B=Y
    
    # Pixel 0
    g0 = y0 + 1.402 * v_signed
    b0 = y0 - 0.344136 * u_signed - 0.714136 * v_signed
    r0 = y0 + 1.772 * u_signed
    
    # Pixel 1
    g1 = y1 + 1.402 * v_signed
    b1 = y1 - 0.344136 * u_signed - 0.714136 * v_signed
    r1 = y1 + 1.772 * u_signed

    # 4. Final Clipping and Assembly
    rgb = np.empty((height, width, 3), dtype=np.uint8)
    
    rgb[:, 0::2, 0] = np.clip(r0, 0, 255)
    rgb[:, 0::2, 1] = np.clip(g0, 0, 255)
    rgb[:, 0::2, 2] = np.clip(b0, 0, 255)

    rgb[:, 1::2, 0] = np.clip(r1, 0, 255)
    rgb[:, 1::2, 1] = np.clip(g1, 0, 255)
    rgb[:, 1::2, 2] = np.clip(b1, 0, 255)

    return rgb

def yuv422_to_rgb_rgb565(raw_data, width, height):
    """
    Converts raw data interpreted as RGB565 to an RGB888 NumPy array.
    Uses bit-replication for accurate 5/6-bit to 8-bit scaling.
    """
    # RGB565 uses 2 bytes per pixel, same as YUYV422 
    # We load as uint16 to handle the two bytes of each pixel as a single word
    # Note: Depending on your hardware DVP/MIPI interface, you may need to 
    # use '.byteswap()' if the byte order is swapped (Endianness).
    data = np.frombuffer(raw_data, dtype='>u2').reshape(height, width)

    # 1. Extract raw components using bit masks
    # Red:   High 5 bits (0xF800)
    # Green: Middle 6 bits (0x07E0)
    # Blue:  Low 5 bits (0x001F)
    r_5bit = (data >> 11) & 0x1F
    g_6bit = (data >> 5) & 0x3F
    b_5bit = data & 0x1F

    # 2. Scale up to 8-bit (0-255)
    # Using bit-replication (e.g., r7r6r5r4r3 -> r7r6r5r4r3 r7r6r5) is more
    # accurate than simple multiplication for full-scale 255.
    r8 = (r_5bit << 3) | (r_5bit >> 2)
    g8 = (g_6bit << 2) | (g_6bit >> 4)
    b8 = (b_5bit << 3) | (b_5bit >> 2)

    # 3. Assemble final RGB888 array
    rgb = np.empty((height, width, 3), dtype=np.uint8)
    rgb[..., 0] = r8
    rgb[..., 1] = g8
    rgb[..., 2] = b8

    return rgb

def save_image(raw_data, cam_id, batch_uuid=None, as_grayscale=False, is_live=False):
    """
    Decodes raw camera data and saves it as a PNG image.
    Handles file path generation for live, batch, or single capture modes.
    """
    try:
        img = None
        if as_grayscale:
            y_data = None
            if PACKING.upper() == "UYVY":
                y_data = raw_data[1::2] 
            elif PACKING.upper() == "YUYV":
                y_data = raw_data[0::2]
            if y_data:
                img = Image.frombytes("L", (WIDTH, HEIGHT), bytes(y_data))
        else:
            rgb_array = yuv422_to_rgb(raw_data, WIDTH, HEIGHT)
            img = Image.fromarray(rgb_array, mode='RGB')

        if img:
            unix_time = int(time.time())
            if is_live:
                LIVE_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
                filename = LIVE_OUTPUT_DIR / "live.png"
            elif batch_uuid:
                BATCH_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
                filename = BATCH_OUTPUT_DIR / f"{unix_time}_{cam_id}.png"
            else:
                SINGLE_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
                filename = SINGLE_OUTPUT_DIR / f"cam_{cam_id}_capture.png"

            img.save(filename, format="PNG")
            
            if not is_live:
                global first_image_saved
                with first_image_lock:
                    if not first_image_saved:
                        first_image_saved = True
                        try:
                            IMAGES_DIR.mkdir(parents=True, exist_ok=True)
                            identifier = unix_time if batch_uuid else 'single'
                            extra_name = f"{identifier}_1.png"
                            extra_path = IMAGES_DIR / extra_name
                            img.save(extra_path, format="PNG")
                        except Exception as e:
                            with print_lock:
                                print(f"[CAM {cam_id}] Extra first-image save error: {e}")

            with print_lock:
                print(f"[CAM {cam_id}] Saved Image: {filename}")
        else:
             with print_lock:
                print(f"[CAM {cam_id}] Error: No image data processed.")
    except Exception as e:
        with print_lock:
            print(f"[CAM {cam_id}] Image Save Error: {e}")

def camera_worker(cam_id, port_name, mode, dump_hex=False, batch_uuid=None, as_grayscale=False, is_live=False, exposure_value=None):
    """
    Thread-safe worker function to handle sequential operations for a single camera.
    Supported modes: UPDATE (registers), RESET (sensor), or CAPTURE (frame data).
    """
    try:
        with serial.Serial(port_name, BAUD_RATE, timeout=TIMEOUT) as ser:
            trigger_event.wait() 

            # --- MODE: UPDATE REGISTERS ---
            if mode == "UPDATE":
                # 1. Create local, thread-safe copy of registers
                local_regs = REGISTRY_UPDATES.copy()
                
                # 2. If exposure is set via CLI, calculate and update the local copy
                if exposure_value is not None:
                    # This calls the calculation function within the worker thread
                    local_regs = set_exposure_config(local_regs, exposure_value)

                with print_lock:
                    print(f"[CAM {cam_id}] Uploading {len(local_regs)} registers...")
                
                # 3. Clear buffers
                ser.reset_input_buffer()
                
                # 4. Send 'W' commands from the local, calculated map
                for reg, val in local_regs.items():
                    cmd = f"W {reg:04X} {val:02X}\n" 
                    ser.write(cmd.encode('utf-8'))
                    time.sleep(0.05)
                
                with print_lock:
                    print(f"[CAM {cam_id}] Upload complete. Sending Reset...")

                # 5. Send Reset to apply
                ser.write(b'R\n')
                time.sleep(0.1)
                
                with print_lock:
                    print(f"[CAM {cam_id}] Registers Applied & Camera Reset.")

            # --- MODE: RESET ONLY ---
            elif mode == "RESET":
                with print_lock:
                    print(f"[CAM {cam_id}] Sending RESET Command 'R'...")
                
                ser.write(b'R\n')
                time.sleep(0.1)
                response = ser.read_all().decode('utf-8', errors='ignore')
                
                with print_lock:
                    print(f"[CAM {cam_id}] Reset Response: {response.strip()}")
            
            # --- MODE: CAPTURE ---
            else:
                ser.write(b'S\n')
                time.sleep(0.05)
                ser.reset_input_buffer()
                
                data = ser.read(FRAME_SIZE)

                with print_lock:
                    if len(data) == FRAME_SIZE:
                        print(f"\n[CAM {cam_id}] SUCCESS. Frame Received.")
                        if dump_hex:
                            print(f"--- [CAM {cam_id}] HEX DUMP START ---")
                            print(data.hex().upper())
                            print(f"--- [CAM {cam_id}] HEX DUMP END ---")
                    else:
                        print(f"\n[CAM {cam_id}] ERROR: Timed out. Got {len(data)} / {FRAME_SIZE} bytes.")

                if len(data) == FRAME_SIZE:
                    save_image(data, cam_id, batch_uuid, as_grayscale, is_live)

    except serial.SerialException as e:
        with print_lock:
            print(f"[CAM {cam_id}] Port Error ({port_name}): {e}")
    finally:
        # Added mandatory finally block to ensure try structure is closed
        pass 

def run_camera_batch(target_cameras, mode, dump_hex, batch_uuid=None, as_grayscale=False, is_live=False, exposure_value=None):
    """
    Launches and manages multi-threaded execution across multiple cameras.
    Ensures live mode is disabled in the DB before proceeding.
    """
    trigger_event.clear()
    
    # --- STEP 1: DISABLE LIVE MODE IN DB (livePreview.c script)---
    print(f"\n--- PREPARING {mode} BATCH (Live: {is_live}) ---")
    print(">>> Disabling background live-view in Database...")
    
    for c_id in target_cameras.keys():
        disable_live_mode(c_id)
    
    time.sleep(0.5) 
    
    threads = []
    
    # --- STEP 2: LAUNCH THREADS ---
    for c_id, c_port in target_cameras.items():
        # Pass the exposure_value down to the worker
        t = threading.Thread(target=camera_worker, args=(c_id, c_port, mode, dump_hex, batch_uuid, as_grayscale, is_live, exposure_value))
        threads.append(t)
        t.start()
    
    print(f"!!! TRIGGERING {mode} NOW !!!")
    trigger_event.set()

    for t in threads:
        t.join()
    
    print(f"--- {mode} BATCH COMPLETE ---\n")

def main():
    """CLI entry point for controlling STM32 cameras and managing captures."""
    #parse console argument
    parser = argparse.ArgumentParser(description="Control STM32 Cameras.")
    parser.add_argument('camera_id', type=int, nargs='?', choices=[1, 2, 3, 4], 
                        help="ID of specific camera. Leave empty for ALL cameras.")
    # --- MODES ---
    parser.add_argument('--reset', action='store_true', 
                        help="Only perform a reset (skip capture).")
    parser.add_argument('-I', '--init-regs', action='store_true',
                        help="Upload I2C registers defined in script and Reset.")
    
    # --- NEW EXPOSURE ARGUMENT ---
    parser.add_argument('--exposure', type=int, choices=range(1, 11),
                        help="Set manual exposure time in lines (1-10).")

    # --- CAPTURE OPTIONS ---
    parser.add_argument('--grayscale', action='store_true', 
                        help="Save image in Grayscale/B&W (Default is Color).")
    parser.add_argument('--live', action='store_true',
                        help="Capture single COLOR frame without reset and save as live.pmg (overwrites).")

    args = parser.parse_args()

    # --- TARGET Camera SELECTION ---
    target_cameras = {}
    if args.camera_id:
        # User specified a specific camera number
        if args.camera_id in CAMERA_MAP:
            target_cameras[args.camera_id] = CAMERA_MAP[args.camera_id]
        else:
            print("Error: Camera ID not found.")
            return
    else:
        # User did NOT specify a number -> Select ALL
        target_cameras = CAMERA_MAP

    # --- LOGIC FLOW ---

    exposure_val = args.exposure if args.exposure is not None else None
    
    # If -I is called OR if --exposure is called, run the UPDATE mode
    if args.init_regs or exposure_val is not None:
        print(">>> REGISTER UPDATE MODE <<<")
        # Run in update mode, passing the exposure value if set. The worker will handle the calculation.
        run_camera_batch(target_cameras, "UPDATE", False, exposure_value=exposure_val)

    elif args.live:
        print(">>> LIVE MODE DETECTED: CAPTURING SINGLE FRAME (NO RESET) <<<")
        run_camera_batch(target_cameras, "CAPTURE", False, batch_uuid=None, as_grayscale=False, is_live=True)

    elif args.camera_id:
        mode = "RESET" if args.reset else "CAPTURE"
        dump_hex = (mode == "CAPTURE") 
        run_camera_batch(target_cameras, mode, dump_hex, batch_uuid=None, as_grayscale=args.grayscale)

    elif args.reset:
        run_camera_batch(target_cameras, "RESET", False, batch_uuid=None)

    else:
        print(">>> ALL CAMERA MODE DETECTED: INITIATING AUTO-RESET SEQUENCE <<<")
        
        run_camera_batch(target_cameras, "RESET", False)
        
        print(">>> WAITING 2 SECONDS FOR SENSOR STABILIZATION ... <<<")
        time.sleep(0.5)
        
        unique_id = uuid.uuid4().hex[:8]
        print(f">>> BATCH UUID: {unique_id} <<<")

        run_camera_batch(target_cameras, "CAPTURE", False, batch_uuid=unique_id, as_grayscale=args.grayscale)

if __name__ == "__main__":
    main()


#all code written by me with minimal AI assistance, comments added using AI and verified by me