# Blind Spot Build Timeline

Generated: 2026-06-14 11:26:23 -0700

This timeline is written in the same style as the Lumiai/PranavWeb timeline:
each event is a compact card with `date`, `title`, `organization`, and `notes`.
I kept the section/event markers so every item is easy to reference.

Secrets, credentials, private keys, and local-only deployment details are omitted.

## Timestamp Rules

- `git-second`: exact timestamp from `git log --all --date=iso-local`.
- `chat-minute`: exact minute visible in the pasted chat transcript. The transcript does not include seconds.
- `session-checkpoint`: exact verified command/log/checkpoint timestamp, or a bounded window anchored by exact events.

## Section S1: Product Scope And Initial Direction

### S1-E01
- date: `2026-06-13 11:05:53 -0700`
- title: Repository created
- organization: Git / shared base / `4adae94`
- notes: Public repo started with `README.md`.

### S1-E02
- date: `2026-06-13 11:07 -0700`
- title: Algorithm and Raspberry Pi ownership set
- organization: Chat transcript
- notes: User linked `pranav-algorithm-camera` and defined their role as algorithm work, image detection, and Raspberry Pi-related device work.

### S1-E03
- date: `2026-06-13 11:07 -0700`
- title: Product requirements established
- organization: PRD / chat transcript
- notes: Blind Spot was framed as a handlebar camera/sensor capture layer feeding a crowd-sourced road hazard and accessibility map.

### S1-E04
- date: `2026-06-13 11:12 -0700`
- title: First Pi and algorithm scaffold completed
- organization: Chat transcript result
- notes: Added Pi/mock capture loop, local SQLite ride/event/photo buffering, IMU impact/crash logic, GPS/camera mocks, Pi-ready adapters, and batch hazard detector CLI. Verified a mock ride, GPS points, impact event, generated photo, and mock pothole label.

## Section S2: Phone GPS Pivot And Protocol Decisions

### S2-E01
- date: `2026-06-13 11:12 -0700`
- title: GPS scope corrected
- organization: Chat transcript
- notes: User clarified that GPS should come from the iPhone while the Pi connects through the iPhone hotspot.

### S2-E02
- date: `2026-06-13 11:43 -0700`
- title: First iPhone GPS prompt produced
- organization: Chat transcript result
- notes: Prompt asked the iPhone developer to use CoreLocation and send 1 Hz GPS JSON to the Pi over the hotspot LAN.

### S2-E03
- date: `2026-06-13 11:44 -0700`
- title: Protocol options compared
- organization: Chat transcript
- notes: User supplied MQTT, UDP/TCP socket, and NTRIP options for iPhone-to-Pi GPS transfer.

### S2-E04
- date: `2026-06-13 11:45 -0700`
- title: MQTT chosen as best GPS default
- organization: Chat transcript result
- notes: MQTT over hotspot was recommended as the robust default; HTTP POST stayed as the hackathon fallback; UDP and NTRIP were deprioritized.

## Section S3: Secret Safety And PRD Button/Photo Contract

### S3-E01
- date: `2026-06-13 11:45 -0700`
- title: Secret safety requirement added
- organization: Chat transcript
- notes: User explicitly warned not to publish secrets to GitHub.

### S3-E02
- date: `2026-06-13 11:45 -0700`
- title: Repo checked for publishable secrets
- organization: Chat transcript result
- notes: Repo was scanned for common secret patterns, and `.gitignore` was hardened for `.env`, local data, keys, credentials, mobile profiles, SQLite databases, and Python cache output.

### S3-E03
- date: `2026-06-13 11:46 -0700`
- title: PRD button/photo behavior requested
- organization: Chat transcript
- notes: User asked what the PRD says about photos and buttons.

### S3-E04
- date: `2026-06-13 12:02 -0700`
- title: Photo and button contract clarified
- organization: Chat transcript result
- notes: One button captures a frame and geo-tagged event within 1 second. Photos attach to ride, event, location, and timestamp, then feed local buffering, sync, privacy blurring, detection, map pins, and recap.

