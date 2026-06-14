# Blind Spot

Hackathon prototype for bike-mounted hazard capture, ride safety, and cycling
accessibility mapping.

This repository now combines the main web/dashboard work, the native iOS app,
the computer-vision experiments, the device capture stack, and the Supabase
schema used by the demo.

## Repository layout

```text
app/                 Next.js dashboard and web UI
BlindSpot/           Native SwiftUI iOS app
computer_vision/     Bike-lane, lane-line, and bike-accessibility CV tools
device/              Device capture, button, BLE, serial, and sync code
ml/                  Hazard-detection command-line helpers
supabase/            SQL schema for rides, photos, automated photos, and summaries
tests/               Python unit tests for device/service logic
```

## Quick starts

### iOS app

Generate the Xcode project from `project.yml`:

```bash
./bootstrap.sh
```

Then select a simulator or device in Xcode and run the `BlindSpot` target.
`BlindSpot.xcodeproj` and `Info.plist` are generated artifacts and are ignored
by Git; re-run `xcodegen generate` or `./bootstrap.sh` after adding Swift files.

### Web dashboard

```bash
cd app
pnpm install
pnpm dev
```

### Device mock loop

```powershell
python -m device.scripts.run_device --mock --duration 8
python -m device.scripts.simulate_event manual_flag
python -m device.scripts.photo_button --mock --once
python -m unittest discover -s tests
```

### Computer vision

```powershell
cd computer_vision
uv run main.py --model models/tusimple.onnx
uv run analyze_bike_accessibility.py --images ../data/lane_tests
```

The TuSimple Ultra Fast Lane Detection model should be placed at
`computer_vision/models/tusimple.onnx`. `computer_vision/download_model.py` can
fetch the expected public ONNX file.

## iOS app

The native app is SwiftUI-first and uses:

- iOS 17.0+
- MapKit
- Swift Observation
- Firebase auth and Supabase-backed repositories
- XcodeGen for project generation

Core screens include onboarding, map, record, ride recap, profile, pairing, and
settings surfaces. The app includes live location/motion service abstractions,
fall-detection SOS UI, tap-to-add/report/delete hazard flows, and contact-picker
utilities.

`BlindSpot/Config/Secrets.example.swift` is the template for local app secrets.
Do not commit `BlindSpot/Config/Secrets.swift`,
`GoogleService-Info.plist`, `.env`, or API keys.

## Device capture

The Python device stack supports mock development and Raspberry Pi deployment.
It includes:

- photo capture and local buffering
- GPIO button gesture handling
- LED/buzzer status feedback
- BLE ride-control messaging
- USB serial JSON-lines demo commands
- Supabase photo and metadata uploads
- optional ride summary service integration

Button gesture defaults:

| Gesture | Meaning |
|---|---|
| Single click | Capture a manual hazard photo |
| Double click | Start or stop local video recording |
| Press and hold | Start or stop a ride |

Default GPIO assumptions:

| Hardware | Raspberry Pi pin |
|---|---|
| Button | BCM GPIO17 / physical pin 11 to GND |
| Addressable LED strip data | BCM GPIO18 / physical pin 12 |

The BLE peripheral name defaults to `BlindSpot-Pi`. The iOS app connects as a
central and exchanges ride start/stop JSON over the configured GATT service and
characteristics.

## Supabase data contract

Run `supabase/blindspot_device_schema.sql` in the Supabase SQL editor before
testing uploads.

Manual/user photos are inserted into `public.photos`. Machine-triggered captures
such as impact, hard-brake, swerve, crash, and interval frames are inserted into
`public.automated_photos`. Both paths require a real `ride_id` tied to
`public.rides`, so uploads do not create orphan photo rows.

Expected local environment variables include:

```bash
BLINDSPOT_SUPABASE_URL="https://PROJECT_REF.supabase.co"
BLINDSPOT_SUPABASE_KEY="..."
BLINDSPOT_SUPABASE_BUCKET="photos"
BLINDSPOT_SUPABASE_AUTOMATED_PHOTOS_TABLE="automated_photos"
BLINDSPOT_USER_ID="..."
BLINDSPOT_BLE_ENABLED="1"
BLINDSPOT_BLE_NAME="BlindSpot-Pi"
BLINDSPOT_SUMMARY_SERVICE_URL="http://<summary-service-host>:8765"
```

Store those values only in local environment files or device-local config. The
repo ignores `.env` files and app/device secret files.

## Ride summary service

Start the optional summary service when structured ride summaries are needed:

```bash
set HACKCLUB_AI_API_KEY=...
python -m device.scripts.ride_summary_service --host 0.0.0.0 --port 8765
```

The service accepts ride metrics and temporary JPEG payloads, then returns a
structured summary. The prompt focuses on bike-specific accessibility and road
condition signals: green bike lanes or paths, bicycle pavement symbols,
protected or painted lanes, missing/blocked lanes, potholes, cracks, debris,
dangerous shoulders, drain grates, and rough pavement.

## Tests

Run the Python checks from the repository root:

```powershell
python -m unittest discover -s tests
```

Run the web and iOS checks from their respective toolchains when changing those
areas.
