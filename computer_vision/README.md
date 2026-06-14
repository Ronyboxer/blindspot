# Bike Road Marking Detector

Detects **green bike lane paint** and **sharrow icons** from a camera feed.
Runs on desktop (webcam/video) for development; deploy to Raspberry Pi by
switching the `--backend` flag.

---

## Requirements

- [uv](https://docs.astral.sh/uv/) — that's it. Dependencies are declared inline.

---

## Run (desktop)

```bash
# Webcam (index 0)
uv run main.py

# Specific webcam
uv run main.py --source 1

# Video file
uv run main.py --source footage.mp4

# Headless (no window, e.g. SSH session)
uv run main.py --no-window --save-frames
```

Dependencies (`opencv-python`, `numpy`) are installed automatically by uv on
first run via the inline `# /// script` block — no `pyproject.toml` needed.

---

## Sharrow detection

Template matching is used. You need a clean grayscale crop of a sharrow icon:

```bash
# Default path the script looks for:
sharrow_template.png
```

Grab a top-down screenshot of a sharrow from Google Maps satellite view,
crop it to just the icon, convert to grayscale, and save as PNG. The script
will print a warning and skip sharrow detection if the file is missing —
green paint detection still works.

Tune `--match-threshold` (default 0.65) up if you get false positives,
down if you're missing real hits.

---

## Tuning green paint detection

Green bike lane paint varies enormously by age, municipality, and lighting.
Use `--green-lower` and `--green-upper` to adjust HSV ranges:

```bash
# Brighter/newer paint
uv run main.py --green-lower 40 60 80 --green-upper 85 255 255

# Faded/worn paint — widen the range
uv run main.py --green-lower 30 30 30 --green-upper 95 255 255
```

A useful calibration workflow: record a short video clip of the target surface,
run it through the script with `--save-frames`, and inspect the annotated frames.

---

## Deploy to Raspberry Pi

1. Copy the project folder to the Pi (scp, rsync, git clone — whatever you prefer)
2. Install uv on the Pi:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
3. Install picamera2 (system package, not pip):
   ```bash
   sudo apt install -y python3-picamera2
   ```
4. Run:
   ```bash
   uv run main.py --backend picamera2 --no-window --save-frames
   ```

The `picamera2` backend is imported lazily, so the script runs fine on desktop
without it installed.

**Pi camera mount:** aim ~45° downward and forward — you want to see markings
1–2 metres ahead of the wheel, not directly beneath it.

---

## Saving detections

```bash
uv run main.py --save-frames
# Annotated JPEGs written to ./detections/
```

---

## Key files

```
main.py                  # everything
sharrow_template.png     # (you provide this)
detections/              # auto-created when --save-frames
```

---

## Next steps

- **YOLOv8-nano fine-tuned model** — swap in via `ultralytics` for better
  generalisation across lighting/surface conditions. Label ~300 frames with
  Roboflow, fine-tune, export to NCNN format for Pi speed.
- **GPIO output** — trigger an LED or buzzer on detection; easy to add in
  `main()` after the `result.has_detections` check.
- **MQTT logging** — pipe detections to a broker for GPS-tagged mapping.


NOTE:
You will need the model in the `models/` folder, follow the specifications in main.py for how to obtain it. The model is PINTO Model Zoo Ultra Fast Lane Detection (TuSimple). Run with:

```bash
uv run main.py --model models/tusimple.onnx
```

---

## Bike accessibility scoring

For Blind Spot's bike-specific map layer, use the post-ride image analyzer:

```bash
uv run analyze_bike_accessibility.py --images ../data/lane_tests
```

It rates each photo for cycling accessibility and writes annotated outputs to
`../data/bike_accessibility/results/`. The local pass looks for:

- green bike-lane/path paint in the road area
- possible bicycle/sharrow pavement symbols
- generic lane-line support from the UFLD lane model
- rough / moderate / smooth surface quality

For a Hack Club AI vision pass, set an API key and use hybrid or explicit
Hack Club mode:

```bash
set HACKCLUB_AI_API_KEY=...
uv run analyze_bike_accessibility.py --provider hackclub --images ../data/lane_tests
```

`hybrid` is the default: it uses Hack Club AI when the key is present and falls
back to local CV when it is not. The output includes a 0-100 score, `good` /
`fair` / `poor` rating, labels, and a short human-readable description.
The default Hack Club vision model is `qwen/qwen3.7-plus`; override it with
`--hackclub-model` if needed.