## Section S4: App, Computer Vision, And Pi Foundation Commits

### S4-E01
- date: `2026-06-13 11:24:33 -0700`
- title: App history started
- organization: Git / app history / `15f11d5`
- notes: Initial app commit landed.

### S4-E02
- date: `2026-06-13 12:14:06 -0700`
- title: Pi capture controls landed
- organization: Git / `pranav-algorithm-camera` / `3d4a6e9`
- notes: First tracked device-side capture control foundation was committed.

### S4-E03
- date: `2026-06-13 12:22:18 -0700`
- title: App shell and onboarding added
- organization: Git / `ronak-app` / `514f055`
- notes: App branch added shell, mock data, and onboarding.

### S4-E04
- date: `2026-06-13 12:23:35 -0700`
- title: App remote work merged
- organization: Git / `ronak-app` / `cc2a01f`
- notes: `origin/ronak-app` was merged into the app branch.

### S4-E05
- date: `2026-06-13 12:23:36 -0700`
- title: Computer vision module added
- organization: Git / computer vision / `ee81c9d`
- notes: Early lane-detection structure landed.

### S4-E06
- date: `2026-06-13 12:26:38 -0700`
- title: Local notes removed from tracking
- organization: Git / `pranav-algorithm-camera` / `aac3735`
- notes: Codex notes were removed from Git tracking so project context stayed local.

### S4-E07
- date: `2026-06-13 12:57:58 -0700`
- title: Lane model guide added
- organization: Git / computer vision / `cba2344`
- notes: Added guide for obtaining the Ultra Fast Lane Detection model.

### S4-E08
- date: `2026-06-13 13:18:15 -0700`
- title: LED status and lane detector committed
- organization: Git / `pranav-algorithm-camera` / `35fd998`
- notes: LED status display and lane detector work landed.

## Section S5: Hardware Bring-Up And Lane Model Testing

### S5-E01
- date: `2026-06-13 13:18:15 -0700 to 2026-06-13 15:45:33 -0700`
- title: Raspberry Pi hardware bring-up
- organization: Session notes
- notes: Hardware work focused on Raspberry Pi 4B GPIO17 button wiring, GPIO18 LED data, and the 8-pixel addressable LED strip.

### S5-E02
- date: `2026-06-13 13:18:15 -0700 to 2026-06-13 15:45:33 -0700`
- title: LED strip issue isolated
- organization: Session notes
- notes: Direct GPIO and NeoPixel software tests ran, but the physical strip did not visibly light. Likely causes were wiring, power, data direction, voltage level, or LED type.

### S5-E03
- date: `2026-06-13 13:18:15 -0700 to 2026-06-13 15:45:33 -0700`
- title: Button wiring issue found
- organization: Session notes
- notes: GPIO17 initially behaved as permanently pressed, pointing to wrong terminal pair, physical-pin confusion, or a short.

### S5-E04
- date: `2026-06-13 13:18:15 -0700 to 2026-06-13 15:45:33 -0700`
- title: One-button gesture map finalized
- organization: Session notes
- notes: Single press became manual photo, double press became video start/stop, and long press became ride start/stop.

### S5-E05
- date: `2026-06-13 13:18:15 -0700 to 2026-06-13 15:45:33 -0700`
- title: Lane neural network preserved and tested
- organization: Session notes
- notes: Existing lane neural network was preserved. TuSimple ONNX path was corrected, metadata was verified, and image outputs were tested.

### S5-E06
- date: `2026-06-13 15:45:33 -0700`
- title: App data and GPS/IMU layer added
- organization: Git / `ronak-app` / `259a396`
- notes: App branch added Firebase auth, Supabase data layer, live GPS/IMU flow, and ride favorites.

## Section S6: Bike Accessibility, Supabase, And Ride/Photo Data Model

### S6-E01
- date: `2026-06-13 16:11:57 -0700`
- title: Bike accessibility analysis added
- organization: Git / `pranav-algorithm-camera` / `efe1a82`
- notes: Pi branch added ride uploads and bike accessibility analysis focused on green bike paint, bike symbols, protected/painted/missing bike lanes, blocked lanes, and surface quality.

