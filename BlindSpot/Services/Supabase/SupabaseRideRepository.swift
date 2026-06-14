//
//  SupabaseRideRepository.swift
//  Blind Spot
//
//  `RideRepository` backed by Supabase Postgres. A ride is stored across three
//  tables — `rides` (summary), `ride_points` (GPS polyline), `ride_events`
//  (flags/impacts/crashes) — all owned by the signed-in user (RLS by Firebase
//  UID). Rides persist across sign-out/in because they live server-side.
//
//  Dates are written/read as ISO-8601 strings (see SupabaseDate) so Postgres
//  `timestamptz` columns accept them.
//

import Foundation
import Supabase

final class SupabaseRideRepository: RideRepository {

    private let client: SupabaseClient
    /// Returns the current Firebase UID (the row owner). Provided by the
    /// composition root so this type stays free of Firebase imports.
    private let userId: @Sendable () -> String?

    init(client: SupabaseClient, userId: @escaping @Sendable () -> String?) {
        self.client = client
        self.userId = userId
    }

    // MARK: - Fetch

    func fetchRides() async throws -> [Ride] {
        // RLS limits this to the signed-in user's rows automatically.
        let rows: [RideRow] = try await client
            .from("rides")
            .select()
            .order("started_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toDomain() }
    }

    func fetchRide(id: UUID) async throws -> (Ride, [RidePoint], [RideEvent])? {
        let rideRows: [RideRow] = try await client
            .from("rides").select().eq("id", value: id.uuidString).limit(1)
            .execute().value
        guard let ride = rideRows.first?.toDomain() else { return nil }

        let pointRows: [PointRow] = try await client
            .from("ride_points").select().eq("ride_id", value: id.uuidString)
            .order("recorded_at", ascending: true)
            .execute().value

        let eventRows: [EventRow] = try await client
            .from("ride_events").select().eq("ride_id", value: id.uuidString)
            .order("occurred_at", ascending: true)
            .execute().value

        return (ride, pointRows.map { $0.toDomain() }, eventRows.map { $0.toDomain() })
    }

    // MARK: - Save / delete

    func saveRide(_ ride: Ride, points: [RidePoint], events: [RideEvent]) async throws {
        let uid = userId() ?? ""

        try await client.from("rides").upsert(RideRow(ride, userId: uid)).execute()

        if !points.isEmpty {
            let rows = points.map { PointRow($0, rideId: ride.id, userId: uid) }
            try await client.from("ride_points").insert(rows).execute()
        }
        if !events.isEmpty {
            let rows = events.map { EventRow($0, rideId: ride.id, userId: uid) }
            try await client.from("ride_events").insert(rows).execute()
        }
    }

    func setRating(rideId: UUID, rating: Int) async throws {
        try await client
            .from("rides")
            .update(["rating": rating])
            .eq("id", value: rideId.uuidString)
            .execute()
    }

    func setFavorite(rideId: UUID, favorite: Bool) async throws {
        try await client
            .from("rides")
            .update(["favorite": favorite])
            .eq("id", value: rideId.uuidString)
            .execute()
    }

    func deleteRide(id: UUID) async throws {
        // points/events are removed automatically via ON DELETE CASCADE.
        try await client.from("rides").delete().eq("id", value: id.uuidString).execute()
    }

    func fetchAISummary(rideId: UUID) async throws -> RideAISummary? {
        // Prefer the ride-level summary; newest first.
        let rows: [AISummaryRow] = try await client
            .from("ai_summary")
            .select()
            .eq("ride_id", value: rideId.uuidString)
            .eq("summary_type", value: "ride")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.toDomain()
    }

    func fetchPhotos(rideId: UUID) async throws -> [RidePhoto] {
        var photos: [RidePhoto] = []

        // Manual photos (the `photos` table).
        let manual: [PhotoRow] = try await client
            .from("photos")
            .select()
            .eq("ride_id", value: rideId.uuidString)
            .order("captured_at", ascending: true)
            .execute()
            .value
        photos += manual.compactMap { $0.toDomain(isMachine: false) }

        // Machine photos (best-effort — table may be empty or shaped differently).
        if let machine: [PhotoRow] = try? await client
            .from("automated_photos")
            .select()
            .eq("ride_id", value: rideId.uuidString)
            .order("captured_at", ascending: true)
            .execute()
            .value {
            photos += machine.compactMap { $0.toDomain(isMachine: true) }
        }
        return photos
    }

    /// Mirrors the `photos` columns we use (tolerant; works for automated_photos
    /// too as long as it has id/ride_id/storage_url).
    private struct PhotoRow: Codable {
        let id: UUID
        let ride_id: UUID
        let storage_url: String?
        let captured_at: String?
        let event_type: String?

        func toDomain(isMachine: Bool) -> RidePhoto? {
            guard let s = storage_url, let url = URL(string: s) else { return nil }
            return RidePhoto(id: id, rideId: ride_id, url: url,
                             capturedAt: captured_at.flatMap(SupabaseDate.date(from:)),
                             eventType: event_type, isMachine: isMachine)
        }
    }

    /// Mirrors the `ai_summary` columns we use. All optional → tolerant decoding
    /// (extra columns like metrics/raw_response are ignored).
    private struct AISummaryRow: Codable {
        let id: UUID
        let ride_id: UUID
        let summary: String?
        let accessibility_score: Int?
        let accessibility_rating: String?
        let potholes_detected: Bool?
        let pothole_count: Int?
        let labels: [String]?
        let observations: [String]?
        let road_hazards: [String]?
        let recommended_map_tags: [String]?

        func toDomain() -> RideAISummary {
            RideAISummary(
                id: id,
                rideId: ride_id,
                summary: summary ?? "",
                accessibilityScore: accessibility_score ?? 0,
                accessibilityRating: accessibility_rating ?? "—",
                potholesDetected: potholes_detected ?? false,
                potholeCount: pothole_count ?? 0,
                labels: labels ?? [],
                observations: observations ?? [],
                roadHazards: road_hazards ?? [],
                recommendedMapTags: recommended_map_tags ?? []
            )
        }
    }

    // MARK: - DB rows (snake_case ↔ domain; dates as ISO strings)

    /// Device that owns the ride. The `rides.device_id` column is NOT NULL; the
    /// phone owns the ride session, so it tags rides with this label. (Pi-attached
    /// photos/AI rows reference the ride by ride_id, not device_id.)
    static let phoneDeviceID = "blindspot-iphone"

    private struct RideRow: Codable {
        let id: UUID
        let user_id: String
        let device_id: String
        let started_at: String
        let ended_at: String?
        let distance_meters: Double
        let duration_seconds: Double
        let avg_speed: Double
        let safety_score: Int?
        let rating: Int?
        let favorite: Bool?
        // Pi-measured values (decode-only; the Pi populates these on processed rides).
        let distance_m: Double?
        let duration_s: Double?

        init(_ r: Ride, userId: String) {
            id = r.id; user_id = userId
            device_id = SupabaseRideRepository.phoneDeviceID
            started_at = SupabaseDate.string(from: r.startedAt)
            ended_at = r.endedAt.map(SupabaseDate.string(from:))
            distance_meters = r.distanceMeters; duration_seconds = r.durationSeconds
            avg_speed = r.avgSpeed; safety_score = r.safetyScore; rating = r.rating
            favorite = r.favorite
            distance_m = nil; duration_s = nil
        }

        func toDomain() -> Ride {
            // Prefer the phone's own tracking; fall back to the Pi's measured
            // distance/duration when the phone didn't track (e.g. Pi-only rides).
            let distance = distance_meters > 0 ? distance_meters : (distance_m ?? 0)
            let duration = duration_seconds > 0 ? duration_seconds : (duration_s ?? 0)
            // Use the stored avg speed if present, else derive it from distance/time.
            let avg = avg_speed > 0 ? avg_speed : (duration > 0 ? distance / duration : 0)
            return Ride(id: id,
                        startedAt: SupabaseDate.date(from: started_at) ?? Date(),
                        endedAt: ended_at.flatMap(SupabaseDate.date(from:)),
                        distanceMeters: distance, durationSeconds: duration,
                        avgSpeed: avg, safetyScore: safety_score, rating: rating,
                        favorite: favorite ?? false)
        }

        enum CodingKeys: String, CodingKey {
            case id, user_id, device_id, started_at, ended_at, distance_meters
            case duration_seconds, avg_speed, safety_score, rating, favorite
            case distance_m, duration_s
        }

        // Decodable reads every column (favorite is optional, so it's fine whether
        // or not the column exists yet).
        //
        // Encodable intentionally OMITS `favorite` so inserting/updating a ride
        // never references a column that may not exist. Favorites are written via
        // the dedicated `setFavorite` UPDATE instead.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(user_id, forKey: .user_id)
            try c.encode(device_id, forKey: .device_id)
            try c.encode(started_at, forKey: .started_at)
            try c.encodeIfPresent(ended_at, forKey: .ended_at)
            try c.encode(distance_meters, forKey: .distance_meters)
            try c.encode(duration_seconds, forKey: .duration_seconds)
            try c.encode(avg_speed, forKey: .avg_speed)
            try c.encodeIfPresent(safety_score, forKey: .safety_score)
            try c.encodeIfPresent(rating, forKey: .rating)
            // favorite intentionally not encoded
        }
    }

