"""
Script Name: wiggler.py
Description:
    Industrial image processing utility for creating 'wiggle' GIFs from multi-camera
    captures. Handles image loading (with EXIF correction), focus point remapping,
    precise cropping for alignment across frames, and high-quality GIF generation.
"""

#all code written by me with minimal AI assistance, comments added using AI and verified by me

import time
from tracemalloc import start
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
import argparse
from pathlib import Path
import os
import sys
from PIL import Image, ImageOps
import numpy as np
import shutil
import traceback
from typing import Optional, Callable
from concurrent.futures import ThreadPoolExecutor
import faulthandler
import threading

IMAGES_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', 'images'))
PROCESSING_DIR = os.path.join(IMAGES_DIR, 'processing')
RAWS_DIR = os.path.join(IMAGES_DIR, 'raws')

def _ensure_dirs():
    """Ensures that the processing and raw image directories exist."""
    os.makedirs(PROCESSING_DIR, exist_ok=True)
    os.makedirs(RAWS_DIR, exist_ok=True)

_ensure_dirs()

_COMMON_EXTS = (".jpg", ".jpeg", ".png")

def _install_error_hooks():
    """Sets up robust error logging to stderr for both main and background threads."""
    try:
        faulthandler.enable()
    except Exception:
        pass

    def _excepthook(exc_type, exc, tb):
        try:
            traceback.print_exception(exc_type, exc, tb, file=sys.stderr)
            sys.stderr.flush()
        except Exception:
            pass

    try:
        sys.excepthook = _excepthook
    except Exception:
        pass

    # Python 3.8+: capture exceptions in threads as well
    try:
        if hasattr(threading, 'excepthook'):
            def _thread_excepthook(args):
                try:
                    traceback.print_exception(args.exc_type, args.exc_value, args.exc_traceback, file=sys.stderr)
                    sys.stderr.flush()
                except Exception:
                    pass
            threading.excepthook = _thread_excepthook
    except Exception:
        pass

_install_error_hooks()

# --- Image I/O helpers to normalize EXIF orientation and strip it on save ---

def _resolve_existing(base_path_no_ext: str) -> Optional[str]:
    """Resolves an existing file path by checking common image extensions."""
    """Return first existing path among common extensions for given base without ext."""
    for ext in _COMMON_EXTS:
        p = base_path_no_ext + ext
        if os.path.exists(p):
            return p
    return None
def _load_image_corrected(path: str):
    """Loads an image and applies EXIF orientation to ensure canonical pixel data."""
    """Load an image with EXIF orientation applied, return as NumPy array."""
    img = Image.open(path)
    try:
        # Apply EXIF orientation so width/height and pixel data are canonical
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass
    return np.array(img)


def _resolve_gif_or_first_jpg(path: str) -> Optional[str]:
    """Smart resolver that maps a GIF result back to its first source frame for UI usage."""
    """If given a .gif path that doesn't exist, resolve to a matching "_1" image.

    Rules:
      - If the exact path exists, return it.
      - If it ends with .gif and doesn't exist, try replacing with "_1" and one of
        the common extensions in the SAME directory. If not found, try IMAGES_DIR
        and then RAWS_DIR with the same base name.
      - If there's no extension, try .gif, else fallback to "_1" with common exts.
    """
    if not path:
        return None
    if os.path.exists(path):
        return path

    base_dir, name = os.path.split(path)
    stem, ext = os.path.splitext(name)
    ext = ext.lower()

    def _try_first_in(dir_path: str) -> Optional[str]:
        base_no_ext = os.path.join(dir_path, stem + "_1")
        return _resolve_existing(base_no_ext)

    if ext == ".gif":
        # 1) Try alongside the provided path
        if base_dir:
            cand = _try_first_in(base_dir)
            if cand:
                return cand
        # 2) Try images folder
        cand = _try_first_in(IMAGES_DIR)
        if cand:
            return cand
        # 3) Try raws folder
        cand = _try_first_in(RAWS_DIR)
        if cand:
            return cand
        return None

    if ext == "":
        # Try a .gif first
        gif_try = path + ".gif"
        if os.path.exists(gif_try):
            return gif_try
        # Else same fallback rules as above
        if base_dir:
            cand = _resolve_existing(os.path.join(base_dir, stem + "_1"))
            if cand:
                return cand
        cand = _resolve_existing(os.path.join(IMAGES_DIR, stem + "_1"))
        if cand:
            return cand
        cand = _resolve_existing(os.path.join(RAWS_DIR, stem + "_1"))
        if cand:
            return cand
        return None

    # For other extensions, just return None (caller may handle differently)
    return None