### S6-E02
- date: `2026-06-13 16:12:39 -0700`
- title: Automated photo table configured
- organization: Git / `pranav-algorithm-camera` / `b16b8af`
- notes: Added config for a separate automated photo table.

### S6-E03
- date: `2026-06-13 16:21:05 -0700`
- title: Manual and automated photos separated
- organization: Git / `pranav-algorithm-camera` / `20f65a5`
- notes: Automated photos route to `automated_photos`; manual rider photos stay in `photos`; uploads require a real ride ID.

### S6-E04
- date: `2026-06-13 16:37:40 -0700`
- title: First Pi BLE ride control added
- organization: Git / `pranav-algorithm-camera` / `e43f09f`
- notes: Initial BLE design made the Pi advertise as a peripheral and expected the iPhone app to connect as central.

### S6-E05
- date: `2026-06-13 16:44:17 -0700`
- title: Pi editable install fixed
- organization: Git / `pranav-algorithm-camera` / `1ee73d2`
- notes: Fixed setuptools package discovery errors for editable Pi install.

### S6-E06
- date: `2026-06-13 16:54:48 -0700`
- title: Ride summary service added
- organization: Git / `pranav-algorithm-camera` / `9fa3cb2`
- notes: Added public-safe ride summary service path for post-ride AI summaries and recap data.

### S6-E07
- date: `2026-06-13 16:54:48 -0700 to 2026-06-13 18:17:35 -0700`
- title: Supabase device loop connected
- organization: Session notes
- notes: Supabase work connected rides, manual photos, automated photos, AI summaries, storage uploads, and ride/photo ID linkage.

### S6-E08
- date: `2026-06-13 18:17:35 -0700`
- title: App recap and Pi data merge added
- organization: Git / `ronak-app` / `48602eb`
- notes: App branch added BLE Pi control, AI summary/photos in recap, Pi data merge, pothole email, and a location fix.

## Section S7: Demo Integration, Main Merges, And Pi Service Fixes

### S7-E01
- date: `2026-06-13 18:17:35 -0700 to 2026-06-13 19:10:14 -0700`
- title: Pi networking stabilized around IPv6 SSH
- organization: Session notes
- notes: Pi networking was unstable over IPv4/hostname routes, so IPv6 link-local SSH became the reliable control path.

### S7-E02
- date: `2026-06-13 19:10:14 -0700`
- title: USB serial demo bridge added
- organization: Git / `pranav-algorithm-camera` / `eb11101`
- notes: Added JSON-lines cable bridge for status/events and optional gesture triggering.

### S7-E03
- date: `2026-06-13 19:10:54 -0700`
- title: App hazard UI and SOS added
- organization: Git / `ronak-app` / `0a1c069`
- notes: App branch added hazard colors, tap-to-add/report/delete, fall detection SOS, and contact picker work.

### S7-E04
- date: `2026-06-13 19:12:52 -0700`
- title: Pi branch merged to main
- organization: Git / `main` / `24a1b72`
- notes: `pranav-algorithm-camera` was merged into `main`.

### S7-E05
- date: `2026-06-13 19:13:55 -0700`
- title: App branch merged to main
- organization: Git / `main` / `4832a54`
- notes: `ronak-app` was merged into `main`.

### S7-E06
- date: `2026-06-13 19:17:03 -0700`
- title: Dashboard tooltip fix landed
- organization: Git / `origin/main` / `236ae32`
- notes: Fixed dashboard tooltip provider prop issue.

### S7-E07
- date: `2026-06-13 19:22:50 -0700`
- title: LED made optional
- organization: Git / `pranav-algorithm-camera` / `c911f71`
- notes: LED strip output was made optional for the final demo path.

### S7-E08
- date: `2026-06-13 19:24:53 -0700`
- title: Serial photo event fields fixed
- organization: Git / `pranav-algorithm-camera` / `368139a`
- notes: Serial status/photo messages now carry the correct capture metadata.