    private struct PointRow: Codable {
        let id: UUID
        let ride_id: UUID
        let user_id: String
        let lat: Double
        let lng: Double
        let speed: Double?
        let recorded_at: String

        init(_ p: RidePoint, rideId: UUID, userId: String) {
            id = p.id; ride_id = rideId; user_id = userId
            lat = p.lat; lng = p.lng; speed = p.speed
            recorded_at = SupabaseDate.string(from: p.recordedAt)
        }

        func toDomain() -> RidePoint {
            RidePoint(id: id, lat: lat, lng: lng, speed: speed,
                      recordedAt: SupabaseDate.date(from: recorded_at) ?? Date())
        }
    }

    private struct EventRow: Codable {
        let id: UUID
        let ride_id: UUID
        let user_id: String
        let type: String
        let hazard_type: String?
        let lat: Double
        let lng: Double
        let imu_magnitude: Double?
        let occurred_at: String
        let detected: Bool

        init(_ e: RideEvent, rideId: UUID, userId: String) {
            id = e.id; ride_id = rideId; user_id = userId
            type = e.type.rawValue; hazard_type = e.hazardType?.rawValue
            lat = e.lat; lng = e.lng; imu_magnitude = e.imuMagnitude
            occurred_at = SupabaseDate.string(from: e.occurredAt); detected = e.detected
        }

        func toDomain() -> RideEvent {
            RideEvent(
                id: id,
                type: EventType(rawValue: type) ?? .manualFlag,
                hazardType: hazard_type.flatMap(HazardType.init(rawValue:)),
                lat: lat, lng: lng, imuMagnitude: imu_magnitude,
                occurredAt: SupabaseDate.date(from: occurred_at) ?? Date(),
                detected: detected
            )
        }
    }
}
