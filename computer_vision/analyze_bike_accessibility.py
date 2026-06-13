"""
Bike accessibility analyzer for Blind Spot.

This is intentionally a post-ride/image-batch tool. It combines local computer
vision signals with the existing UFLD lane detector and can optionally ask a
Hack Club AI vision model for a higher-level bike-infrastructure judgment.

Usage:
    uv run analyze_bike_accessibility.py --images ../data/lane_tests
    uv run analyze_bike_accessibility.py --images image.jpg --provider hackclub
"""

# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "opencv-python>=4.9",
#   "numpy>=1.26",
#   "onnxruntime>=1.17",
#   "requests>=2.32",
# ]
# ///

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import cv2
import numpy as np
import requests

sys.path.insert(0, str(Path(__file__).parent))
from main import Config, Dataset, Lane, UFLDLaneDetector  # noqa: E402


if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
HACKCLUB_BASE_URL = "https://ai.hackclub.com/proxy/v1/chat/completions"
DEFAULT_HACKCLUB_MODEL = "qwen/qwen3.7-plus"


@dataclass
class Box:
    x1: float
    y1: float
    x2: float
    y2: float


@dataclass
class LocalEvidence:
    green_bike_paint: bool
    green_paint_score: float
    green_area_ratio: float
    green_regions: list[Box] = field(default_factory=list)
    bike_symbol_possible: bool = False
    bike_symbol_score: float = 0.0
    white_marking_regions: list[Box] = field(default_factory=list)
    lane_count: int = 0
    lane_point_count: int = 0
    surface_quality: str = "unknown"
    surface_score: float = 0.5
    notes: list[str] = field(default_factory=list)


@dataclass
class AccessibilityReport:
    image: str
    score: int
    rating: str
    confidence: float
    labels: list[str]
    description: str
    local_evidence: LocalEvidence
    ai_evidence: dict[str, Any] | None = None
    annotated_image: str | None = None
    elapsed_ms: int = 0


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def iter_images(paths: list[str]) -> list[Path]:
    images: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            for child in sorted(path.iterdir()):
                if child.suffix.lower() in IMAGE_EXTENSIONS and "_annotated" not in child.stem:
                    images.append(child)
        elif path.exists() and path.suffix.lower() in IMAGE_EXTENSIONS:
            images.append(path)
    return images


def road_roi_mask(frame: np.ndarray) -> np.ndarray:
    """Approximate the ride-forward road area and avoid sky/side greenery."""
    h, w = frame.shape[:2]
    polygon = np.array(
        [
            (int(w * 0.04), h - 1),
            (int(w * 0.96), h - 1),
            (int(w * 0.68), int(h * 0.43)),
            (int(w * 0.32), int(h * 0.43)),
        ],
        dtype=np.int32,
    )
    mask = np.zeros((h, w), dtype=np.uint8)
    cv2.fillPoly(mask, [polygon], 255)
    return mask


def normalized_box(x: int, y: int, w: int, h: int, image_w: int, image_h: int) -> Box:
    return Box(
        x1=round(x / image_w, 4),
        y1=round(y / image_h, 4),
        x2=round((x + w) / image_w, 4),
        y2=round((y + h) / image_h, 4),
    )