def _raw_aspect(filename: str) -> Optional[float]:
    """Computes the native aspect ratio (H/W) from the first raw frame of a capture."""
    """Compute H/W from the first existing RAW (index 1)."""
    base_no_ext = os.path.join(RAWS_DIR, f"{filename}_1")
    p = _resolve_existing(base_no_ext)
    if not p:
        return None
    img = _load_image_corrected(p)
    H, W = img.shape[0], img.shape[1]
    if W == 0:
        return None
    return H / W


def _to_uint8(arr: np.ndarray) -> np.ndarray:
    """Safely converts a NumPy array to uint8 format for image saving."""
    if arr.dtype == np.float32 or arr.dtype == np.float64:
        arr = np.clip(arr * 255.0, 0, 255).astype(np.uint8)
    elif arr.dtype != np.uint8:
        arr = np.clip(arr, 0, 255).astype(np.uint8)
    return arr


def _array_to_pil(arr: np.ndarray) -> Image.Image:
    """Converts a NumPy array to a PIL Image with appropriate mode detection."""
    arr = _to_uint8(arr)
    arr = np.ascontiguousarray(arr)
    if arr.ndim == 2:
        mode = "L"
    elif arr.ndim == 3 and arr.shape[2] == 3:
        mode = "RGB"
    elif arr.ndim == 3 and arr.shape[2] == 4:
        mode = "RGBA"
    else:
        # Fallback: convert via PIL fromarray default
        return Image.fromarray(arr)
    return Image.fromarray(arr, mode)


def _save_image_no_exif(path: str, arr: np.ndarray) -> None:
    """Saves a NumPy array as an image file while stripping all EXIF metadata."""
    """Save array as JPEG/PNG while stripping EXIF (incl. orientation)."""
    # Guard against empty crops (zero width/height) before converting
    if arr is None or arr.ndim < 2 or arr.shape[0] == 0 or arr.shape[1] == 0:
        raise ValueError("Attempting to save empty image (zero dimension).")
    img = _array_to_pil(arr)
    ext = os.path.splitext(path)[1].lower()
    save_kwargs = {}
    if ext in (".jpg", ".jpeg"):
        save_kwargs["quality"] = 95
        # Ensure no EXIF is written back (default is none unless provided)
    img.save(path, **save_kwargs)

def pick_point(image_path: str):
    """Launches a Matplotlib window for manual selection of a focus point on an image."""
    # Allow callers to pass a .gif reference; map to a matching _1.jpg if needed
    resolved = _resolve_gif_or_first_jpg(image_path) or image_path
    img = _load_image_corrected(resolved)

    fig, ax = plt.subplots()
    fig.canvas.manager.toolbar_visible = False  # hide toolbar (new Matplotlib versions)

    ax.imshow(img)
    ax.axis("off")  # no ticks or border

    clicked = {"xy": None}

    def on_click(event):
        if event.inaxes is ax and event.xdata is not None and event.ydata is not None:
            clicked["xy"] = (int(round(event.xdata)), int(round(event.ydata)))
            plt.close(fig)

    fig.canvas.mpl_connect("button_press_event", on_click)
    plt.show()
    return clicked["xy"]

