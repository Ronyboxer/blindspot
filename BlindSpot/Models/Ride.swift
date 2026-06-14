//
//  Ride.swift
//  Blind Spot
//
//  A recorded ride summary. The detailed polyline (`RidePoint`s) and notable
//  moments (`RideEvent`s) are stored separately and fetched alongside it.
//

import Foundation

struct Ride: Codable, Identifiable, Hashable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double
    var durationSeconds: Double
    var avgSpeed: Double          // meters/second
    var safetyScore: Int?         // 0–100, set by the future scoring service
    var rating: Int?              // 1–5, set by the rider
    var favorite: Bool            // starred by the rider

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        distanceMeters: Double,
        durationSeconds: Double,
        avgSpeed: Double,
        safetyScore: Int? = nil,
        rating: Int? = nil,
        favorite: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.avgSpeed = avgSpeed
        self.safetyScore = safetyScore
        self.rating = rating
        self.favorite = favorite
    }
}
