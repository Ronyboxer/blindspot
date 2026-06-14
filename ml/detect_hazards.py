from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable


HAZARD_LABELS = {"pothole", "debris", "glass", "water", "blocked_lane", "construction"}


def detect_with_mock(image: Path) -> list[dict]:
    name = image.name.lower()
    label = "pothole" if "pothole" in name or "impact" in name else "road_hazard"
    return [
        {
            "label": label,
            "confidence": 0.76,
            "bbox": {"x1": 0.35, "y1": 0.42, "x2": 0.62, "y2": 0.68},
        }
    ]


def detect_with_yolo(model_path: str, images: Iterable[Path], confidence: float) -> list[dict]:
    try:
        from ultralytics import YOLO
    except ImportError as exc:
        raise RuntimeError("Install ultralytics or use --model mock") from exc

    model = YOLO(model_path)
    output: list[dict] = []
    for result in model([str(image) for image in images], conf=confidence):
        image_path = Path(result.path)
        detections = []
        for box in result.boxes:
            cls_id = int(box.cls[0])
            label = result.names[cls_id]
            xyxy = [float(v) for v in box.xyxy[0].tolist()]
            detections.append(
                {
                    "label": label,
                    "confidence": float(box.conf[0]),
                    "bbox": {"x1": xyxy[0], "y1": xyxy[1], "x2": xyxy[2], "y2": xyxy[3]},
                }
            )
        output.append({"image": str(image_path), "detections": detections})
    return output


def iter_images(paths: list[str]) -> list[Path]:
    images: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            images.extend(sorted(path.glob("*.jpg")))
            images.extend(sorted(path.glob("*.jpeg")))
            images.extend(sorted(path.glob("*.png")))
        elif path.exists():
            images.append(path)
    return images


def main() -> None:
    parser = argparse.ArgumentParser(description="Batch-detect Blind Spot road hazards")
    parser.add_argument("--model", required=True, help="'mock' or a YOLO model path/name")
    parser.add_argument("--images", nargs="+", required=True, help="Image files or directories")
    parser.add_argument("--confidence", type=float, default=0.35)
    parser.add_argument("--jsonl", action="store_true", help="Print one JSON object per image")
    args = parser.parse_args()

    images = iter_images(args.images)
    if not images:
        raise SystemExit("No images found")

    if args.model == "mock":
        results = [{"image": str(image), "detections": detect_with_mock(image)} for image in images]
    else:
        results = detect_with_yolo(args.model, images, args.confidence)

    if args.jsonl:
        for item in results:
            print(json.dumps(item))
    else:
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
