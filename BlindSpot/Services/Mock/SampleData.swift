//
//  SampleData.swift
//  Blind Spot
//
//  Centralized in-memory seed data for the FOUNDATION milestone. Everything the
//  app shows today originates here. When the real data layer lands, this file
//  simply stops being used (the mock repos that reference it are swapped out).
//
//  All locations are scattered around San Jose, CA (37.3382, -121.8863).
//

import Foundation
import CoreLocation

/// Namespace for seed data + small geo helpers. Not instantiated.
enum SampleData {

    /// Map center / reference point: downtown San Jose.
    static let sanJose = CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)

    // MARK: - Hazards

    /// ~10 hazards mixing types, severities, and statuses around San Jose.
    /// Dates are relative to "now" so the UI always looks fresh.
    static func makeHazards(now: Date = Date()) -> [Hazard] {
        // Small helper for "N hours/days ago".
        func ago(hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        return [
            Hazard(lat: 37.3402, lng: -121.8901, type: .pothole, severity: .severe,
                   status: .confirmed, confirmCount: 12,
                   firstReportedAt: ago(hours: 50), lastConfirmedAt: ago(hours: 2)),

            Hazard(lat: 37.3361, lng: -121.8847, type: .glass, severity: .moderate,
                   status: .confirmed, confirmCount: 5,
                   firstReportedAt: ago(hours: 30), lastConfirmedAt: ago(hours: 6)),

            Hazard(lat: 37.3430, lng: -121.8825, type: .construction, severity: .severe,
                   status: .reported, confirmCount: 1,
                   firstReportedAt: ago(hours: 8)),

            Hazard(lat: 37.3318, lng: -121.8889, type: .debris, severity: .minor,
                   status: .reported, confirmCount: 2,
                   firstReportedAt: ago(hours: 4)),

            Hazard(lat: 37.3375, lng: -121.8950, type: .water, severity: .moderate,
                   status: .confirmed, confirmCount: 7,
                   firstReportedAt: ago(hours: 20), lastConfirmedAt: ago(hours: 1)),

            Hazard(lat: 37.3290, lng: -121.8810, type: .blockedLane, severity: .severe,
                   status: .confirmed, confirmCount: 9,
                   firstReportedAt: ago(hours: 16), lastConfirmedAt: ago(hours: 3)),

            Hazard(lat: 37.3445, lng: -121.8888, type: .pothole, severity: .moderate,
                   status: .reported, confirmCount: 3,
                   firstReportedAt: ago(hours: 12)),

            Hazard(lat: 37.3350, lng: -121.8790, type: .glass, severity: .minor,
                   status: .expired, confirmCount: 1,
                   firstReportedAt: ago(hours: 90), lastConfirmedAt: ago(hours: 80)),

            Hazard(lat: 37.3408, lng: -121.8772, type: .debris, severity: .moderate,
                   status: .confirmed, confirmCount: 4,
                   firstReportedAt: ago(hours: 26), lastConfirmedAt: ago(hours: 5)),

            Hazard(lat: 37.3300, lng: -121.8935, type: .construction, severity: .minor,
                   status: .reported, confirmCount: 2,
                   firstReportedAt: ago(hours: 18)),

            Hazard(lat: 37.3460, lng: -121.8860, type: .water, severity: .severe,
                   status: .reported, confirmCount: 1,
                   firstReportedAt: ago(hours: 3)),
        ]
    }

    // MARK: - Rides

    /// A bundle holding a ride and its detail, returned together by the mock repo.
    struct RideBundle {
        var ride: Ride
        var points: [RidePoint]
        var events: [RideEvent]
    }

    /// 3 sample rides, each with a realistic polyline and a few events.
    static func makeRides(now: Date = Date()) -> [RideBundle] {
        [
            makeRide(
                start: now.addingTimeInterval(-2 * 86400),  // 2 days ago
                origin: CLLocationCoordinate2D(latitude: 37.3320, longitude: -121.8900),
                heading: .northeast,
                pointCount: 28,
                stepMeters: 90,
                avgSpeed: 6.1,        // ~22 km/h
                safetyScore: 82,
                rating: 4,
                eventSpecs: [
                    (0.30, .manualFlag, .pothole),
                    (0.65, .hardBrake,  nil),
                ]
            ),
            makeRide(
                start: now.addingTimeInterval(-5 * 86400),  // 5 days ago
                origin: CLLocationCoordinate2D(latitude: 37.3410, longitude: -121.8820),
                heading: .southwest,
                pointCount: 40,
                stepMeters: 75,
                avgSpeed: 5.4,        // ~19 km/h
                safetyScore: 67,
                rating: 3,
                eventSpecs: [
                    (0.20, .manualFlag, .glass),
                    (0.50, .swerve,     nil),
                    (0.80, .impact,     .debris),
                ]
            ),
            makeRide(
                start: now.addingTimeInterval(-9 * 86400),  // 9 days ago
                origin: CLLocationCoordinate2D(latitude: 37.3290, longitude: -121.8850),
                heading: .east,
                pointCount: 18,
                stepMeters: 110,
                avgSpeed: 7.2,        // ~26 km/h
                safetyScore: 91,
                rating: nil,          // not yet rated — exercises the rating control
                eventSpecs: [
                    (0.45, .manualFlag, .water),
                ]
            ),
        ]
    }

    // MARK: - Ride synthesis helpers

    /// Compass-ish directions for laying down a simple straight-ish polyline.
    enum Heading {
        case north, south, east, west, northeast, southwest

        /// (dLat, dLng) unit step direction.
        var delta: (Double, Double) {
            switch self {
            case .north:     return ( 1,  0)
            case .south:     return (-1,  0)
            case .east:      return ( 0,  1)
            case .west:      return ( 0, -1)
            case .northeast: return ( 0.7,  0.7)
            case .southwest: return (-0.7, -0.7)
            }
        }
    }

    /// Build one ride: a gently wandering polyline from `origin`, plus events
    /// placed at fractional positions along it.
    ///
    /// `eventSpecs` = array of (fraction 0...1 along the route, event type, optional hazard type).
    private static func makeRide(
        start: Date,
        origin: CLLocationCoordinate2D,
        heading: Heading,
        pointCount: Int,
        stepMeters: Double,
        avgSpeed: Double,
        safetyScore: Int?,
        rating: Int?,
        eventSpecs: [(Double, EventType, HazardType?)]
    ) -> RideBundle {

        let rideId = UUID()

        // Seconds between samples, derived so distance/speed are self-consistent:
        // time per step = distance per step / speed.
        let secondsPerStep = stepMeters / max(avgSpeed, 0.1)

        // Convert a meters step into rough degree deltas. ~111_320 m per degree
        // latitude; longitude scaled by cos(latitude).
        let metersPerDegLat = 111_320.0
        let metersPerDegLng = 111_320.0 * cos(origin.latitude * .pi / 180)

        let (uLat, uLng) = heading.delta

        var points: [RidePoint] = []
        points.reserveCapacity(pointCount)

        var lat = origin.latitude
        var lng = origin.longitude

        for i in 0..<pointCount {
            // A little deterministic "wander" so the line isn't perfectly straight.
            // (No randomness needed — a sine wiggle keeps it reproducible.)
            let wiggle = sin(Double(i) * 0.6) * 0.15

            let dLatMeters = (uLat + wiggle) * stepMeters
            let dLngMeters = (uLng - wiggle) * stepMeters

            lat += dLatMeters / metersPerDegLat
            lng += dLngMeters / metersPerDegLng

            // Speed gently varies around the average.
            let speed = avgSpeed + sin(Double(i) * 0.4) * 1.2

            points.append(RidePoint(
                lat: lat,
                lng: lng,
                speed: max(0, speed),
                recordedAt: start.addingTimeInterval(Double(i) * secondsPerStep)
            ))
        }

        // Derived ride summary stats.
        let durationSeconds = Double(max(pointCount - 1, 0)) * secondsPerStep
        let distanceMeters  = Double(max(pointCount - 1, 0)) * stepMeters
        let end             = start.addingTimeInterval(durationSeconds)

        // Place events at their fractional positions along the polyline.
        let events: [RideEvent] = eventSpecs.map { fraction, type, hazardType in
            let idx = min(points.count - 1, max(0, Int(Double(points.count - 1) * fraction)))
            let p = points[idx]
            return RideEvent(
                type: type,
                hazardType: hazardType,
                lat: p.lat,
                lng: p.lng,
                // Give detected-ish events a plausible IMU magnitude.
                imuMagnitude: (type == .manualFlag) ? nil : Double.random(in: 1.8...4.5),
                occurredAt: p.recordedAt,
                // Manual flags are not "detected"; the rest pretend they were.
                detected: type != .manualFlag
            )
        }

        let ride = Ride(
            id: rideId,
            startedAt: start,
            endedAt: end,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            avgSpeed: avgSpeed,
            safetyScore: safetyScore,
            rating: rating
        )

        return RideBundle(ride: ride, points: points, events: events)
    }
}
