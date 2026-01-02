# ------------------ CLI entry point ------------------
"""
WS2812 LED effects for Raspberry Pi 5 using rpi5_ws2812.

This script provides several visual effects for a WS2812 LED strip connected to
the Raspberry Pi 5. It manages a background process state using a PID file to
ensure only one effect runs at a time and provides a CLI for triggering effects.

Includes effects: rainbow, comet, theater, solid, and white.
"""

#all code written by me with minimal AI assistance, comments added using AI and verified by me

from rpi5_ws2812.ws2812 import Color, WS2812SpiDriver
import time
import math
from typing import List, Tuple

import os
import signal

PID_FILE = "/tmp/led_effect.pid"

def _read_pid():
    """Reads the process ID of the currently running LED effect from the PID file."""
    try:
        with open(PID_FILE, "r") as f:
            return int(f.read().strip())
    except Exception:
        return None

def _pid_alive(pid: int) -> bool:
    """Checks if a process with the given PID is currently active."""
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

def _terminate_previous(timeout: float = 2.0) -> None:
    """Attempts to terminate any previously running LED effect process."""
    pid = _read_pid()
    if not pid:
        return
    # Don't kill ourselves if we happen to run within the same process
    if pid == os.getpid():
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    # wait up to timeout
    import time as _t
    start = _t.time()
    while _t.time() - start < timeout:
        if not _pid_alive(pid):
            break
        _t.sleep(0.05)
    if _pid_alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    # best effort cleanup
    try:
        os.remove(PID_FILE)
    except Exception:
        pass

# ------------------ Config ------------------
LED_COUNT = 30
SPI_BUS = 0
SPI_DEVICE = 0

RGB = Tuple[int, int, int]

# ------------------ Helpers ------------------

def make_strip(led_count: int = LED_COUNT,
               spi_bus: int = SPI_BUS,
               spi_device: int = SPI_DEVICE):
    """
    Initializes the WS2812 strip and creates a local RGB buffer.

    Returns:
        tuple: (WS2812 strip object, RGB buffer list)
    """
    strip = WS2812SpiDriver(spi_bus=spi_bus, spi_device=spi_device,
                            led_count=led_count).get_strip()
    buf: List[RGB] = [(0, 0, 0)] * led_count
    return strip, buf


def show(strip, buf: List[RGB]) -> None:
    """Updates the physical LED strip with the contents of the RGB buffer."""
    for i, (r, g, b) in enumerate(buf):
        strip.set_pixel_color(i, Color(r, g, b))
    strip.show()


def clear(buf: List[RGB]) -> None:
    """Resets the RGB buffer to all zeros (off)."""
    for i in range(len(buf)):
        buf[i] = (0, 0, 0)


def fade_all(buf: List[RGB], amount: int) -> None:
    """Reduces the brightness of all pixels in the buffer by a specific amount."""
    amt = max(0, int(amount))
    for i, (r, g, b) in enumerate(buf):
        buf[i] = (max(0, r - amt), max(0, g - amt), max(0, b - amt))


def wheel(pos: int) -> RGB:
    """Generates a color from a 0-255 position on a color wheel."""
    pos %= 256
    if pos < 85:
        return (pos * 3, 255 - pos * 3, 0)
    if pos < 170:
        pos -= 85
        return (255 - pos * 3, 0, pos * 3)
    pos -= 170
    return (0, pos * 3, 255 - pos * 3)

# ------------------ Effects (3) ------------------