def detect_green_bike_paint(frame: np.ndarray, roi: np.ndarray) -> tuple[bool, float, float, list[Box], np.ndarray]:
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)

    # Broad enough for worn green bike paint, but constrained to the road ROI.
    green = cv2.inRange(hsv, np.array((35, 45, 45)), np.array((95, 255, 255)))
    green = cv2.bitwise_and(green, roi)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
    green = cv2.morphologyEx(green, cv2.MORPH_OPEN, kernel, iterations=1)
    green = cv2.morphologyEx(green, cv2.MORPH_CLOSE, kernel, iterations=2)

    h, w = frame.shape[:2]
    roi_area = max(1, int(np.count_nonzero(roi)))
    min_area = max(350, int(roi_area * 0.002))
    boxes: list[Box] = []
    kept_area = 0.0

    contours, _ = cv2.findContours(green, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for contour in contours:
        area = float(cv2.contourArea(contour))
        if area < min_area:
            continue
        x, y, bw, bh = cv2.boundingRect(contour)
        # Ignore tiny dots and very thin vertical objects that are usually poles/signs.
        if bw < 12 or bh < 12:
            continue
        if bh > bw * 4 and x > w * 0.75:
            continue
        kept_area += area
        boxes.append(normalized_box(x, y, bw, bh, w, h))

    area_ratio = kept_area / roi_area
    score = clamp(area_ratio / 0.08, 0.0, 1.0)
    return score >= 0.18, score, round(area_ratio, 5), boxes, green


def detect_bike_symbol_candidate(
    frame: np.ndarray, roi: np.ndarray
) -> tuple[bool, float, list[Box], np.ndarray]:
    """Find possible white bike pavement symbols without claiming certainty."""
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    white = cv2.inRange(hsv, np.array((0, 0, 145)), np.array((180, 95, 255)))
    white = cv2.bitwise_and(white, roi)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    white = cv2.morphologyEx(white, cv2.MORPH_OPEN, kernel, iterations=1)

    h, w = frame.shape[:2]
    roi_area = max(1, int(np.count_nonzero(roi)))
    min_area = max(80, int(roi_area * 0.00035))
    max_area = int(roi_area * 0.08)

    boxes: list[Box] = []
    accepted_centers: list[tuple[int, int]] = []
    accepted_area = 0.0

    contours, _ = cv2.findContours(white, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for contour in contours:
        area = float(cv2.contourArea(contour))
        if area < min_area or area > max_area:
            continue
        x, y, bw, bh = cv2.boundingRect(contour)
        if bw < 8 or bh < 8:
            continue
        aspect = min(bw, bh) / max(bw, bh)
        long_thin_lane_stripe = aspect < 0.12 and max(bw, bh) > max(w, h) * 0.10
        if long_thin_lane_stripe:
            continue
        if y < h * 0.38:
            continue

        accepted_area += area
        accepted_centers.append((x + bw // 2, y + bh // 2))
        boxes.append(normalized_box(x, y, bw, bh, w, h))

    if not boxes:
        return False, 0.0, [], white

    xs = [c[0] for c in accepted_centers]
    ys = [c[1] for c in accepted_centers]
    cluster_w = max(xs) - min(xs) + 1
    cluster_h = max(ys) - min(ys) + 1
    compact_cluster = cluster_w < w * 0.42 and cluster_h < h * 0.42
    component_score = clamp(len(boxes) / 5.0, 0.0, 1.0)
    area_score = clamp((accepted_area / roi_area) / 0.035, 0.0, 1.0)
    score = (component_score * 0.55 + area_score * 0.45) * (1.0 if compact_cluster else 0.65)

    return score >= 0.35, round(score, 3), boxes, white


def estimate_surface_quality(frame: np.ndarray, roi: np.ndarray, ignore_mask: np.ndarray) -> tuple[str, float]:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    analysis_mask = cv2.bitwise_and(roi, cv2.bitwise_not(ignore_mask))
    area = max(1, int(np.count_nonzero(analysis_mask)))

    edges = cv2.Canny(gray, 80, 160)
    edge_density = np.count_nonzero(cv2.bitwise_and(edges, analysis_mask)) / area
    dark = cv2.inRange(gray, 0, 55)
    dark_ratio = np.count_nonzero(cv2.bitwise_and(dark, analysis_mask)) / area

    roughness = edge_density * 1.8 + dark_ratio * 0.8
    if roughness > 0.42:
        return "rough", 0.2
    if roughness > 0.25:
        return "moderate", 0.55
    return "smooth", 0.9


def load_lane_detector(model_path: Path, conf: float) -> UFLDLaneDetector | None:
    if not model_path.exists():
        return None
    cfg = Config(
        model_path=str(model_path),
        dataset=Dataset.TUSIMPLE,
        lane_conf_threshold=conf,
        show_window=False,
        save_frames=False,
    )
    return UFLDLaneDetector(cfg)


def detect_lanes(detector: UFLDLaneDetector | None, frame: np.ndarray) -> list[Lane]:
    if detector is None:
        return []
    return detector.detect(frame)


def build_local_evidence(frame: np.ndarray, lanes: list[Lane]) -> tuple[LocalEvidence, dict[str, np.ndarray]]:
    roi = road_roi_mask(frame)
    green_present, green_score, green_ratio, green_boxes, green_mask = detect_green_bike_paint(frame, roi)
    symbol_present, symbol_score, white_boxes, white_mask = detect_bike_symbol_candidate(frame, roi)
    ignore = cv2.bitwise_or(green_mask, white_mask)
    surface_quality, surface_score = estimate_surface_quality(frame, roi, ignore)

    lane_point_count = sum(1 for lane in lanes for point in lane.points if point is not None)
    notes: list[str] = []
    if not green_present and symbol_present and symbol_score < 0.82:
        symbol_present = False
        symbol_score = 0.0
        notes.append("White pavement markings were not treated as bike symbols without green paint or AI confirmation.")
    if green_present and surface_quality == "rough" and green_ratio > 0.05:
        surface_quality = "moderate"
        surface_score = 0.55
    if lanes:
        notes.append("UFLD lane lines are generic road-lane evidence, not proof of a bike lane.")
    if not green_present and not symbol_present:
        notes.append("No bike-specific pavement marking was found by local CV.")

    evidence = LocalEvidence(
        green_bike_paint=green_present,
        green_paint_score=round(green_score, 3),
        green_area_ratio=green_ratio,
        green_regions=green_boxes[:8],
        bike_symbol_possible=symbol_present,
        bike_symbol_score=round(symbol_score, 3),
        white_marking_regions=white_boxes[:12],
        lane_count=len(lanes),
        lane_point_count=lane_point_count,
        surface_quality=surface_quality,
        surface_score=round(surface_score, 3),
        notes=notes,
    )
    return evidence, {"roi": roi, "green": green_mask, "white": white_mask}


def heuristic_score(evidence: LocalEvidence) -> tuple[int, str, float, list[str], str]:
    labels: list[str] = []
    score = 26.0

    if evidence.green_bike_paint:
        score += 45.0 * evidence.green_paint_score
        labels.append("green_bike_paint")
    if evidence.bike_symbol_possible:
        score += 24.0 * evidence.bike_symbol_score
        labels.append("possible_bike_pavement_symbol")
    if evidence.lane_count >= 2:
        score += 6.0
        labels.append("lane_markings_visible")

    if evidence.surface_quality == "smooth":
        score += 8.0
        labels.append("smooth_surface")
    elif evidence.surface_quality == "moderate":
        score += 2.0
        labels.append("moderate_surface")
    elif evidence.surface_quality == "rough":
        score -= 8.0
        labels.append("rough_surface")

    if "green_bike_paint" not in labels and "possible_bike_pavement_symbol" not in labels:
        labels.append("no_bike_specific_marking_seen")
        score = min(score, 42.0)

    score = int(round(clamp(score, 0, 100)))
    rating = rating_from_score(score)
    confidence = clamp(
        0.32
        + evidence.green_paint_score * 0.34
        + evidence.bike_symbol_score * 0.22
        + min(evidence.lane_count, 4) * 0.03,
        0.0,
        0.9,
    )

    description = describe_from_evidence(score, rating, evidence, ai_used=False)
    return score, rating, round(confidence, 3), labels, description


def rating_from_score(score: int) -> str:
    if score >= 70:
        return "good"
    if score >= 45:
        return "fair"
    return "poor"


def describe_from_evidence(
    score: int,
    rating: str,
    evidence: LocalEvidence,
    *,
    ai_used: bool,
) -> str:
    parts: list[str] = []
    if evidence.green_bike_paint:
        parts.append("green bike-lane/path paint is visible")
    if evidence.bike_symbol_possible:
        parts.append("a possible bike pavement symbol is visible")
    if evidence.lane_count:
        parts.append(f"{evidence.lane_count} generic lane line(s) were detected")
    parts.append(f"surface looks {evidence.surface_quality}")

    basis = "; ".join(parts)
    if rating == "good":
        prefix = "Good bike accessibility"
    elif rating == "fair":
        prefix = "Fair bike accessibility"
    else:
        prefix = "Poor or unconfirmed bike accessibility"

    suffix = "AI vision plus local CV" if ai_used else "local CV"
    return f"{prefix} ({score}/100): {basis}. Assessment source: {suffix}."


def encode_image_for_ai(frame: np.ndarray, max_side: int = 1280) -> str:
    h, w = frame.shape[:2]
    scale = min(1.0, max_side / max(h, w))
    if scale < 1.0:
        frame = cv2.resize(frame, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 82])
    if not ok:
        raise RuntimeError("Could not encode image for AI request")
    return base64.b64encode(encoded.tobytes()).decode("ascii")


def extract_json_object(text: str) -> dict[str, Any]:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if not match:
            raise
        return json.loads(match.group(0))


def call_hackclub_vision(
    frame: np.ndarray,
    *,
    api_key: str,
    model: str,
    timeout_s: float,
) -> dict[str, Any]:
    image_data = encode_image_for_ai(frame)
    prompt = (
        "You are analyzing one bike-mounted ride photo for Blind Spot. "
        "Focus only on cycling accessibility. Detect whether the photo shows: "
        "green bike-lane/path paint, a bicycle symbol or sharrow painted on the ground, "
        "protected/painted/no bike lane, a blocked bike lane, and surface quality. "
        "Return only valid JSON with keys: score integer 0-100, rating one of "
        "good/fair/poor, confidence 0-1, green_bike_paint boolean, "
        "bike_pavement_symbol boolean, lane_type string, blocked boolean, "
        "surface_quality one of smooth/moderate/rough/unknown, labels array of strings, "
        "description one short sentence, evidence array of short strings. "
        "If a bike-specific marking is not visible, do not infer one from normal car lane lines."
    )
    response = requests.post(
        HACKCLUB_BASE_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:image/jpeg;base64,{image_data}"},
                        },
                    ],
                }
            ],
            "temperature": 0,
        },
        timeout=timeout_s,
    )
    response.raise_for_status()
    payload = response.json()
    content = payload["choices"][0]["message"]["content"]
    parsed = extract_json_object(content)
    parsed["_model"] = model
    return parsed