def crop_image_sides(image_path: str, crop_x: int, crop_y: int, W, H, center_x_percentage: float, center_y_percentage: float):
    """
    Performs a single-sided crop and aspect ratio correction based on focus alignment data.
    """
    # Accept .gif references and resolve to the corresponding _1.jpg in-place
    resolved = _resolve_gif_or_first_jpg(image_path) or image_path
    img = _load_image_corrected(resolved)

    # Round crop values
    crop_x = int(round(crop_x))
    crop_y = int(round(crop_y))

    # Clamp requested crops so at least 1 pixel remains
    max_crop_x = max(0, int(W) - 1)
    max_crop_y = max(0, int(H) - 1)
    crop_x = max(-max_crop_x, min(max_crop_x, crop_x))
    crop_y = max(-max_crop_y, min(max_crop_y, crop_y))

    # Crop X (left/right)
    if crop_x > 0:
        # Positive: crop from LEFT
        start_x = crop_x
        end_x = W
    elif crop_x < 0:
        # Negative: crop from RIGHT
        start_x = 0
        end_x = W - abs(crop_x)
    else:
        start_x = 0
        end_x = W

    # Crop Y (top/bottom)
    if crop_y > 0:
        # Positive: crop from TOP
        start_y = abs(crop_y)
        end_y = H
    elif crop_y < 0:
        # Negative: crop from BOTTOM
        start_y = 0
        end_y = H - abs(crop_y)
    else:
        start_y = 0
        end_y = H

    # Ensure bounds
    start_x = max(0, min(start_x, W))
    end_x = max(0, min(end_x, W))
    start_y = max(0, min(start_y, H))
    end_y = max(0, min(end_y, H))

    # Ensure at least 1 pixel in each dimension
    if end_x - start_x <= 0:
        start_x = max(0, min(W - 1, start_x))
        end_x = start_x + 1
    if end_y - start_y <= 0:
        start_y = max(0, min(H - 1, start_y))
        end_y = start_y + 1

    ## Recompute after aspect fix
    cropped_width = end_x - start_x
    cropped_height = end_y - start_y

    original_aspect = W / H  # width divided by height from the EXIF-corrected image
    current_aspect = cropped_width / cropped_height

    if current_aspect > original_aspect:
        # Too wide: reduce width to match aspect, split using center_x_percentage
        target_width = int(round(cropped_height * original_aspect))
        delta_w = cropped_width - target_width
        if delta_w > 0:
            cut_left = int(round(delta_w * center_x_percentage))
            cut_right = delta_w - cut_left
            start_x += cut_left
            end_x -= cut_right

    elif current_aspect < original_aspect:
        # Too tall: reduce height to match aspect, split using center_y_percentage
        target_height = int(round(cropped_width / original_aspect))
        delta_h = cropped_height - target_height
        if delta_h > 0:
            cut_top = int(round(delta_h * center_y_percentage))
            cut_bottom = delta_h - cut_top
            start_y += cut_top
            end_y -= cut_bottom

    # Ensure integer and clamp to image bounds before slicing
    start_x = int(round(start_x))
    end_x   = int(round(end_x))
    start_y = int(round(start_y))
    end_y   = int(round(end_y))

    img_cropped = img[start_y:end_y, start_x:end_x, ...]

    # Save cropped image
    base_in = os.path.splitext(os.path.basename(image_path))[0]
    out_path = os.path.join(PROCESSING_DIR, base_in + "_cropped.jpg")
    _save_image_no_exif(out_path, img_cropped)

    return img_cropped.shape[0]


