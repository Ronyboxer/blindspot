//
//  RidePoint.swift
//  Blind Spot
//
//  A single GPS sample along a ride. A ride's ordered list of these forms its
//  route polyline.
//

import Foundation

struct RidePoint: Codable, Identifiable, Hashable {
    let id: UUID
    var lat: Double
    var lng: Double
    var speed: Double?    // meters/second, optional (may be missing from a fix)
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        lat: Double,
        lng: Double,
        speed: Double? = nil,
        recordedAt: Date
    ) {
        self.id = id
        self.lat = lat
        self.lng = lng
        self.speed = speed
        self.recordedAt = recordedAt
    }
}
