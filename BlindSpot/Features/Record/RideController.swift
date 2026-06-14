//
//  RideController.swift
//  Blind Spot
//
//  The single source of truth for an active ride. Driven by BOTH the UI (the big
//  start button on the Record screen) and the Raspberry Pi (via the local HTTP
//  server, see RideControlServer). Owns CoreLocation route tracking, IMU/crash
//  detection, hazard flagging, and Supabase persistence.
//
//  Key difference from a normal record flow: the Supabase ride row is created at
//  START (so the Pi immediately gets a `ride_id` to attach photos to), and the
//  same row is updated with the route + final stats at STOP.
//
//  Lives in AppEnvironment and is shared app-wide, so it's constructed with its
//  dependencies rather than receiving them per-call.
//

import Foundation
import Observation
import CoreLocation

@MainActor
@Observable
final class RideController {

    enum Phase { case idle, recording }

    // MARK: Dependencies
    private let rideRepository: RideRepository
    private let hazardRepository: HazardRepository
    private let locationService: LocationService
    private let motionService: MotionService

    init(rideRepository: RideRepository,
         hazardRepository: HazardRepository,
         locationService: LocationService,
         motionService: MotionService) {
        self.rideRepository = rideRepository
        self.hazardRepository = hazardRepository
        self.locationService = locationService
        self.motionService = motionService
    }

    // MARK: Published state
    private(set) var phase: Phase = .idle
    /// The Supabase ride id of the active (or just-finished) ride.
    private(set) var currentRideId: UUID?
    private(set) var elapsedSeconds: Int = 0
    private(set) var distanceMeters: Double = 0
    private(set) var currentSpeedMPS: Double = 0
    private(set) var peakIMU: Double = 0
    private(set) var events: [RideEvent] = []
    private(set) var flagConfirmation: String?
    private(set) var saveError: String?
    /// Where the last start/stop came from — handy for the UI to show.
    private(set) var startedByPi = false

    // Crash SOS shell
    private(set) var sosActive = false
    private(set) var sosCountdown = RideController.sosSeconds
    private(set) var sosSent = false

    // Tuning
    static let sosSeconds = 5            // crash-SOS countdown length (seconds)
    static let impactThreshold = 2.2     // g → logs an impact event
    static let crashThreshold = 3.5      // g → big standalone impact = crash SOS
    static let freeFallThreshold = 0.35  // g (total) → device is ~weightless (falling)
    static let fallImpactThreshold = 1.8 // g → impact right after a free-fall = a fall

    // MARK: Private
    private var rideStart: Date?
    private var points: [RidePoint] = []
    private var lastFix: CLLocation?
    private var timer: Timer?
    private var sosTimer: Timer?
    private var lastImpactAt: Date?
    private var lastFreeFallAt: Date?

    // MARK: - Start (creates the Supabase row, returns its id)