### S7-E09
- date: `2026-06-13 19:29:37 -0700`
- title: Pi camera startup made resilient
- organization: Git / `pranav-algorithm-camera` / `2e4d691`
- notes: Added Pi camera retry/lazy behavior so the service stays alive if the camera is not immediately ready.

### S7-E10
- date: `2026-06-13 19:32:05 -0700`
- title: Service startup order fixed
- organization: Git / `origin/pranav-algorithm-camera` / `4dfa406`
- notes: Adjusted service startup ordering so the service starts before camera capture is required.

## Section S8: Final Judging BLE State

### S8-E01
- date: `2026-06-13 19:51:07 -0700`
- title: Pi button service active
- organization: Pi service log
- notes: `blindspot-button.service` was active with BLE enabled and LED disabled.

### S8-E02
- date: `2026-06-13 19:51:07 -0700`
- title: Pi advertising confirmed
- organization: Pi Bluetooth state
- notes: Pi Bluetooth was powered on and advertising as `BlindSpot-Pi`.

### S8-E03
- date: `2026-06-13 19:51:07 -0700 to 2026-06-13 23:47:13 -0700`
- title: Final demo path narrowed
- organization: Session notes
- notes: USB/cable stayed as power/debug, LED was scrapped, and BLE became the ride start/stop path.

### S8-E04
- date: `2026-06-13 23:47:13 -0700`
- title: BLE role mismatch found
- organization: BLE scan/verification
- notes: iPhone app was found advertising as BLE peripheral named `Blind Spot`, opposite of the first Pi BLE role.

### S8-E05
- date: `2026-06-13 23:47:13 -0700`
- title: Pi central BLE mode deployed
- organization: Pi deployment verification
- notes: Pi central/client BLE support was added locally, deployed to the Pi, and configured for the phone-side BLE signal.

### S8-E06
- date: `2026-06-13 23:47:13 -0700`
- title: BLE smoke test passed
- organization: BLE smoke test
- notes: Pi-to-iPhone BLE `ping` write succeeded, proving the Pi could reach the app Bluetooth service.

### S8-E07
- date: `2026-06-13 23:48:47 -0700`
- title: First timeline draft created
- organization: Local timeline work
- notes: First local `timeline.md` draft was created on `main`.

### S8-E08
- date: `2026-06-13 23:50:15 -0700`
- title: Timeline expanded from chat and branch history
- organization: Local timeline work
- notes: Timeline was rewritten to include actual chat history, project notes, and all fetched branch history.

### S8-E09
- date: `2026-06-13 23:55:03 -0700`
- title: Timeline given exact event markers
- organization: Local timeline work
- notes: Timeline was restructured with section-level event markers and explicit timestamp precision.

### S8-E10
- date: `2026-06-14 11:26:23 -0700`
- title: Timeline converted to Lumiai style
- organization: Current update
- notes: Timeline was converted to compact `date`, `title`, `organization`, and `notes` cards while keeping exact markers and timestamps.

## Issues And Resolutions

### I01
- date: `2026-06-13 11:07 -0700`
- title: Product scope started broad
- organization: PRD / planning
- notes: PRD included GPS, camera, IMU, LED/buzzer, local buffering, sync, CV, map, SOS, and recap. The build narrowed around button/photo/ride ID, Supabase upload, bike accessibility analysis, app map/recap/SOS, and BLE control.

### I02
- date: `2026-06-13 11:12 -0700`
- title: GPS ownership changed
- organization: Phone/Pi integration
- notes: GPS moved from possible Pi GPS module to iPhone-owned GPS and route/session UI. Pi kept button, camera, buffering, Supabase writes, and summary writes.

### I03
- date: `2026-06-13 11:44 -0700`
- title: Communication protocol changed several times
- organization: Phone/Pi integration
- notes: HTTP, MQTT, UDP, NTRIP, Bluetooth, and cable/COM were considered. MQTT was recommended for GPS streaming; BLE became final ride control because the phone app exposed a BLE service.