def combine_with_ai(
    local: LocalEvidence,
    local_score: int,
    local_rating: str,
    local_confidence: float,
    local_labels: list[str],
    local_description: str,
    ai: dict[str, Any] | None,
) -> tuple[int, str, float, list[str], str, dict[str, Any] | None]:
    if not ai:
        return local_score, local_rating, local_confidence, local_labels, local_description, None

    ai_score = int(clamp(float(ai.get("score", local_score)), 0, 100))
    score = int(round(local_score * 0.35 + ai_score * 0.65))
    rating = str(ai.get("rating") or rating_from_score(score)).lower()
    if rating not in {"good", "fair", "poor"}:
        rating = rating_from_score(score)
    confidence = round(clamp(max(local_confidence, float(ai.get("confidence", 0.0))), 0.0, 1.0), 3)

    ai_labels = [str(label) for label in ai.get("labels", []) if str(label).strip()]
    labels = sorted(set(local_labels + ai_labels))
    description = str(ai.get("description") or describe_from_evidence(score, rating, local, ai_used=True))
    return score, rating, confidence, labels, description, ai


def draw_annotations(
    frame: np.ndarray,
    evidence: LocalEvidence,
    lanes: list[Lane],
    masks: dict[str, np.ndarray],
    score: int,
    rating: str,
    description: str,
) -> np.ndarray:
    out = frame.copy()
    overlay = out.copy()
    roi_contours, _ = cv2.findContours(masks["roi"], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(overlay, roi_contours, -1, (0, 200, 255), 2)
    cv2.addWeighted(overlay, 0.18, out, 0.82, 0, out)

    green_contours, _ = cv2.findContours(masks["green"], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(out, green_contours, -1, (0, 255, 0), 2)

    white_contours, _ = cv2.findContours(masks["white"], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(out, white_contours, -1, (255, 255, 255), 1)

    lane_colours = [(255, 60, 60), (60, 255, 60), (60, 60, 255), (255, 255, 60)]
    for lane in lanes:
        valid = [point for point in lane.points if point is not None]
        if len(valid) < 2:
            continue
        colour = lane_colours[lane.lane_idx % len(lane_colours)]
        pts = np.array(valid, dtype=np.int32).reshape(-1, 1, 2)
        cv2.polylines(out, [pts], False, colour, 2)
        for point in valid:
            cv2.circle(out, point, 3, colour, -1)

    h, w = out.shape[:2]
    panel_h = 92
    cv2.rectangle(out, (0, 0), (w, panel_h), (0, 0, 0), -1)
    colour = (0, 220, 0) if rating == "good" else (0, 210, 255) if rating == "fair" else (0, 80, 255)
    cv2.putText(
        out,
        f"Bike accessibility: {rating.upper()} {score}/100",
        (12, 28),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.78,
        colour,
        2,
    )
    cv2.putText(
        out,
        f"green={evidence.green_paint_score:.2f} symbol={evidence.bike_symbol_score:.2f} "
        f"surface={evidence.surface_quality} lanes={evidence.lane_count}",
        (12, 56),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.48,
        (230, 230, 230),
        1,
    )
    cv2.putText(
        out,
        description[:140],
        (12, 80),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.42,
        (220, 220, 220),
        1,
    )
    return out


def analyze_image(
    image: Path,
    *,
    lane_detector: UFLDLaneDetector | None,
    provider: str,
    hackclub_key: str | None,
    hackclub_model: str,
    hackclub_timeout: float,
    output_dir: Path | None,
) -> AccessibilityReport:
    t0 = time.perf_counter()
    frame = cv2.imread(str(image))
    if frame is None:
        raise RuntimeError(f"Cannot read image: {image}")

    lanes = detect_lanes(lane_detector, frame)
    local, masks = build_local_evidence(frame, lanes)
    display_lanes = lanes
    if local.green_area_ratio > 0.45:
        local.lane_count = 0
        local.lane_point_count = 0
        display_lanes = []
        local.notes.append("Ignored UFLD lane evidence because this looks like a close-up bike-lane marking.")
    local_score, local_rating, local_confidence, local_labels, local_description = heuristic_score(local)

    ai_evidence = None
    if provider in {"hackclub", "hybrid"} and hackclub_key:
        try:
            ai_evidence = call_hackclub_vision(
                frame,
                api_key=hackclub_key,
                model=hackclub_model,
                timeout_s=hackclub_timeout,
            )
        except Exception as exc:
            local.notes.append(f"Hack Club AI vision call failed: {exc}")
            if provider == "hackclub":
                raise

    score, rating, confidence, labels, description, merged_ai = combine_with_ai(
        local,
        local_score,
        local_rating,
        local_confidence,
        local_labels,
        local_description,
        ai_evidence,
    )

    annotated_path = None
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)
        annotated = draw_annotations(frame, local, display_lanes, masks, score, rating, description)
        annotated_path = output_dir / f"{image.stem}_bike_access_annotated.jpg"
        cv2.imwrite(str(annotated_path), annotated)

    return AccessibilityReport(
        image=str(image),
        score=score,
        rating=rating,
        confidence=confidence,
        labels=labels,
        description=description,
        local_evidence=local,
        ai_evidence=merged_ai,
        annotated_image=str(annotated_path) if annotated_path else None,
        elapsed_ms=int((time.perf_counter() - t0) * 1000),
    )


def report_to_json(report: AccessibilityReport) -> dict[str, Any]:
    data = asdict(report)
    data["local_evidence"]["green_regions"] = [asdict(box) for box in report.local_evidence.green_regions]
    data["local_evidence"]["white_marking_regions"] = [
        asdict(box) for box in report.local_evidence.white_marking_regions
    ]
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description="Rate bike accessibility from ride photos")
    parser.add_argument("--images", nargs="+", required=True, help="Image files or directories")
    parser.add_argument("--model", default="models/tusimple.onnx", help="Optional UFLD lane model path")
    parser.add_argument("--conf", type=float, default=0.5, help="Lane detector confidence")
    parser.add_argument(
        "--provider",
        choices=["heuristic", "hybrid", "hackclub"],
        default="hybrid",
        help="hybrid uses Hack Club AI if HACKCLUB_AI_API_KEY is set, otherwise local CV",
    )
    parser.add_argument("--hackclub-model", default=DEFAULT_HACKCLUB_MODEL)
    parser.add_argument("--hackclub-timeout", type=float, default=40.0)
    parser.add_argument(
        "--output-dir",
        default="../data/bike_accessibility/results",
        help="Directory for annotated images",
    )
    parser.add_argument("--jsonl", action="store_true", help="Print one JSON object per image")
    args = parser.parse_args()

    images = iter_images(args.images)
    if not images:
        raise SystemExit("No images found")

    model_path = Path(args.model)
    if not model_path.exists():
        alt = Path(__file__).parent / args.model
        model_path = alt if alt.exists() else model_path

    lane_detector = load_lane_detector(model_path, args.conf)
    if lane_detector is None:
        print(f"[warn] Lane model not found at {model_path}; continuing without UFLD lane evidence", file=sys.stderr)

    hackclub_key = os.getenv("HACKCLUB_AI_API_KEY") or os.getenv("HACK_CLUB_AI_API_KEY")
    if args.provider == "hackclub" and not hackclub_key:
        raise SystemExit("Set HACKCLUB_AI_API_KEY to use --provider hackclub")
    if args.provider == "hybrid" and not hackclub_key:
        print("[info] HACKCLUB_AI_API_KEY not set; using local CV heuristics only", file=sys.stderr)

    output_dir = Path(args.output_dir) if args.output_dir else None
    reports = [
        analyze_image(
            image,
            lane_detector=lane_detector,
            provider=args.provider,
            hackclub_key=hackclub_key,
            hackclub_model=args.hackclub_model,
            hackclub_timeout=args.hackclub_timeout,
            output_dir=output_dir,
        )
        for image in images
    ]

    if args.jsonl:
        for report in reports:
            print(json.dumps(report_to_json(report), separators=(",", ":")))
        return

    print(json.dumps([report_to_json(report) for report in reports], indent=2))


if __name__ == "__main__":
    main()
