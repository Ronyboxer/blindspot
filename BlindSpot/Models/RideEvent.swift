//
//  RideEvent.swift
//  Blind Spot
//
//  A notable moment during a ride — a manually flagged hazard, a detected
//  anomaly (impact / hard brake / swerve), or a crash.
//

import Foundation

struct RideEvent: Codable, Identifiable, Hashable {
    let id: UUID
    var type: EventType
    /// If this event is a hazard flag, what kind of hazard. Nil for e.g. a crash.
    var hazardType: HazardType?
    var lat: Double
    var lng: Double
    /// IMU magnitude (g-force-ish) at the moment, if measured. Set by sensors later.
    var imuMagnitude: Double?
    var occurredAt: Date
    /// Whether the (future) ML service auto-DETECTED this event.
    /// Defaults to `false`: a manual flag is not "detected".
    var detected: Bool

    init(
        id: UUID = UUID(),
        type: EventType,
        hazardType: HazardType? = nil,
        lat: Double,
        lng: Double,
        imuMagnitude: Double? = nil,
        occurredAt: Date,
        detected: Bool = false
    ) {
        self.id = id
        self.type = type
        self.hazardType = hazardType
        self.lat = lat
        self.lng = lng
        self.imuMagnitude = imuMagnitude
        self.occurredAt = occurredAt
        self.detected = detected
    }
}