def effect_rainbow(strip, buf: List[RGB], fps: int = 50) -> None:
    """Runs a moving rainbow effect across the entire strip."""
    offset = 0
    frame = 1.0 / max(1, fps)
    n = len(buf)
    while True:
        t0 = time.time()
        for i in range(n):
            buf[i] = wheel((i * 256 // n + offset) & 255)
        show(strip, buf)
        offset = (offset + 2) & 255
        dt = time.time() - t0
        if dt < frame:
            time.sleep(frame - dt)


def effect_comet(strip, buf: List[RGB], fps: int = 60,
                  color: RGB = (0, 255, 180), fade: int = 18) -> None:
    """Runs a bouncing single pixel 'comet' effect with a fading tail."""
    n = len(buf)
    pos, direction = 0, 1
    frame = 1.0 / max(1, fps)
    while True:
        t0 = time.time()
        fade_all(buf, fade)
        buf[pos] = color
        show(strip, buf)
        pos += direction
        if pos <= 0 or pos >= n - 1:
            direction *= -1
        dt = time.time() - t0
        if dt < frame:
            time.sleep(frame - dt)


def effect_theater_chase(strip, buf: List[RGB], fps: int = 30,
                          color: RGB = (255, 80, 0), gap: int = 3) -> None:
    """Runs a classic 'theater chase' marquee effect."""
    step = 0
    frame = 1.0 / max(1, fps)
    n = len(buf)
    g = max(1, gap)
    while True:
        t0 = time.time()
        # Clear for crisp dots
        for i in range(n):
            buf[i] = (0, 0, 0)
        for i in range(step % g, n, g):
            buf[i] = color
        show(strip, buf)
        step = (step + 1) % g
        dt = time.time() - t0
        if dt < frame:
            time.sleep(frame - dt)

def effect_solid_color(strip, buf: List[RGB], color: RGB) -> None:
    """Displays a constant solid color across the entire strip."""
    while True:
        for i in range(len(buf)):
            buf[i] = color
        show(strip, buf)
        time.sleep(0.05)


# ------------------ New Effect: White ------------------
def effect_white(strip, buf: List[RGB], brightness: int = 200) -> None:
    """Gradually ramps up and then holds a solid white light."""
    brightness = max(0, min(255, int(brightness)))
    target_color = (brightness, brightness, brightness)
    ramp_duration = 0.7
    steps = max(1, int(ramp_duration / 0.02))
    sleep_per_step = ramp_duration / steps 

    # Smooth ramp to the target brightness once, then hold steady.
    for step in range(1, steps + 1):
        level = int(brightness * step / steps)
        color = (level, level, level)
        for i in range(len(buf)):
            buf[i] = color
        show(strip, buf)
        time.sleep(sleep_per_step)

    while True:
        for i in range(len(buf)):
            buf[i] = target_color
        show(strip, buf)
        time.sleep(0.05)

# ------------------ Registry & single-effect runner ------------------
EFFECTS = {
    "rainbow": effect_rainbow,
    "comet": effect_comet,
    "theater": effect_theater_chase,
    "solid": effect_solid_color,
    "white": effect_white,
}


def run_effect(name: str, **kwargs) -> None:
    """
    Orchestrates the execution of a named LED effect.
    Handles PID management, initialization, and cleanup.
    """
    print("effect triggered")

    """Create strip/buffer and run a single effect by name once."""
    if name not in EFFECTS:
        raise ValueError(f"Unknown effect '{name}'. Available: {', '.join(EFFECTS)}")
    # stop any previous background runner
    _terminate_previous()
    # record our PID so future calls can stop us
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass
    strip, buf = make_strip()
    try:
        try:
            EFFECTS[name](strip, buf, **kwargs)
        except Exception as e:
            print(f"Error in {name}: {e}")
            import traceback; traceback.print_exc()
    finally:
        clear(buf)
        show(strip, buf)
        try:
            if os.path.exists(PID_FILE) and _read_pid() == os.getpid():
                os.remove(PID_FILE)
        except Exception:
            pass

def clear_strip() -> None:
    """Stops any running effect and turns off all pixels on the strip."""
    _terminate_previous()
    strip, buf = make_strip()
    clear(buf)
    show(strip, buf)
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception:
        pass

# ------------------ CLI entry point (effect only) ------------------
if __name__ == "__main__":
    import argparse

    def _handle_exit(signum, frame):
        """Signal handler to ensure LEDs are turned off when the process is terminated."""
        try:
            strip, buf = make_strip()
            clear(buf)
            show(strip, buf)
        except Exception:
            pass
        try:
            if os.path.exists(PID_FILE) and _read_pid() == os.getpid():
                os.remove(PID_FILE)
        except Exception:
            pass
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _handle_exit)
    signal.signal(signal.SIGINT, _handle_exit)

    parser = argparse.ArgumentParser(description="Run a single WS2812 LED effect (defaults only)")
    parser.add_argument("effect", choices=sorted(list(EFFECTS.keys()) + ["clear", "stop"]), help="Effect to run")
    parser.add_argument("--color", type=int, nargs=3, metavar=('R', 'G', 'B'), help="RGB color for solid effect")
    args = parser.parse_args()

    if args.effect in ("clear", "stop"):
        clear_strip()
    elif args.effect == "solid":
        if args.color is None:
            parser.error("--color is required for the 'solid' effect")
        run_effect("solid", color=tuple(args.color))
    else:
        run_effect(args.effect)


#all code written by me with minimal AI assistance, comments added using AI and verified by me