def adjustZoom(filename, minHeight, centerXpercentage, centerYpercentage):
    """
    Aligns multiple frames by creating consistent crops around their focus centers.
    Ensures every frame has identical border distances to prevent 'jumping'.
    """

    # Resolve inputs: prefer cropped; otherwise fall back to RAWs
    cropped_bases = [os.path.join(PROCESSING_DIR, f"{filename}_{i}_cropped") for i in range(1, 5)]
    raw_bases     = [os.path.join(RAWS_DIR,       f"{filename}_{i}")        for i in range(1, 5)]

    inputs = []
    for cb, rb in zip(cropped_bases, raw_bases):
        p = _resolve_existing(cb) or _resolve_existing(rb)
        inputs.append(p)

    # Load images and collect shapes
    imgs = []
    shapes = []  # list of (H, W)
    for p in inputs:
        if p:
            arr = _load_image_corrected(p)
            imgs.append(arr)
            shapes.append((arr.shape[0], arr.shape[1]))
        else:
            imgs.append(None)
            shapes.append((0, 0))

    # Choose reference frame: smallest height (ties: first occurrence)
    ref_idx = None
    ref_H = None
    for i, (H, W) in enumerate(shapes):
        if H <= 0 or W <= 0:
            continue
        if ref_H is None or H < ref_H:
            ref_H = H
            ref_idx = i

    if ref_idx is None:
        # No valid inputs; nothing to do
        return

    # Reference frame sizes and center in pixels
    H_ref, W_ref = shapes[ref_idx]
    cx_ref = int(round(float(centerXpercentage) * (W_ref - 1)))
    cy_ref = int(round(float(centerYpercentage) * (H_ref - 1)))

    # Border distances for the reference frame (inclusive-center accounting)
    # Desired window size is exactly the reference frame size.
    left_d   = cx_ref
    right_d  = (W_ref - 1) - cx_ref
    top_d    = cy_ref
    bottom_d = (H_ref - 1) - cy_ref

    # Derived reference window size (exclusive slicing uses width/height below)
    ref_width  = left_d + 1 + right_d
    ref_height = top_d  + 1 + bottom_d

    # Safety: the math above must give exactly the reference size
    # but round safeguards ensure consistent slicing.

    for idx, (arr, (H, W)) in enumerate(zip(imgs, shapes), start=1):
        if arr is None or H <= 0 or W <= 0:
            continue

        # Center for this frame in pixels
        cx = int(round(float(centerXpercentage) * (W - 1)))
        cy = int(round(float(centerYpercentage) * (H - 1)))

        # Initial window matching reference border distances
        start_x = cx - left_d
        end_x   = start_x + ref_width
        start_y = cy - top_d
        end_y   = start_y + ref_height

        # If the window is out of bounds, we SHIFT it (do not resize) to fit.
        # Horizontal shift
        if start_x < 0:
            shift = -start_x
            start_x += shift
            end_x   += shift
        if end_x > W:
            shift = end_x - W
            start_x -= shift
            end_x   -= shift
        # Vertical shift
        if start_y < 0:
            shift = -start_y
            start_y += shift
            end_y   += shift
        if end_y > H:
            shift = end_y - H
            start_y -= shift
            end_y   -= shift

        # Final clamp and integerize
        start_x = max(0, min(start_x, W))
        end_x   = max(0, min(end_x,   W))
        start_y = max(0, min(start_y, H))
        end_y   = max(0, min(end_y,   H))

        # As a last resort, if some frame is actually smaller than the
        # reference size (should not happen because we picked the smallest
        # as reference), reduce the window to fit while keeping the same
        # center pixel. This prevents crashes without introducing scaling.
        cur_w = end_x - start_x
        cur_h = end_y - start_y
        if cur_w <= 0 or cur_h <= 0:
            # Fallback to at least a 1x1 crop at (cx, cy)
            start_x = max(0, min(cx, W - 1))
            start_y = max(0, min(cy, H - 1))
            end_x = min(W, start_x + 1)
            end_y = min(H, start_y + 1)
        elif cur_w != ref_width or cur_h != ref_height:
            # Resize the window symmetrically around (cx, cy) to the max possible
            # that fits, but capped by the reference size.
            half_w_left  = min(left_d,  cx)
            half_w_right = min(right_d, (W - 1) - cx)
            half_h_top   = min(top_d,   cy)
            half_h_bot   = min(bottom_d,(H - 1) - cy)
            # Recompute start/end so they fit while staying as close as possible
            start_x = cx - half_w_left
            end_x   = cx + half_w_right + 1
            start_y = cy - half_h_top
            end_y   = cy + half_h_bot + 1

        # Perform crop (exclusive slicing)
        img2 = arr[start_y:end_y, start_x:end_x, ...]

        out_path = os.path.join(PROCESSING_DIR, f"{filename}_{idx}_zoom.jpg")
        _save_image_no_exif(out_path, img2)

def convertToGif(filename, speed) -> bool:
    """
    Assembles a sequence of aligned frames into an animated GIF.
    Includes forward/backward boomerang effect and color quantization.
    """
    bases = [os.path.join(PROCESSING_DIR, f"{filename}_{i}_zoom") for i in range(1, 5)]

    # Load frames (already saved without EXIF by _save_image_no_exif)
    frames = []
    for b in bases:
        p = _resolve_existing(b)
        if p and os.path.exists(p):
            pil = Image.open(p)
            try:
                frames.append(pil.convert("RGB"))
            finally:
                try:
                    pil.close()
                except Exception:
                    pass

    if not frames:
        return False

    # Create forward and backward sequence (exclude duplicate endpoints)
    if len(frames) > 1:
        base_seq = frames + frames[-2:0:-1]
    else:
        base_seq = frames

    try:
        method = Image.Quantize.FASTOCTREE
        #dither = Image.Dither.NONE
        dither = Image.Dither.FLOYDSTEINBERG
    except AttributeError:
        method = 2  # FASTOCTREE fallback for older Pillow
        #dither = 0  # NONE
        dither = 1  # FLOYDSTEINBERG

    try:
        first_p = base_seq[0].quantize(colors=256, method=method, dither=dither)
    except Exception:
        # Fallback to default quantize if FASTOCTREE not available
        first_p = base_seq[0].quantize(colors=256)
    pal = first_p.getpalette()
    pal_frames = [first_p]
    for im in base_seq[1:]:
        try:
            q = im.quantize(palette=first_p, dither=dither)
        except Exception:
            q = im.quantize(colors=256)
        if q.getpalette() is None and pal is not None:
            try:
                q.putpalette(pal)
            except Exception:
                pass
        pal_frames.append(q)

    gif_out = os.path.join(IMAGES_DIR, f"{filename}.gif")
    # Remove existing gif if present
    if os.path.exists(gif_out):
        try:
            os.remove(gif_out)
        except OSError:
            pass

    try:
        pal_frames[0].save(
            gif_out,
            save_all=True,
            append_images=pal_frames[1:],
            duration=int(speed),  # ms per frame
            loop=0,
            disposal=2,       # replace frame for robustness
            optimize=False    # keep off for speed
        )
    except Exception as e:
        report_error("Error saving GIF", e)
        return False

    # Cleanup generated intermediates
    for b in bases:
        p = _resolve_existing(b)
        if p and os.path.exists(p):
            try:
                os.remove(p)
            except OSError:
                pass
    for i in range(1, 5):
        cropped_path = os.path.join(PROCESSING_DIR, f"{filename}_{i}_cropped.jpg")
        if os.path.exists(cropped_path):
            try:
                os.remove(cropped_path)
            except OSError:
                pass
    success = os.path.exists(gif_out)
    if success:
        # Remove the sample image copy in the images folder (leave RAWs intact)
        sample_path = os.path.join(IMAGES_DIR, f"{filename}_1.png")
        if os.path.exists(sample_path):
            try:
                os.remove(sample_path)
            except OSError:
                pass

    return success

