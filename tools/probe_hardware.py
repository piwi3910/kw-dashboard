#!/usr/bin/env python3
"""Verify DRM master, touch input, and VT availability on km01.

Spike tool (plan Task 1). Its job is to answer three questions that can
invalidate layout work if guessed wrong:

  1. Can the service user acquire DRM master unprivileged? -> systemd User=
  2. What are the ILITEK digitiser's axis ranges and orientation? -> calibration
  3. Which VT is free? -> systemd TTYPath=

Touch probing needs a human to touch the panel, so it is opt-in via --touch.
"""

import glob
import os
import select
import struct
import subprocess
import sys
import time


def check_vt():
    print("== VT ==")
    try:
        active = open("/sys/class/tty/console/active").read().split()
        print(f"console active on: {active}")
    except OSError as e:
        print(f"could not read console active: {e}")
    try:
        used = subprocess.run(
            ["fuser", "-v"] + sorted(glob.glob("/dev/tty[1-9]")),
            capture_output=True,
            text=True,
            timeout=10,
        )
        print(f"tty users:\n{used.stderr.strip() or '(none reported)'}")
    except (OSError, subprocess.SubprocessError) as e:
        print(f"fuser unavailable: {e}")


def check_drm():
    print("== DRM ==")
    os.environ["SDL_VIDEODRIVER"] = "kmsdrm"
    try:
        import pygame
    except ImportError:
        print("pygame not installed")
        return False
    try:
        pygame.display.init()
        info = pygame.display.Info()
        print(f"DRM OK as uid={os.getuid()}: {info.current_w}x{info.current_h}")
        pygame.display.quit()
        return True
    except Exception as e:
        print(f"DRM FAILED as uid={os.getuid()}: {e}")
        return False


def check_touch(dev="/dev/input/event5", seconds=15):
    """Report raw touch ranges so calibration can be derived."""
    print("== TOUCH ==")
    EV_ABS, ABS_X, ABS_Y = 0x03, 0x00, 0x01
    fmt = "llHHi"
    size = struct.calcsize(fmt)
    xs, ys = [], []
    print(f"Touch all four corners for {seconds}s... reading {dev}")
    try:
        with open(dev, "rb") as f:
            end = time.time() + seconds
            while time.time() < end:
                if select.select([f], [], [], 0.5)[0]:
                    _, _, typ, code, val = struct.unpack(fmt, f.read(size))
                    if typ == EV_ABS and code == ABS_X:
                        xs.append(val)
                    elif typ == EV_ABS and code == ABS_Y:
                        ys.append(val)
    except OSError as e:
        print(f"could not read {dev}: {e}")
        return
    if xs and ys:
        print(f"ABS_X range: {min(xs)}..{max(xs)}")
        print(f"ABS_Y range: {min(ys)}..{max(ys)}")
        print(
            "Compare against 1280x720: if X range maps to the short edge, "
            "set swap_xy = true in config."
        )
    else:
        print("NO TOUCH EVENTS SEEN")


if __name__ == "__main__":
    check_vt()
    check_drm()
    if "--touch" in sys.argv:
        check_touch()
    else:
        print("== TOUCH ==\n  skipped (pass --touch, requires a human at the panel)")
