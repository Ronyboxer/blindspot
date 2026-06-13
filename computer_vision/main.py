"""
Bike Road Marking Detector
--------------------------
Lane detection via Ultra-Fast-Lane-Detection (UFLD) ONNX model.
Green bike lane paint detection via HSV masking.

Model source (ONNX, no PyTorch needed):
  PINTO0309/PINTO_model_zoo — entry 140_Ultra-Fast-Lane-Detection
  Download script: see README.md or run download_model.sh

Runs on desktop (webcam/video). Swap --backend picamera2 for Pi.

Usage:
    uv run main.py
    uv run main.py --source video.mp4
    uv run main.py --model models/tusimple.onnx --dataset tusimple
    uv run main.py --backend picamera2 --no-window
    uv run main.py --debug
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
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
import onnxruntime as ort

# ---------------------------------------------------------------------------
# UFLD model constants
# ---------------------------------------------------------------------------

class Dataset(Enum):
    TUSIMPLE = "tusimple"
    CULANE   = "culane"

# These are fixed by how the model was trained — do not change.
UFLD_INPUT_W = 800
UFLD_INPUT_H = 288

DATASET_CFG = {
    Dataset.TUSIMPLE: {
        "griding_num":     100,
        "cls_num_per_lane": 56,
        # Row anchors: vertical positions (in 288px input space) where lanes are sampled
        "row_anchors": [
            64, 68, 72, 76, 80, 84, 88, 92, 96, 100,
           104,108,112,116,120,124,128,132,136,140,
           144,148,152,156,160,164,168,172,176,180,
           184,188,192,196,200,204,208,212,216,220,
           224,228,232,236,240,244,248,252,256,260,
           264,268,272,276,280,284
        ],
        "img_w": 1280,
        "img_h": 720,
    },
    Dataset.CULANE: {
        "griding_num":     200,
        "cls_num_per_lane": 18,
        "row_anchors": [
            121,131,141,150,160,170,180,189,199,
            209,219,228,238,248,258,267,277,287
        ],
        "img_w": 1640,
        "img_h": 590,
    },
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

@dataclass
class Config:
    # Camera
    camera_backend: str = "opencv"
    source: str | int = 0
    frame_width:  int = 640
    frame_height: int = 480

    # Model
    model_path: str = "models/tusimple.onnx"
    dataset:   Dataset = Dataset.TUSIMPLE

    # Green paint HSV
    green_hsv_lower: tuple = (35, 40, 40)
    green_hsv_upper: tuple = (90, 255, 255)
    green_min_area:  int   = 800

    # Lane confidence threshold — UFLD outputs a softmax over grid positions
    # plus a "no lane" class; we accept a lane point if its max class prob
    # exceeds this value.
    lane_conf_threshold: float = 0.6

    # Display
    show_window:  bool = True
    save_frames:  bool = False
    debug:        bool = False
    output_dir:   str  = "detections"

# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------

@dataclass
class GreenRegion:
    contour:      np.ndarray
    area:         float
    centroid:     tuple[int, int]
    bounding_rect: tuple[int, int, int, int]


@dataclass
class Lane:
    """
    A detected lane as a list of (x, y) points in original frame coords.
    Points may have gaps where the model had low confidence.
    """
    points:    list[Optional[tuple[int, int]]]  # None = no detection at that row
    lane_idx:  int    # 0=leftmost, 1=left, 2=right, 3=rightmost


@dataclass
class FrameResult:
    timestamp:     float
    green_regions: list[GreenRegion] = field(default_factory=list)
    lanes:         list[Lane]        = field(default_factory=list)
    bike_lane_confidence: float      = 0.0

    @property
    def has_detections(self) -> bool:
        return bool(self.green_regions or self.lanes)

# ---------------------------------------------------------------------------
# Camera backends
# ---------------------------------------------------------------------------

class CameraBackend:
    def read(self) -> tuple[bool, Optional[np.ndarray]]: raise NotImplementedError
    def release(self): pass

class OpenCVCamera(CameraBackend):
    def __init__(self, source, w, h):
        idx = int(source) if str(source).isdigit() else source
        self.cap = cv2.VideoCapture(idx)
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH,  w)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
        if not self.cap.isOpened():
            raise RuntimeError(f"Cannot open: {source!r}")
    def read(self): return self.cap.read()
    def release(self): self.cap.release()

class PiCamera2Backend(CameraBackend):
    def __init__(self, w, h):
        try:
            from picamera2 import Picamera2  # type: ignore
        except ImportError:
            raise RuntimeError("sudo apt install -y python3-picamera2")
        self.cam = Picamera2()
        self.cam.configure(self.cam.create_preview_configuration(
            main={"size": (w, h), "format": "RGB888"}
        ))
        self.cam.start()
        time.sleep(0.5)
    def read(self):
        return True, cv2.cvtColor(self.cam.capture_array(), cv2.COLOR_RGB2BGR)
    def release(self): self.cam.stop()

def build_camera(cfg: Config) -> CameraBackend:
    if cfg.camera_backend == "picamera2":
        return PiCamera2Backend(cfg.frame_width, cfg.frame_height)
    return OpenCVCamera(cfg.source, cfg.frame_width, cfg.frame_height)

# ---------------------------------------------------------------------------
# UFLD inference
# ---------------------------------------------------------------------------

class UFLDLaneDetector:
    """
    Wraps the UFLD ONNX model.

    The model treats lane detection as a classification problem: for each of
    N row anchors and each of 4 lane slots, it predicts a probability
    distribution over (griding_num + 1) horizontal grid cells, where the
    last cell is the "no lane here" class.
    """

    def __init__(self, cfg: Config):
        self.cfg     = cfg
        self.ds_cfg  = DATASET_CFG[cfg.dataset]
        self.session = self._load_session()

        # Mean/std for ImageNet normalisation (what the model was trained with)
        self.mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        self.std  = np.array([0.229, 0.224, 0.225], dtype=np.float32)

    def _load_session(self) -> ort.InferenceSession:
        path = Path(self.cfg.model_path)
        if not path.exists():
            print(
                f"\n[ufld] Model not found at {path}\n"
                f"       Run:  bash download_model.sh\n"
                f"       Or see README.md for manual download instructions.\n",
                file=sys.stderr,
            )
            sys.exit(1)

        providers = ["CPUExecutionProvider"]
        sess = ort.InferenceSession(str(path), providers=providers)
        print(f"[ufld] Loaded {path.name}  "
              f"input={sess.get_inputs()[0].shape}  "
              f"dataset={self.cfg.dataset.value}")
        return sess

    def _preprocess(self, frame: np.ndarray) -> np.ndarray:
        """BGR frame → normalised CHW float32 blob."""
        rgb   = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        resized = cv2.resize(rgb, (UFLD_INPUT_W, UFLD_INPUT_H))
        norm  = (resized.astype(np.float32) / 255.0 - self.mean) / self.std
        chw   = norm.transpose(2, 0, 1)          # HWC → CHW
        return chw[np.newaxis, ...]               # → NCHW

    def _postprocess(
        self,
        output: np.ndarray,
        orig_w: int,
        orig_h: int,
    ) -> list[Lane]:
        """
        output shape: (1, griding_num+1, cls_num_per_lane, 4)
        Returns up to 4 Lane objects in original frame pixel coordinates.
        """
        ds      = self.ds_cfg
        gn      = ds["griding_num"]
        anchors = ds["row_anchors"]
        tw, th  = ds["img_w"], ds["img_h"]

        # Remove batch dim → (gn+1, cls_num, 4)
        out = output[0]

        lanes = []
        for lane_idx in range(4):
            lane_col = out[:, :, lane_idx]   # (gn+1, cls_num)

            points: list[Optional[tuple[int, int]]] = []

            for row_idx, anchor_y in enumerate(anchors):
                logits = lane_col[:, row_idx]           # (gn+1,)
                probs  = softmax(logits)
                no_lane_prob = probs[-1]

                if no_lane_prob > (1 - self.cfg.lane_conf_threshold):
                    points.append(None)
                    continue

                # Weighted average of grid positions (exclude no-lane class)
                grid_probs = probs[:-1]
                grid_pos   = np.arange(gn, dtype=np.float32)
                loc        = float(np.sum(grid_probs * grid_pos) / (np.sum(grid_probs) + 1e-6))

                # Map from model's training resolution to original frame size
                x_in_train = loc / gn * tw
                y_in_train = anchor_y / UFLD_INPUT_H * th

                x = int(x_in_train / tw  * orig_w)
                y = int(y_in_train / th  * orig_h)
                points.append((x, y))

            # Only include lane if it has enough valid points
            valid = [p for p in points if p is not None]
            if len(valid) >= 2:
                lanes.append(Lane(points=points, lane_idx=lane_idx))

        return lanes

    def detect(self, frame: np.ndarray) -> list[Lane]:
        blob   = self._preprocess(frame)
        output = self.session.run(None, {self.session.get_inputs()[0].name: blob})[0]
        return self._postprocess(output, frame.shape[1], frame.shape[0])


def softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - x.max())
    return e / e.sum()

# ---------------------------------------------------------------------------
# Green paint detector (unchanged)
# ---------------------------------------------------------------------------

class GreenPaintDetector:
    def __init__(self, cfg: Config):
        self.cfg = cfg

    def detect(self, frame: np.ndarray) -> list[GreenRegion]:
        hsv  = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(
            hsv,
            np.array(self.cfg.green_hsv_lower, dtype=np.uint8),
            np.array(self.cfg.green_hsv_upper, dtype=np.uint8),
        )
        k    = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k, iterations=2)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN,  k, iterations=1)

        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        results = []
        for c in contours:
            area = cv2.contourArea(c)
            if area < self.cfg.green_min_area:
                continue
            M = cv2.moments(c)
            if M["m00"] == 0:
                continue
            results.append(GreenRegion(
                contour=c,
                area=area,
                centroid=(int(M["m10"]/M["m00"]), int(M["m01"]/M["m00"])),
                bounding_rect=cv2.boundingRect(c),
            ))
        return results

# ---------------------------------------------------------------------------
# Top-level detector
# ---------------------------------------------------------------------------

class Detector:
    def __init__(self, cfg: Config):
        self.cfg   = cfg
        self.lanes = UFLDLaneDetector(cfg)
        self.green = GreenPaintDetector(cfg)

    def detect(self, frame: np.ndarray) -> FrameResult:
        result = FrameResult(timestamp=time.time())
        result.green_regions = self.green.detect(frame)
        result.lanes         = self.lanes.detect(frame)
        result.bike_lane_confidence = self._confidence(result)
        return result

    def _confidence(self, r: FrameResult) -> float:
        score = 0.0
        if r.green_regions:
            score += 0.5
        # 3+ lanes detected suggests a multi-lane road with a bike lane
        if len(r.lanes) >= 3:
            score += 0.3
        if r.green_regions and r.lanes:
            score += 0.2
        return min(score, 1.0)

# ---------------------------------------------------------------------------
# Visualiser
# ---------------------------------------------------------------------------

# Colours per lane slot: leftmost, left, right, rightmost
LANE_COLOURS = [
    (255,  50,  50),   # blue-ish
    (50,  255,  50),   # green
    (50,  50,  255),   # red
    (255, 255,  50),   # cyan
]

def draw_result(frame: np.ndarray, result: FrameResult) -> np.ndarray:
    out = frame.copy()
    h, w = out.shape[:2]

    # Green regions
    for region in result.green_regions:
        cv2.drawContours(out, [region.contour], -1, (0, 255, 0), 2)
        x, y, rw, rh = region.bounding_rect
        cv2.putText(out, f"GREEN {region.area:.0f}px²",
                    (x, max(y-6, 12)), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1)

    # Lane points + polyline
    for lane in result.lanes:
        colour = LANE_COLOURS[lane.lane_idx % len(LANE_COLOURS)]
        valid  = [(x, y) for pt in lane.points if (pt is not None) for x, y in [pt]]

        # Draw individual keypoints
        for pt in valid:
            cv2.circle(out, pt, 4, colour, -1)

        # Connect with polyline
        if len(valid) >= 2:
            pts_arr = np.array(valid, dtype=np.int32).reshape(-1, 1, 2)
            cv2.polylines(out, [pts_arr], False, colour, 2)

        # Label at the bottom-most valid point
        if valid:
            label_pt = max(valid, key=lambda p: p[1])
            labels = ["L-OUTER", "L-INNER", "R-INNER", "R-OUTER"]
            cv2.putText(out, labels[lane.lane_idx],
                        (label_pt[0]+6, label_pt[1]),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.45, colour, 1)

    # Fill polygon between innermost lanes (idx 1 and 2)
    left  = next((l for l in result.lanes if l.lane_idx == 1), None)
    right = next((l for l in result.lanes if l.lane_idx == 2), None)
    if left and right:
        lpts = [p for p in left.points  if p is not None]
        rpts = [p for p in right.points if p is not None]
        if len(lpts) >= 2 and len(rpts) >= 2:
            poly  = np.array(lpts + rpts[::-1], dtype=np.int32)
            overlay = out.copy()
            cv2.fillPoly(overlay, [poly], (0, 80, 160))
            cv2.addWeighted(overlay, 0.2, out, 0.8, 0, out)

    # HUD
    conf = int(result.bike_lane_confidence * 100)
    n_lanes = len(result.lanes)
    conf_col = (0,255,100) if conf > 60 else (0,200,255) if conf > 30 else (150,150,150)
    cv2.putText(out, f"Lanes: {n_lanes}  Bike lane: {conf}%",
                (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.6, conf_col, 2)

    return out

# ---------------------------------------------------------------------------
# Args + main loop
# ---------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--source",   default="0")
    p.add_argument("--backend",  default="opencv", choices=["opencv", "picamera2"])
    p.add_argument("--width",    type=int, default=640)
    p.add_argument("--height",   type=int, default=480)
    p.add_argument("--model",    default="models/tusimple.onnx")
    p.add_argument("--dataset",  default="tusimple", choices=["tusimple", "culane"])
    p.add_argument("--conf",     type=float, default=0.6, help="Lane point confidence threshold")
    p.add_argument("--no-window",   action="store_true")
    p.add_argument("--save-frames", action="store_true")
    p.add_argument("--debug",       action="store_true")
    p.add_argument("--green-lower", nargs=3, type=int, default=[35,40,40],   metavar=("H","S","V"))
    p.add_argument("--green-upper", nargs=3, type=int, default=[90,255,255], metavar=("H","S","V"))
    return p.parse_args()


def main():
    args = parse_args()

    cfg = Config(
        camera_backend=args.backend,
        source=int(args.source) if args.source.isdigit() else args.source,
        frame_width=args.width,
        frame_height=args.height,
        model_path=args.model,
        dataset=Dataset(args.dataset),
        lane_conf_threshold=args.conf,
        show_window=not args.no_window,
        save_frames=args.save_frames,
        debug=args.debug,
        green_hsv_lower=tuple(args.green_lower),
        green_hsv_upper=tuple(args.green_upper),
    )

    if cfg.save_frames:
        Path(cfg.output_dir).mkdir(parents=True, exist_ok=True)

    try:
        camera = build_camera(cfg)
    except RuntimeError as e:
        print(f"[main] {e}", file=sys.stderr); sys.exit(1)

    detector = Detector(cfg)

    frame_count = 0
    fps_timer   = time.time()
    fps_display = 0.0
    saved_count = 0

    print("[main] Running — press Q to quit")

    try:
        while True:
            ok, frame = camera.read()
            if not ok or frame is None:
                print("[main] End of stream."); break

            result    = detector.detect(frame)
            annotated = draw_result(frame, result)

            frame_count += 1
            elapsed = time.time() - fps_timer
            if elapsed >= 1.0:
                fps_display = frame_count / elapsed
                frame_count = 0
                fps_timer   = time.time()

            cv2.putText(annotated, f"{fps_display:.1f} fps",
                        (cfg.frame_width - 90, 24),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (180,180,180), 1)

            if result.has_detections:
                parts = []
                if result.green_regions:
                    parts.append(f"{len(result.green_regions)} green")
                if result.lanes:
                    parts.append(f"{len(result.lanes)} lane(s)")
                print(f"[{time.strftime('%H:%M:%S')}] {' | '.join(parts)}  "
                      f"confidence={result.bike_lane_confidence:.0%}")

            if cfg.save_frames and result.has_detections:
                fname = Path(cfg.output_dir) / f"det_{int(time.time()*1000)}.jpg"
                cv2.imwrite(str(fname), annotated)
                saved_count += 1

            if cfg.show_window:
                cv2.imshow("Bike Marking Detector — Q to quit", annotated)
                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), 27):
                    break

    except KeyboardInterrupt:
        print("\n[main] Interrupted.")
    finally:
        camera.release()
        if cfg.show_window:
            cv2.destroyAllWindows()
        if cfg.save_frames:
            print(f"[main] Saved {saved_count} frame(s) to ./{cfg.output_dir}/")


if __name__ == "__main__":
    main()
