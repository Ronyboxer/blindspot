//
//  MockLocationService.swift
//  Blind Spot
//
//  Preview/offline `LocationService`. Reports a fixed San Jose location and a
//  steady speed so previews render without GPS. Does not move on its own.
//

import Foundation
import CoreLocation
import Observation

@Observable
final class MockLocationService: LocationService {

    private(set) var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    private(set) var currentLocation: CLLocation?
    private(set) var currentSpeedMPS: Double = 6.7   // ~15 mph
    private(set) var isTracking = false

    init() {
        currentLocation = CLLocation(latitude: 37.3382, longitude: -121.8863)
    }

    func requestAuthorization() {}
    func startUpdates() {}
    func stopUpdates() {}
    func startTracking() { isTracking = true }
    func stopTracking() { isTracking = false }
}
