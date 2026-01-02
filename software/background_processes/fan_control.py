"""
PWM fan control on BCM 13 with three speed levels.

This script manages a cooling fan using PWM (Pulse Width Modulation) via the pigpio daemon.
It supports three predefined speed levels and an 'off' command.

Requires pigpio daemon for reliable PWM that persists after exit.

Usage:
  python3 scripts/fan_control.py level <0|1|2>
  python3 scripts/fan_control.py off

Levels map to duty cycles: [33%, 66%, 100%].
"""
#all code written by me with minimal AI assistance, comments added using AI and verified by me

import sys
import os

PIN = 13
FREQ = 25000  # Hz, typical quiet PWM for brushless fans
LEVEL_TO_DUTY = [85, 170, 255]


def _set_pigpio_duty(level: int) -> bool:
    """
    Sets the PWM duty cycle for the fan using the pigpio library.

    Args:
        level (int): The speed level index (0, 1, or 2). Use -1 to turn off.

    Returns:
        bool: True if the duty cycle was set successfully, False otherwise.
    """
    try:
        import pigpio  # type: ignore
    except Exception:
        print("error: pigpio module not available; install pigpio and run pigpiod", file=sys.stderr)
        return False

    pi = pigpio.pi()
    if not pi.connected:
        print("error: pigpio daemon not running (start with 'sudo pigpiod')", file=sys.stderr)
        return False

    if level < 0:
        duty = 0
    else:
        level = max(0, min(2, int(level)))
        duty = LEVEL_TO_DUTY[level]

    try:
        pi.set_PWM_frequency(PIN, FREQ)
        pi.set_PWM_dutycycle(PIN, duty)
        # Do not call pi.stop(); let daemon keep PWM running
        return True
    except Exception as e:
        print(f"error: failed to set PWM: {e}", file=sys.stderr)
        return False


def main(argv: list[str]) -> int:
    """
    Main entry point for the fan control script.

    Parses command-line arguments to set the fan level or turn it off.

    Args:
        argv (list[str]): Command-line arguments.

    Returns:
        int: Exit code (0 for success, non-zero for errors).
    """
    if len(argv) < 2:
        print("Usage: fan_control.py level <0|1|2> | off", file=sys.stderr)
        return 2
    cmd = argv[1].strip().lower()
    if cmd == "off":
        ok = _set_pigpio_duty(-1)
        return 0 if ok else 1
    if cmd == "level":
        if len(argv) < 3:
            print("Usage: fan_control.py level <0|1|2>", file=sys.stderr)
            return 2
        try:
            level = int(argv[2])
        except ValueError:
            print("level must be 0, 1, or 2", file=sys.stderr)
            return 2
        ok = _set_pigpio_duty(level)
        return 0 if ok else 1

    print("Usage: fan_control.py level <0|1|2> | off", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#all code written by me with minimal AI assistance, comments added using AI and verified by me