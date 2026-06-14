//
//  Hazard.swift
//  Blind Spot
//
//  A crowd-sourced road hazard pinned to a location. Plain value type so it maps
//  1:1 to a future DB row.
//

import Foundation

struct Hazard: Codable, Identifiable, Hashable {
    let id: UUID
    var lat: Double
    var lng: Double
    var type: HazardType
    var severity: Severity
    var status: HazardStatus
    /// How many riders have confirmed this hazard (crowd-sourcing signal).
    var confirmCount: Int
    var firstReportedAt: Date
    var lastConfirmedAt: Date?

    init(
        id: UUID = UUID(),
        lat: Double,
        lng: Double,
        type: HazardType,
        severity: Severity,
        status: HazardStatus = .reported,
        confirmCount: Int = 0,
        firstReportedAt: Date,
        lastConfirmedAt: Date? = nil
    ) {
        self.id = id
        self.lat = lat
        self.lng = lng
        self.type = type
        self.severity = severity
        self.status = status
        self.confirmCount = confirmCount
        self.firstReportedAt = firstReportedAt
        self.lastConfirmedAt = lastConfirmedAt
    }
}