    /// Begins a ride: creates the ride row in Supabase, then starts tracking.
    /// Returns the new ride id only after the row exists (or nil on failure).
    @discardableResult
    func start(triggeredByPi: Bool = false) async -> UUID? {
        guard phase == .idle else { return currentRideId }  // already recording

        let id = UUID()
        let start = Date()

        // Begin recording IMMEDIATELY so the start control always responds, even
        // if the network is slow/unavailable.
        currentRideId = id
        rideStart = start
        startedByPi = triggeredByPi
        phase = .recording
        elapsedSeconds = 0
        distanceMeters = 0
        currentSpeedMPS = 0
        peakIMU = 0
        events = []
        points = []
        lastFix = nil
        saveError = nil

        locationService.startTracking()
        motionService.start { [weak self] impact, total in
            Task { @MainActor in self?.handleMotion(impact: impact, total: total) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        // Create/open the Supabase row so the Pi has a ride_id. Non-fatal: if it
        // fails we keep recording and re-upsert the full ride at stop.
        let opening = Ride(id: id, startedAt: start, endedAt: nil,
                           distanceMeters: 0, durationSeconds: 0, avgSpeed: 0)
        do {
            try await rideRepository.saveRide(opening, points: [], events: [])
        } catch {
            saveError = "Recording locally — couldn't reach the server (will sync on stop)."
        }
        return id
    }

    private func tick() {
        elapsedSeconds += 1
        currentSpeedMPS = locationService.currentSpeedMPS

        guard let fix = locationService.currentLocation else { return }
        if let last = lastFix {
            let delta = fix.distance(from: last)
            if delta >= 2 && delta < 200 {   // ignore jitter / implausible jumps
                distanceMeters += delta
                appendPoint(fix)
            }
        } else {
            appendPoint(fix)
        }
    }

    private func appendPoint(_ fix: CLLocation) {
        points.append(RidePoint(
            lat: fix.coordinate.latitude,
            lng: fix.coordinate.longitude,
            speed: max(0, fix.speed),
            recordedAt: Date()
        ))
        lastFix = fix
    }

    // MARK: - IMU / impacts

    private func handleMotion(impact: Double, total: Double) {
        peakIMU = max(peakIMU, impact)

        // Remember the moment of free-fall (device weightless = falling).
        if total < Self.freeFallThreshold { lastFreeFallAt = Date() }

        guard impact >= Self.impactThreshold else { return }

        let now = Date()
        let cooled = lastImpactAt.map { now.timeIntervalSince($0) > 3 } ?? true
        guard cooled else { return }
        lastImpactAt = now

        let coord = locationService.currentLocation?.coordinate
        events.append(RideEvent(type: .impact,
                                lat: coord?.latitude ?? 0, lng: coord?.longitude ?? 0,
                                imuMagnitude: impact, occurredAt: now, detected: true))

        // A fast FALL = free-fall immediately followed by an impact. Also fire on a
        // very large standalone impact (a hard crash with no clean free-fall phase).
        let justFell = lastFreeFallAt.map { now.timeIntervalSince($0) < 1.2 } ?? false
        if (justFell && impact >= Self.fallImpactThreshold) || impact >= Self.crashThreshold {
            triggerCrashSOS(magnitude: impact, detected: true)
        }
    }

    // MARK: - Flagging

    func flag(_ hazardType: HazardType) {
        let coord = locationService.currentLocation?.coordinate
        let lat = coord?.latitude ?? 0
        let lng = coord?.longitude ?? 0

        events.append(RideEvent(type: .manualFlag, hazardType: hazardType,
                                lat: lat, lng: lng,
                                imuMagnitude: peakIMU > 0 ? peakIMU : nil,
                                occurredAt: Date(), detected: false))

        if coord != nil {
            let hazard = Hazard(lat: lat, lng: lng, type: hazardType,
                                severity: .moderate, status: .reported, firstReportedAt: Date())
            Task { try? await hazardRepository.reportHazard(hazard) }
        }

        flagConfirmation = "\(hazardType.displayName) flagged"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.flagConfirmation = nil
        }
    }

    // MARK: - Stop (uploads route + closes the row with ended_at)

    /// Stops the active ride, uploads the route/events, and closes the row.
    /// Returns the finished ride id, or nil on failure.
    @discardableResult
    func stop() async -> UUID? {
        timer?.invalidate(); timer = nil
        locationService.stopTracking()
        motionService.stop()

        guard let start = rideStart, let id = currentRideId else {
            phase = .idle
            return nil
        }

        let duration = Double(elapsedSeconds)
        let avgSpeed = duration > 0 ? distanceMeters / duration : 0
        let detectedCount = events.filter { $0.type != .manualFlag }.count

        let finished = Ride(id: id, startedAt: start, endedAt: Date(),
                            distanceMeters: distanceMeters, durationSeconds: duration,
                            avgSpeed: avgSpeed,
                            safetyScore: max(40, 95 - detectedCount * 8), rating: nil)

        do {
            // Upserts the existing row (adds ended_at + stats) and inserts route/events.
            try await rideRepository.saveRide(finished, points: points, events: events)
        } catch {
            saveError = "Couldn't save your ride. Check your connection and try again."
            return nil
        }

        reset()
        return id
    }

    private func reset() {
        phase = .idle
        elapsedSeconds = 0
        distanceMeters = 0
        currentSpeedMPS = 0
        peakIMU = 0
        events = []
        points = []
        rideStart = nil
        lastFix = nil
        startedByPi = false
        // currentRideId is kept so the UI can navigate to the recap.
    }

    // MARK: - Crash SOS

    func simulateCrash() { triggerCrashSOS(magnitude: 6.4, detected: false) }

    private func triggerCrashSOS(magnitude: Double, detected: Bool) {
        guard !sosActive else { return }
        if phase == .recording {
            let coord = locationService.currentLocation?.coordinate
            events.append(RideEvent(type: .crash,
                                    lat: coord?.latitude ?? 0, lng: coord?.longitude ?? 0,
                                    imuMagnitude: magnitude, occurredAt: Date(), detected: detected))
        }
        sosActive = true; sosSent = false; sosCountdown = Self.sosSeconds
        sosTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sosTick() }
        }
    }

    private func sosTick() {
        guard sosCountdown > 0 else {
            sosTimer?.invalidate(); sosTimer = nil; sosSent = true; return
        }
        sosCountdown -= 1
    }

    func dismissSOS() {
        sosTimer?.invalidate(); sosTimer = nil
        sosActive = false; sosSent = false; sosCountdown = Self.sosSeconds
    }
}

// MARK: - Remote control (Raspberry Pi via RideControlServer)

extension RideController: RideControlDelegate {
    /// The active ride id (nil when idle).
    var activeRideId: UUID? { phase == .recording ? currentRideId : nil }
    /// Status string for remote queries.
    var rideStatusString: String { phase == .recording ? "recording" : "idle" }

    func rideControlStart() async -> UUID? {
        await start(triggeredByPi: true)
    }

    func rideControlStop(rideId: UUID?) async -> Bool {
        // If the Pi names a ride, only stop when it matches the active one.
        if let rideId, let current = currentRideId, rideId != current { return false }
        return await stop() != nil
    }
}