def report_error(prefix: str, e: Exception):
    """Prints a formatted error message and traceback to stderr."""
    try:
        msg = f"{prefix}: {e}"
        print(f"ERROR: {msg}", file=sys.stderr, flush=True)
        tb = traceback.format_exc()
        if tb:
            print(tb, file=sys.stderr, flush=True)
    except Exception:
        # As a last resort, avoid raising inside error handler
        pass

def calculateCrop(fullSize, focus, center):
    """
    Calculates the exact pixel crop required to move a focus point to the target center.
    """
    percentageLeftCenter = center / fullSize
    percentageRightCenter = 1.0 - percentageLeftCenter

    #crop right
    if focus < center:
        entireSize = focus / percentageLeftCenter
        crop = fullSize - entireSize
        crop = -crop
    else:
        #crop left
        entireSize = (fullSize - focus) / percentageRightCenter
        crop = fullSize - entireSize


    return int(round(crop))

def remapCoordinates(focus, original_image_size):
    """Remaps focus coordinates to account for physical sensor orientation/flipping."""
    x = focus[0]
    y = focus[1]

    x = original_image_size[1] - x

    return (x, y)

def remapFullSize(originalImageSize):
    """Swaps width and height if the sensor orientation is rotated."""
    width = originalImageSize[1]
    height = originalImageSize[0]
    return (width, height)