### I04
- date: `2026-06-13 11:45 -0700`
- title: Secret leakage risk
- organization: Git/GitHub hygiene
- notes: `.gitignore` was hardened; `codex.md` and `.env` stayed ignored; credentials and private keys are omitted from this timeline.

### I05
- date: `2026-06-13 11:46 -0700`
- title: Photo/button behavior needed clarity
- organization: PRD interpretation
- notes: Clarified one-button photo/event behavior and photo linkage to ride/event/location/time.

### I06
- date: `2026-06-13 13:18:15 -0700`
- title: LED strip did not visibly respond
- organization: Raspberry Pi hardware
- notes: LED was made optional and then disabled for the final demo.

### I07
- date: `2026-06-13 13:18:15 -0700`
- title: GPIO17 button looked permanently pressed
- organization: Raspberry Pi hardware
- notes: Clarified BCM GPIO17 / physical pin 11 to GND with pull-up and implemented one-button gestures.

### I08
- date: `2026-06-13 13:18:15 -0700`
- title: Lane detection needed bike context
- organization: Computer vision
- notes: Analysis shifted to green bike paint, bike symbols, lane type, blocked lanes, rough pavement, and hazards.

### I09
- date: `2026-06-13 16:21:05 -0700`
- title: Manual and machine photos needed separate tables
- organization: Supabase data model
- notes: Manual photos go to `photos`; automatic/machine photos go to `automated_photos`; both require a real `ride_id`.

### I10
- date: `2026-06-13 16:44:17 -0700`
- title: Pi editable install failed
- organization: Python packaging
- notes: Explicit package discovery was added in `pyproject.toml`.

### I11
- date: `2026-06-13 18:17:35 -0700`
- title: Pi networking and SSH were unreliable
- organization: Raspberry Pi deployment
- notes: IPv6 link-local SSH was used when available; SD boot and service setup were adjusted.

### I12
- date: `2026-06-13 19:29:37 -0700`
- title: Camera was unreliable at service startup
- organization: Raspberry Pi camera
- notes: Lazy/retry camera startup kept the service alive.

### I13
- date: `2026-06-13 23:47:13 -0700`
- title: BLE roles were mismatched
- organization: iPhone/Pi Bluetooth
- notes: Pi central/client mode was added while preserving original Pi-peripheral mode. Pi-to-phone BLE write was verified.

### I14
- date: `2026-06-13 23:48:47 -0700`
- title: GitHub publishing boundary changed
- organization: Git workflow
- notes: Earlier commits had been pushed, then later demo files stayed local until user explicitly requested a timeline push.

## Final Demo State

### F01
- date: `2026-06-13 23:47:13 -0700`
- title: Button service active
- organization: Raspberry Pi service
- notes: Pi button service was active.

### F02
- date: `2026-06-13 23:47:13 -0700`
- title: LED disabled
- organization: Raspberry Pi service
- notes: LED path was disabled.

### F03
- date: `2026-06-13 23:47:13 -0700`
- title: Phone BLE visible
- organization: iPhone app
- notes: iPhone app advertised Bluetooth as `Blind Spot`.

### F04
- date: `2026-06-13 23:47:13 -0700`
- title: Pi BLE central mode active
- organization: Raspberry Pi Bluetooth
- notes: Pi was configured as BLE central/client for the phone-side signal.

### F05
- date: `2026-06-13 23:47:13 -0700`
- title: Button gestures ready
- organization: Final demo controls
- notes: Single press captures manual photo; double press starts/stops video; long press starts/stops ride through phone BLE service.

### F06
- date: `2026-06-13 23:47:13 -0700`
- title: Photo routing contract ready
- organization: Supabase data model
- notes: Manual photos attach only to an active ride ID. Automated/machine photos go to `automated_photos`, not `photos`.

### F07
- date: `2026-06-13 23:47:13 -0700`
- title: BLE smoke test passed
- organization: Final demo verification
- notes: Last BLE smoke test succeeded with a Pi-to-phone write.
