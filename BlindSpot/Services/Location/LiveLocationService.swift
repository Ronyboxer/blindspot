//
//  LiveLocationService.swift
//  Blind Spot
//
//  CoreLocation-backed `LocationService`. Created on the main thread, so its
//  CLLocationManager delivers delegate callbacks on the main thread — we mutate
//  observable state directly there.
//

import Foundation
import CoreLocation
import Observation

@Observable
final class LiveLocationService: NSObject, LocationService, CLLocationManagerDelegate {

    // Observation ignores the manager itself (it's not UI state).
    @ObservationIgnored private let manager = CLLocationManager()

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var currentSpeedMPS: Double = 0
    private(set) var isTracking = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        // Update on every small movement; CoreLocation still throttles to ~1 Hz.
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    // Foreground "standby" updates (map viewing / hazard reporting), separate from
    // ride tracking so stopping one doesn't kill the other.
    @ObservationIgnored private var standbyActive = false

    func startUpdates() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        standbyActive = true
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        standbyActive = false
        // Don't stop the GPS if a ride is still recording.
        if !isTracking {
            manager.stopUpdatingLocation()
        }
    }

    func startTracking() {
        // Make sure we're authorized; request if needed.
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        isTracking = true
        // Keep tracking when backgrounded mid-ride (requires UIBackgroundModes
        // "location" in Info.plist). Shows the blue status bar.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        manager.allowsBackgroundLocationUpdates = false
        // Keep updating if the map is still in standby; otherwise stop.
        if !standbyActive {
            manager.stopUpdatingLocation()
        }
        currentSpeedMPS = 0
    }

    // MARK: - CLLocationManagerDelegate (called on the main thread)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        // If the user granted while we intended to track, (re)start.
        if isTracking,
           authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        // CLLocation.speed is < 0 when unavailable; clamp to 0.
        currentSpeedMPS = max(0, location.speed)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. no fix yet) are common; ignore quietly.
    }
}