def fullFunction(filename, focus1, focus2, focus3, focus4, speed, images_dir_str=None):
    """
    High-level entry point that orchestrates the entire alignment and GIF-creation pipeline.
    """
    global IMAGES_DIR, PROCESSING_DIR, RAWS_DIR
    
    if images_dir_str:
        IMAGES_DIR = os.path.abspath(images_dir_str)
        PROCESSING_DIR = os.path.join(IMAGES_DIR, 'processing')
        RAWS_DIR = os.path.join(IMAGES_DIR, 'raws')
        _ensure_dirs()

    print(f"DEBUG: IMAGES_DIR={IMAGES_DIR}")
    print(f"DEBUG: RAWS_DIR={RAWS_DIR}")

    mainstart = time.time()
    try:
        print("idkf2")

        print(f"fullFunction called with: filename={filename}, focus1={focus1}, focus2={focus2}, focus3={focus3}, focus4={focus4}, speed={speed}, images_dir={images_dir_str}")

        # Resolve available raw paths for frames 1..4 (support .jpg/.jpeg/.png)
        resolved_raws = []
        for i in range(1, 5):
            base_no_ext = os.path.join(RAWS_DIR, f"{filename}_{i}")
            p = _resolve_existing(base_no_ext)
            print(f"DEBUG: Checking {base_no_ext} -> {p}")
            resolved_raws.append(p)

        # Get the original image size (H, W): prefer frame 1, else first available
        originalImageSize = None
        pref = resolved_raws[0] if resolved_raws and resolved_raws[0] else None
        src_for_size = pref or next((p for p in resolved_raws if p), None)
        if src_for_size:
            img = _load_image_corrected(src_for_size)
            originalImageSize = (img.shape[0], img.shape[1])
        if originalImageSize is None:
            raise FileNotFoundError("No RAW inputs found for base name '%s'" % filename)

        focus1 = remapCoordinates(focus1, originalImageSize)
        focus2 = remapCoordinates(focus2, originalImageSize)
        focus3 = remapCoordinates(focus3, originalImageSize)
        focus4 = remapCoordinates(focus4, originalImageSize)

        originalImageSize = remapFullSize(originalImageSize)

        centerx = (focus1[0] + focus2[0] + focus3[0] + focus4[0]) / 4
        centery = (focus1[1] + focus2[1] + focus3[1] + focus4[1]) / 4

        # Percentages must be normalized by width for x and height for y
        centerxPercentage = centerx / originalImageSize[0]
        centeryPercentage = centery / originalImageSize[1]

        start = time.time()
        crop1x = calculateCrop(originalImageSize[0], focus1[0], centerx)
        crop2x = calculateCrop(originalImageSize[0], focus2[0], centerx)
        crop3x = calculateCrop(originalImageSize[0], focus3[0], centerx)
        crop4x = calculateCrop(originalImageSize[0], focus4[0], centerx)

        crop1y = calculateCrop(originalImageSize[1], focus1[1], centery)
        crop2y = calculateCrop(originalImageSize[1], focus2[1], centery)
        crop3y = calculateCrop(originalImageSize[1], focus3[1], centery)
        crop4y = calculateCrop(originalImageSize[1], focus4[1], centery)
        end = time.time()
        print(f"calculateCrop took {end - start:.2f} seconds")

        # Run the crops in parallel for existing frames (I/O-bound work benefits from threads)
        per_frame_crops = [
            (resolved_raws[0], crop1x, crop1y),
            (resolved_raws[1], crop2x, crop2y),
            (resolved_raws[2], crop3x, crop3y),
            (resolved_raws[3], crop4x, crop4y),
        ]
        crop_args = [(p, cx, cy) for (p, cx, cy) in per_frame_crops if p]
        if not crop_args:
            raise FileNotFoundError("No source frames found to crop for '%s'" % filename)

        start = time.time()
        def _run_crop(path, cx, cy):
            return crop_image_sides(
                path,
                cx,
                cy,
                originalImageSize[0],
                originalImageSize[1],
                centerxPercentage,
                centeryPercentage,
            )

        with ThreadPoolExecutor(max_workers=4) as ex:
            futures = [ex.submit(_run_crop, p, cx, cy) for (p, cx, cy) in crop_args]
            heights = [f.result() for f in futures]
        end = time.time()
        print(f"crop_image_sides took {end - start:.2f} seconds")

        targetH = min(heights)
        
        start = time.time()
        adjustZoom(filename, targetH, centerxPercentage, centeryPercentage)
        end = time.time()
        print(f"adjustZoom took {end - start:.2f} seconds")

        start = time.time()
        ok = convertToGif(filename, speed)
        end = time.time()
        print(f"convertToGif took {end - start:.2f} seconds")

        mainend = time.time()
        print(f"fullFunction took {mainend - mainstart:.2f} seconds")
        
        if not ok:
            raise FileNotFoundError(f"GIF not created for '{filename}'")
    except Exception as e:
        report_error("Error in fullFunction", e)
        raise



# ------------------ CLI entry point ------------------
if __name__ == "__main__":
    try:
        import argparse
        parser = argparse.ArgumentParser(description="Run wiggler fullFunction for image cropping and GIF creation.")
        parser.add_argument("filename", type=str, help="Base filename (without _1.jpg etc)")
        parser.add_argument("focus1", type=int, nargs=2, metavar="F1", help="Focus point 1 as: x y")
        parser.add_argument("focus2", type=int, nargs=2, metavar="F2", help="Focus point 2 as: x y")
        parser.add_argument("focus3", type=int, nargs=2, metavar="F3", help="Focus point 3 as: x y")
        parser.add_argument("focus4", type=int, nargs=2, metavar="F4", help="Focus point 4 as: x y")
        parser.add_argument("--speed", type=int, default=150, help="GIF frame speed in ms (default: 200)")
        parser.add_argument("--images-dir", type=str, default=None, help="Path to images directory")
        args = parser.parse_args()

        # Call the main function
        fullFunction(
            args.filename,
            tuple(args.focus1),
            tuple(args.focus2),
            tuple(args.focus3),
            tuple(args.focus4),
            args.speed,
            args.images_dir
        )
    except Exception as e:
        report_error("Error in __main__", e)
        sys.exit(1)



#all code written by me with minimal AI assistance, comments added using AI and verified by me