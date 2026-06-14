//
//  LocationService.swift
//  Blind Spot
//
//  The seam for live GPS. The real implementation wraps CoreLocation; a mock
//  drives previews with a moving fake location. Observable so the Map and the
//  Record screen react to new fixes.
//
//  Speed comes straight from CoreLocation's GPS Doppler speed (`CLLocation.speed`,
//  meters/second), which is what makes the readout accurate — far better than
//  integrating position. Invalid speeds (-1) are reported as 0.
//

import Foundation
import CoreLocation

/// Abstract live-location provider.
protocol LocationService: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    /// Most recent GPS fix (nil until the first one arrives).
    var currentLocation: CLLocation? { get }
    /// Latest valid speed in meters/second (0 when unknown / stationary).
    var currentSpeedMPS: Double { get }
    var isTracking: Bool { get }

    func requestAuthorization()
    /// Begin lightweight foreground updates (e.g. while viewing the map) so the
    /// user's location is available without a ride being active.
    func startUpdates()
    func stopUpdates()
    /// Begin high-accuracy updates suitable for an active ride (background-enabled).
    func startTracking()
    func stopTracking()
}
