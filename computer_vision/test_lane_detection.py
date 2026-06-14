import os, sys
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
"""
Lane Detection Test Script
---------------------------
Tests the UFLD lane detection model on static images.
Generates synthetic highway images if no real images are available.

Usage:
    cd computer_vision
    uv run test_lane_detection.py
    uv run test_lane_detection.py --image path/to/your_road.jpg
    uv run test_lane_detection.py --generate-only
"""

# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "opencv-python>=4.9",
#   "numpy>=1.26",
#   "onnxruntime>=1.17",
# ]
# ///

import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np

# Import from the existing main.py
# We import the detector classes directly to avoid modifying main.py
sys.path.insert(0, str(Path(__file__).parent))
from main import (
    Config,
    Dataset,
    UFLDLaneDetector,
    GreenPaintDetector,
    Detector,
    FrameResult,
    draw_result,
    UFLD_INPUT_W,
    UFLD_INPUT_H,
)

# ---------------------------------------------------------------------------
# Synthetic lane image generation
# ---------------------------------------------------------------------------

def generate_highway_image(width: int = 1280, height: int = 720) -> np.ndarray:
    """Generate a realistic-looking synthetic highway image with lane markings."""
    img = np.zeros((height, width, 3), dtype=np.uint8)

    # Sky gradient (top half)
    for y in range(height // 2):
        ratio = y / (height // 2)
        b = int(200 - ratio * 40)
        g = int(180 - ratio * 30)
        r = int(160 - ratio * 20)
        img[y, :] = (b, g, r)

    # Road surface (bottom half) - dark gray asphalt
    vanishing_y = height // 3
    road_color = (60, 60, 60)

    # Define road edges (perspective lines converging to vanishing point)
    vp_x = width // 2  # vanishing point x
    left_bottom = int(width * 0.05)
    right_bottom = int(width * 0.95)

    # Fill road area
    for y in range(vanishing_y, height):
        t = (y - vanishing_y) / (height - vanishing_y)
        left_x = int(vp_x + (left_bottom - vp_x) * t)
        right_x = int(vp_x + (right_bottom - vp_x) * t)
        # Slight color variation for realism
        shade = int(60 + t * 20)
        img[y, left_x:right_x] = (shade, shade, shade)

    # Lane markings - 4 lanes need 5 lines
    lane_positions = [0.2, 0.4, 0.5, 0.6, 0.8]  # relative positions at bottom

    for i, pos in enumerate(lane_positions):
        bottom_x = int(left_bottom + (right_bottom - left_bottom) * pos)
        # Draw dashed or solid lane lines
        is_center = (i == 2)  # center line is double yellow
        is_edge = (i == 0 or i == 4)

        for y in range(vanishing_y + 5, height):
            t = (y - vanishing_y) / (height - vanishing_y)
            x = int(vp_x + (bottom_x - vp_x) * t)
            line_width = max(1, int(3 * t))

            # Dashed lines for middle lanes, solid for edges
            if is_edge or is_center:
                # Solid line
                color = (0, 200, 200) if is_center else (200, 200, 200)
                cv2.line(img, (x - line_width, y), (x + line_width, y), color, 1)
            else:
                # Dashed line (10px on, 15px off, scaled by perspective)
                dash_len = max(5, int(15 * t))
                gap_len = max(8, int(20 * t))
                segment = (y - vanishing_y) % (dash_len + gap_len)
                if segment < dash_len:
                    cv2.line(img, (x - line_width, y), (x + line_width, y), (200, 200, 200), 1)

    # Add some horizon detail
    cv2.line(img, (0, vanishing_y), (width, vanishing_y), (100, 120, 100), 1)

    return img


def generate_curved_road(width: int = 1280, height: int = 720) -> np.ndarray:
    """Generate a synthetic curved road with lane markings."""
    img = np.zeros((height, width, 3), dtype=np.uint8)

    # Sky
    for y in range(height // 2):
        ratio = y / (height // 2)
        img[y, :] = (int(220 - ratio * 50), int(200 - ratio * 40), int(180 - ratio * 30))

    # Green sides (grass)
    for y in range(height // 3, height):
        for x in range(width):
            t = (y - height // 3) / (height - height // 3)
            # Road center curve
            center_x = width // 2 + int(150 * np.sin(t * 1.5))
            road_half_width = int(50 + 250 * t)

            if abs(x - center_x) > road_half_width:
                # Grass
                green_var = np.random.randint(-10, 10)
                img[y, x] = (30 + green_var, 120 + green_var, 30 + green_var)
            else:
                # Road
                img[y, x] = (70, 70, 70)

    # Lane lines on curved road
    for lane_offset_ratio in [-0.5, 0.0, 0.5]:
        for y in range(height // 3 + 5, height):
            t = (y - height // 3) / (height - height // 3)
            center_x = width // 2 + int(150 * np.sin(t * 1.5))
            road_half_width = int(50 + 250 * t)
            x = int(center_x + road_half_width * lane_offset_ratio)
            line_w = max(1, int(2 * t))

            if lane_offset_ratio == 0.0:
                # Center dashed
                dash = int(12 * t) + 5
                gap = int(18 * t) + 8
                if (y - height // 3) % (dash + gap) < dash:
                    cv2.circle(img, (x, y), line_w, (0, 200, 200), -1)
            else:
                # Edge solid white
                cv2.circle(img, (x, y), line_w, (200, 200, 200), -1)

    return img


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

def test_image(
    detector: Detector,
    image_path: str,
    output_dir: Path,
    label: str = "",
) -> FrameResult:
    """Run detection on a single image and save the annotated result."""
    frame = cv2.imread(image_path)
    if frame is None:
        print(f"  [SKIP] Cannot read: {image_path}")
        return None

    h, w = frame.shape[:2]
    print(f"  Image: {Path(image_path).name}  ({w}x{h})")

    t0 = time.perf_counter()
    result = detector.detect(frame)
    dt = time.perf_counter() - t0

    annotated = draw_result(frame, result)

    # Add timing info
    cv2.putText(
        annotated,
        f"Inference: {dt*1000:.0f}ms",
        (10, h - 20),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (200, 200, 200),
        1,
    )

    # Save output
    stem = Path(image_path).stem
    out_name = f"{stem}_detected.jpg" if not label else f"{label}_{stem}_detected.jpg"
    out_path = output_dir / out_name
    cv2.imwrite(str(out_path), annotated)

    # Print results
    n_lanes = len(result.lanes)
    n_green = len(result.green_regions)
    conf = result.bike_lane_confidence

    status = "✓" if n_lanes > 0 else "✗"
    print(f"  {status} Lanes: {n_lanes}  Green regions: {n_green}  "
          f"Bike-lane confidence: {conf:.0%}  Time: {dt*1000:.0f}ms")

    for lane in result.lanes:
        valid_pts = [p for p in lane.points if p is not None]
        labels = ["L-OUTER", "L-INNER", "R-INNER", "R-OUTER"]
        lane_label = labels[lane.lane_idx] if lane.lane_idx < 4 else f"Lane-{lane.lane_idx}"
        print(f"    {lane_label}: {len(valid_pts)} points")

    print(f"  → Saved: {out_path.name}")
    return result


def main():
    parser = argparse.ArgumentParser(description="Test UFLD lane detection on images")
    parser.add_argument("--image", "-i", type=str, help="Path to a specific image to test")
    parser.add_argument("--image-dir", type=str, help="Directory of images to test")
    parser.add_argument(
        "--model",
        default="models/tusimple.onnx",
        help="Path to ONNX model (default: models/tusimple.onnx)",
    )
    parser.add_argument("--dataset", default="tusimple", choices=["tusimple", "culane"])
    parser.add_argument("--conf", type=float, default=0.5, help="Confidence threshold")
    parser.add_argument("--generate-only", action="store_true", help="Only generate synthetic images")
    parser.add_argument(
        "--output-dir",
        default="../data/lane_tests/results",
        help="Directory to save annotated results",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    test_images_dir = Path("../data/lane_tests")
    test_images_dir.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------------------------
    # Step 1: Generate synthetic test images
    # -----------------------------------------------------------------------
    print("\n" + "=" * 60)
    print("  LANE DETECTION TEST SUITE")
    print("=" * 60)

    print("\n[1/3] Generating synthetic test images...")
    synthetic_images = []

    # Straight highway
    highway = generate_highway_image()
    highway_path = test_images_dir / "synthetic_highway.jpg"
    cv2.imwrite(str(highway_path), highway)
    synthetic_images.append(str(highway_path))
    print(f"  → {highway_path.name} (1280x720)")

    # Curved road
    curved = generate_curved_road()
    curved_path = test_images_dir / "synthetic_curved.jpg"
    cv2.imwrite(str(curved_path), curved)
    synthetic_images.append(str(curved_path))
    print(f"  → {curved_path.name} (1280x720)")

    if args.generate_only:
        print("\n[DONE] Synthetic images generated. Skipping inference.")
        return

    # -----------------------------------------------------------------------
    # Step 2: Load model
    # -----------------------------------------------------------------------
    print(f"\n[2/3] Loading model: {args.model}")
    model_path = Path(args.model)
    if not model_path.exists():
        # Try relative to computer_vision dir
        alt = Path(__file__).parent / args.model
        if alt.exists():
            model_path = alt
        else:
            print(f"\n  ✗ Model not found at {args.model}")
            print(f"    Also checked: {alt}")
            print(f"\n  The model archive is likely still downloading.")
            print(f"  Once downloaded, extract the ONNX model and run this test again.")
            print(f"  Expected path: computer_vision/models/tusimple.onnx")
            sys.exit(1)

    cfg = Config(
        model_path=str(model_path),
        dataset=Dataset(args.dataset),
        lane_conf_threshold=args.conf,
        show_window=False,
        save_frames=False,
    )

    try:
        detector = Detector(cfg)
    except Exception as e:
        print(f"  ✗ Failed to load model: {e}")
        sys.exit(1)

    print(f"  ✓ Model loaded successfully")

    # -----------------------------------------------------------------------
    # Step 3: Run tests
    # -----------------------------------------------------------------------
    print(f"\n[3/3] Running lane detection tests...")
    print("-" * 60)

    all_images = []

    # Add specific image if provided
    if args.image:
        all_images.append(args.image)

    # Add directory images
    if args.image_dir:
        img_dir = Path(args.image_dir)
        for ext in ("*.jpg", "*.jpeg", "*.png", "*.bmp"):
            all_images.extend(str(p) for p in img_dir.glob(ext))

    # Add synthetic images
    all_images.extend(synthetic_images)

    # Add any existing test images (but not previously generated results)
    for ext in ("*.jpg", "*.jpeg", "*.png"):
        for p in test_images_dir.glob(ext):
            if "_detected" not in p.stem and str(p) not in all_images:
                all_images.append(str(p))

    if not all_images:
        print("  No test images found!")
        return

    total_lanes = 0
    total_time = 0.0
    results = []

    for i, img_path in enumerate(all_images):
        print(f"\n  Test {i+1}/{len(all_images)}")
        t0 = time.perf_counter()
        result = test_image(detector, img_path, output_dir)
        dt = time.perf_counter() - t0

        if result:
            total_lanes += len(result.lanes)
            total_time += dt
            results.append((img_path, result))

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    print("\n" + "=" * 60)
    print("  TEST SUMMARY")
    print("=" * 60)
    print(f"  Images tested:     {len(results)}")
    print(f"  Total lanes found: {total_lanes}")
    print(f"  Avg time/image:    {total_time/max(len(results),1)*1000:.0f}ms")
    print(f"  Results saved to:  {output_dir.resolve()}")
    print("=" * 60)

    # List output files
    print("\n  Output files:")
    for f in sorted(output_dir.glob("*_detected.*")):
        print(f"    {f.name}  ({f.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
