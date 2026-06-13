# Blind Spot

Hackathon prototype for bike-mounted hazard capture and crowd safety mapping.

This branch contains the algorithm/Raspberry Pi foundation:

- Raspberry Pi capture loop scaffold with mock mode for laptop development.
- Local SQLite buffering for rides, GPS points, events, and photos.
- IMU impact and crash detection logic.
- Sync client stub for uploading buffered events/photos to a backend.
- Batch image detection CLI for pothole/hazard labeling.

## Quick Start

Run the mock device loop locally:

```powershell
python -m device.scripts.run_device --mock --duration 8
```

Trigger one simulated manual flag:

```powershell
python -m device.scripts.simulate_event manual_flag
```

Run the button-to-photo loop in local mock mode:

```powershell
python -m device.scripts.photo_button --mock --once
```

Run tests:

```powershell
python -m unittest discover -s tests
```

Run image detection in deterministic mock mode:

```powershell
python -m ml.detect_hazards --model mock --images data/device/photos
```

## Raspberry Pi Notes

The code is designed to work without hardware while the rest of the product is still being built. On the Pi, install the optional hardware packages and swap mock readers for real camera/GPS/GPIO readers:

- `picamera2` for Pi Camera capture.
- `pyserial` for UART GPS.
- `gpiozero` for button, LED, and buzzer.
- `ultralytics` for YOLOv8 batch inference on a server or dev machine.

For v1, detection is intentionally batch-on-upload instead of always-on real-time inference on the Pi.

## Button + 8-LED Strip Wiring

Assumption: the 3-wire 8-LED strip is an addressable WS2812/SK6812-style strip with `5V`, `GND`, and `DIN`/`DATA` labels. Check the labels before powering it. If the wires are not labeled, do not guess.

### LED strip

| LED strip wire | Raspberry Pi pin |
|---|---|
| `5V` / `VCC` | physical pin 2 or 4 (`5V`) |
| `GND` | physical pin 6, 9, 14, 20, 25, 30, 34, or 39 (`GND`) |
| `DIN` / `DATA` | physical pin 12 (`GPIO18` / `BCM 18`) |

Recommended:

- Put a 330-470 ohm resistor in series between `GPIO18` and LED `DIN`.
- Put a 1000 uF capacitor across LED `5V` and `GND` if you have one.
- Keep brightness modest. Eight RGB LEDs can draw up to about 480 mA at full white.
- If you use an external 5V LED power supply, connect its ground to the Pi ground.

### Button

Use the Pi's internal pull-up resistor:

| Button terminal | Raspberry Pi pin |
|---|---|
| One side of button | physical pin 11 (`GPIO17` / `BCM 17`) |
| Other side of button | any `GND` pin |

Run on the Raspberry Pi:

```bash
python -m pip install ".[pi]"
python -m device.scripts.photo_button
```

Pressing the button captures a photo to `data/device/photos` and flashes the LED strip.

### LED status display

| LED display | Meaning |
|---|---|
| One dim yellow LED | Ready / idle |
| Solid amber | Capturing photo or toggling video |
| Green flash | Saved / action confirmed |
| Solid green | Ride is active |
| Solid red | Video is recording |
| Alternating red + green | Ride active and video recording |
| Red flash | Error |

### One-button gestures

| Gesture | Meaning | Photo prefix |
|---|---|---|
| Single click | Normal manual hazard flag | `manual_flag` |
| Double click | Start/stop video recording | `button_video` in `data/device/videos` |
| Press and hold | Start/stop ride | no photo |

Default timing:

- Double click window: `0.45s`
- Long press threshold: `1.1s`

You can tune those values:

```bash
python -m device.scripts.photo_button --double-window 0.55 --long-press 1.3
```
