# Blind Spot

Hackathon prototype for bike-mounted hazard capture and crowd safety mapping.

This branch contains the algorithm/Raspberry Pi foundation:

- Raspberry Pi capture loop scaffold with mock mode for development.
- Local SQLite buffering for rides, GPS points, events, and photos.
- IMU impact and crash detection logic.
- Sync client stub for uploading buffered events/photos to a backend.
- Raspberry Pi ride AI processing for bike accessibility, potholes, and surface hazards.

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
- `supabase` for uploading captured photos to Supabase Storage + the `photos` and `automated_photos` tables.
- `requests` for the Pi-side Hack Club AI call after a ride.

For v1, AI processing is intentionally post-ride instead of always-on real-time inference. The Pi remains the capture/controller and owns button handling, camera capture, BLE ride control, local buffering, and Supabase writes. Supabase is only storage for manual photos, automated photo metadata, ride rows, and `ai_summary`; it should not run the image-processing workflow.

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

### Supabase photo upload

Run `supabase/blindspot_device_schema.sql` in the Supabase SQL editor first. Then set secrets only on the Pi, not in Git:

```bash
export BLINDSPOT_SUPABASE_URL="https://PROJECT_REF.supabase.co"
export BLINDSPOT_SUPABASE_KEY="..."
export BLINDSPOT_SUPABASE_BUCKET="photos"
export BLINDSPOT_SUPABASE_AUTOMATED_PHOTOS_TABLE="automated_photos"
export BLINDSPOT_USER_ID="..."
export BLINDSPOT_BLE_ENABLED="1"
export BLINDSPOT_BLE_NAME="BlindSpot-Pi"
export BLINDSPOT_SUMMARY_SERVICE_URL="http://<summary-service-host>:8765"
```

You can also put those values in `/home/pranav/blindspot/.env`; `.env` is ignored by Git.

Hold the button to start a ride. If BLE is enabled, the Pi advertises a Blind Spot BLE service and the iPhone app connects to the Pi to receive ride start/stop commands. The iPhone app should create/close the Supabase ride and return the `ride_id`; the Pi uses that id only to attach captured photos. The Pi can stay connected to `MUSDChrome` Wi-Fi for internet/Supabase while Bluetooth is connected to the iPhone.

Single-click captures a user/manual photo, uploads it to Storage, and inserts a row into `photos` with `ride_id` pointing at the active row in `rides`. The Pi refuses to upload a photo unless it has a real `ride_id`; no orphan `photos` rows should be created.

Only user/manual photos go into the `photos` table. Machine-triggered captures such as `impact`, `hard_brake`, `swerve`, `crash`, or Qwen interval frames upload under the same Storage bucket but insert rows into `automated_photos` instead. Automated rows also require a real `ride_id`, so every uploaded image remains tied to the active ride.

When a ride stops, the Pi computes ride distance/duration/photo count from its local SQLite `ride_points` and `events`. If `BLINDSPOT_SUMMARY_SERVICE_URL` is set, the Pi requests a Qwen ride summary from that service, then writes the result back to Supabase. If the service URL is not set, the Pi runs Qwen directly when `HACKCLUB_AI_API_KEY` is present. The summary is saved both on the separate `rides` table row for that ride and as a history row in `ai_summary`. The Qwen prompt specifically checks for green bike lanes/paths, bicycle pavement symbols, protected/painted/missing bike lanes, blocked lanes, potholes, cracks, debris, dangerous shoulders, and rough surface conditions. Set `BLINDSPOT_HACKCLUB_AI_MAX_IMAGES` to control how many ride images are attached; the default is `24`.

If the ride id comes from the iPhone or an already-open Supabase ride, the Pi mirrors that ride id into local SQLite so it can still do the photo summarization itself when the ride stops.

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

### Ride summary service

Start the optional ride summary service when you want the Pi to request structured Qwen ride summaries over the local network:

```bash
set HACKCLUB_AI_API_KEY=...
python -m device.scripts.ride_summary_service --host 0.0.0.0 --port 8765
```

On the Pi, set:

```bash
export BLINDSPOT_SUMMARY_SERVICE_URL="http://<summary-service-host>:8765"
```

The Pi still captures photos, owns ride/photo bookkeeping, and uploads Supabase rows. The summary service receives ride metrics plus temporary base64 JPEGs and returns summary JSON to the Pi.

### Bluetooth ride-control

For Bluetooth mode, first prep the Pi adapter:

```bash
python -m device.scripts.bluetooth_ready --name BlindSpot-Pi --discoverable
```

Then start the button runner with BLE enabled:

```bash
python -m device.scripts.photo_button --ble
```

The Pi acts as the BLE peripheral / GATT server. The iPhone app acts as the BLE central and connects from inside the app. iOS Bluetooth Settings may show or pair the Pi for debugging, but the actual JSON ride commands are app-level BLE characteristic traffic.

BLE UUIDs:

| Purpose | UUID |
|---|---|
| Service | `9b7d0001-6c9e-4f2a-9f1a-4b5f0b5d0001` |
| Pi command characteristic (`read` + `notify`) | `9b7d0002-6c9e-4f2a-9f1a-4b5f0b5d0002` |
| iPhone response characteristic (`read` + `write`) | `9b7d0003-6c9e-4f2a-9f1a-4b5f0b5d0003` |

On long press, the Pi notifies the command characteristic with:

```json
{
  "type": "ride_start",
  "request_id": "...",
  "device_id": "pranav-pi-001",
  "source": "raspberry_pi",
  "occurred_at": "..."
}
```

The iPhone writes this response JSON to the response characteristic:

```json
{
  "ok": true,
  "type": "ride_start_response",
  "request_id": "...",
  "ride_id": "...",
  "status": "recording"
}
```

On the next long press, the Pi sends `ride_stop` with the same shape plus `ride_id`, and expects `ride_stop_response`. Do not send GPS data over BLE; the Pi only needs the ride id and status.

### Hotspot HTTP ride-control fallback

If BLE is disabled and `BLINDSPOT_PHONE_BASE_URL` is set, the Pi can still use the older hotspot-LAN HTTP fallback. The iPhone app should listen on the hotspot LAN, for example `http://172.20.10.1:8787`, and implement:

- `POST /blindspot/ride/start` with JSON `{ "type": "ride_start", "device_id": "...", "source": "raspberry_pi", "occurred_at": "..." }`
- Response: `{ "ok": true, "ride_id": "...", "status": "recording" }`
- `POST /blindspot/ride/stop` with JSON `{ "type": "ride_stop", "device_id": "...", "source": "raspberry_pi", "ride_id": "...", "occurred_at": "..." }`
- Response: `{ "ok": true, "ride_id": "...", "status": "stopped" }`

If `BLINDSPOT_PHONE_TOKEN` is set on the Pi, requests include `Authorization: Bearer <token>`.
