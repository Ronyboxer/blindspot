//
//  RideRecapView.swift
//  Blind Spot
//
//  Post-ride recap: the route drawn as a `MapPolyline`, summary `StatTile`s,
//  an editable star rating (persisted via `setRating`), and a photos placeholder.
//
//  Loads the full ride detail (summary + points + events) from the repository
//  by id, so it works equally for seeded rides and ones just saved by Record.
//

import SwiftUI
import MapKit
import CoreLocation
import Observation

// MARK: - View model

@MainActor
@Observable
final class RideRecapViewModel {

    private(set) var ride: Ride?
    private(set) var points: [RidePoint] = []
    private(set) var events: [RideEvent] = []
    private(set) var aiSummary: RideAISummary?
    private(set) var photos: [RidePhoto] = []
    private(set) var isLoading = false

    /// The route as map coordinates (derived from points).
    var routeCoordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    /// Number of hazard flags / events on this ride (shown as a stat).
    var hazardCount: Int { events.count }

    /// Potholes on this ride: manual pothole flags + IMU impacts, and the AI's
    /// pothole count if it has been computed.
    var potholeCount: Int {
        let fromEvents = events.filter {
            ($0.type == .manualFlag && $0.hazardType == .pothole) || $0.type == .impact
        }.count
        return max(fromEvents, aiSummary?.potholeCount ?? 0)
    }

    /// Coordinates of the pothole/impact events, for the email body.
    var potholeLocations: [String] {
        events
            .filter { ($0.type == .manualFlag && $0.hazardType == .pothole) || $0.type == .impact }
            .map { Format.coord(lat: $0.lat, lng: $0.lng) }
    }

    func load(rideId: UUID, using repository: RideRepository) async {
        isLoading = true
        if let detail = try? await repository.fetchRide(id: rideId) {
            ride = detail.0
            points = detail.1
            events = detail.2
        }
        // The Pi's AI analysis (if it has finished processing the ride).
        aiSummary = try? await repository.fetchAISummary(rideId: rideId)
        // Photos captured during the ride.
        photos = (try? await repository.fetchPhotos(rideId: rideId)) ?? []
        isLoading = false
    }

    /// Persist a new rating and update local state so the stars reflect it.
    func setRating(_ rating: Int, using repository: RideRepository) async {
        guard let rideId = ride?.id else { return }
        try? await repository.setRating(rideId: rideId, rating: rating)
        ride?.rating = rating
    }
}

// MARK: - View

struct RideRecapView: View {
    let rideId: UUID
    /// When true (i.e. arriving right after a ride), offer to email a pothole
    /// report if any were detected.
    var autoPromptEmail: Bool = false

    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = RideRecapViewModel()
    @State private var showEmailPrompt = false
    @State private var showMailComposer = false
    @State private var didPromptEmail = false

    /// Where pothole reports are sent.
    private let reportEmail = "ronak.k.rupani@gmail.com"

    var body: some View {
        ZStack {
            Color.bsBlack.ignoresSafeArea()

            if let ride = viewModel.ride {
                ScrollView {
                    VStack(spacing: 16) {
                        routeMap
                        statsGrid(for: ride)
                        if let summary = viewModel.aiSummary {
                            aiSummaryCard(summary)
                        }
                        ratingCard(for: ride)
                        photosPlaceholder
                    }
                    .padding(16)
                }
            } else if viewModel.isLoading {
                ProgressView().tint(.bsPrimary)
            } else {
                Text("Ride not found.")
                    .font(.bsBody)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))
            }
        }
        .navigationTitle("Recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.bsCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await viewModel.load(rideId: rideId, using: environment.rideRepository)
            // At the end of a ride, offer to email a pothole report (asks first).
            if autoPromptEmail, !didPromptEmail, viewModel.potholeCount > 0 {
                didPromptEmail = true
                showEmailPrompt = true
            }
        }
        // Ask before emailing.
        .alert("Pothole report", isPresented: $showEmailPrompt) {
            Button("Email Report") { startEmail() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("\(viewModel.potholeCount) pothole\(viewModel.potholeCount == 1 ? "" : "s") detected on this ride. Email a report to \(reportEmail)?")
        }
        // The mail composer (the user reviews + sends).
        .sheet(isPresented: $showMailComposer) {
            MailView(recipients: [reportEmail],
                     subject: emailSubject,
                     body: emailBody)
        }
    }

    // MARK: - Pothole report email

    private func startEmail() {
        if MailView.canSend {
            showMailComposer = true
        } else if let url = mailtoURL {
            // No Mail account configured → hand off to a mail handler if present.
            UIApplication.shared.open(url)
        }
    }

    private var emailSubject: String {
        "Blind Spot — Pothole report (\(viewModel.potholeCount))"
    }

    private var emailBody: String {
        let r = viewModel.ride
        let date = r.map { Format.rideDate($0.startedAt) } ?? "—"
        let dist = r.map { "\(Format.miles($0.distanceMeters)) mi" } ?? "—"
        let dur = r.map { Format.duration($0.durationSeconds) } ?? "—"
        let locations = viewModel.potholeLocations.isEmpty
            ? "(no coordinates recorded)"
            : viewModel.potholeLocations.map { "• \($0)" }.joined(separator: "\n")
        return """
        Blind Spot pothole report

        Ride: \(date)
        Distance: \(dist)
        Duration: \(dur)
        Potholes detected: \(viewModel.potholeCount)

        Pothole locations:
        \(locations)
        """
    }

    private var mailtoURL: URL? {
        var c = URLComponents(string: "mailto:\(reportEmail)")
        c?.queryItems = [
            URLQueryItem(name: "subject", value: emailSubject),
            URLQueryItem(name: "body", value: emailBody)
        ]
        return c?.url
    }

    // MARK: Route map (polyline + event markers)

    private var routeMap: some View {
        Map(initialPosition: cameraPosition) {
            // The ride route as a bright yellow polyline.
            MapPolyline(coordinates: viewModel.routeCoordinates)
                .stroke(Color.bsPrimary, lineWidth: 5)

            // A marker per event along the route.
            ForEach(viewModel.events) { event in
                Annotation(
                    event.type.displayName,
                    coordinate: CLLocationCoordinate2D(latitude: event.lat, longitude: event.lng)
                ) {
                    Image(systemName: event.type.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.bsBlack)
                        .padding(7)
                        .background(Circle().fill(Color.bsPrimaryBright))
                        .overlay(Circle().stroke(Color.bsBlack, lineWidth: 1.5))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)   // recap map is for viewing, not panning
    }

    // Frame the camera on the route's bounding region.
    private var cameraPosition: MapCameraPosition {
        let coords = viewModel.routeCoordinates
        guard let first = coords.first else {
            return .region(MKCoordinateRegion(
                center: SampleData.sanJose,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }

        // Compute min/max bounds, then pad a little.
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.005, (maxLng - minLng) * 1.5)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: Stats grid

    private func statsGrid(for ride: Ride) -> some View {
        BSCard {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    StatTile(value: Format.miles(ride.distanceMeters), label: "Distance", unit: "mi")
                    StatTile(value: Format.duration(ride.durationSeconds), label: "Duration")
                }
                HStack(spacing: 12) {
                    StatTile(value: Format.mph(ride.avgSpeed), label: "Avg Speed", unit: "mph")
                    StatTile(value: "\(viewModel.hazardCount)", label: "Hazards")
                }
                HStack(spacing: 12) {
                    StatTile(
                        value: ride.safetyScore.map(String.init) ?? "—",
                        label: "Safety Score"
                    )
                    // Spacer tile to keep the grid balanced.
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: AI summary (from the Pi's post-ride analysis)

    private func aiSummaryCard(_ summary: RideAISummary) -> some View {
        BSCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("AI RIDE SUMMARY", systemImage: "sparkles")
                        .font(.bsCaption)
                        .tracking(1.2)
                        .foregroundStyle(Color.bsWhite.opacity(0.6))
                    Spacer()
                    aiRatingBadge(summary)
                }

                // The summary text.
                Text(summary.summary)
                    .font(.bsBody)
                    .foregroundStyle(Color.bsWhite)
                    .fixedSize(horizontal: false, vertical: true)

                // Potholes line (only if detected).
                if summary.potholesDetected {
                    Label("\(summary.potholeCount) pothole\(summary.potholeCount == 1 ? "" : "s") detected",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.bsModerate)
                }

                // Hazard / tag chips.
                let chips = summary.realHazards + summary.recommendedMapTags
                if !chips.isEmpty {
                    FlowChips(items: Array(Set(chips)).sorted())
                }
            }
        }
    }

    /// Coral-to-green rating pill driven by the AI accessibility score/word.
    private func aiRatingBadge(_ summary: RideAISummary) -> some View {
        let color: Color = {
            switch summary.accessibilityScore {
            case 80...:   return .bsGood
            case 50..<80: return .bsModerate
            default:      return .bsSevere
            }
        }()
        return HStack(spacing: 6) {
            Text(summary.accessibilityRating.capitalized)
                .font(.system(size: 13, weight: .heavy))
            Text("\(summary.accessibilityScore)")
                .font(.custom(BSFont.monoBold, size: 13))
        }
        .foregroundStyle(Color.bsBlack)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color)
        .clipShape(Capsule())
    }

    // MARK: Editable rating

    private func ratingCard(for ride: Ride) -> some View {
        BSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("RATE THIS RIDE")
                    .font(.bsCaption)
                    .tracking(1.2)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))

                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { star in
                        let filled = (ride.rating ?? 0) >= star
                        Image(systemName: filled ? "star.fill" : "star")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(filled ? Color.bsPrimary : Color.bsWhite.opacity(0.3))
                            .onTapGesture {
                                // Persist via the repo; VM updates local state.
                                Task {
                                    await viewModel.setRating(star, using: environment.rideRepository)
                                }
                            }
                            .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    }
                }
            }
        }
    }

    // MARK: Photos (from Supabase `photos` / `automated_photos`)

    private let photoColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var photosPlaceholder: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PHOTOS")
                        .font(.bsCaption)
                        .tracking(1.2)
                        .foregroundStyle(Color.bsWhite.opacity(0.6))
                    Spacer()
                    if !viewModel.photos.isEmpty {
                        Text("\(viewModel.photos.count)")
                            .font(.bsCaption)
                            .foregroundStyle(Color.bsWhite.opacity(0.4))
                    }
                }

                if viewModel.photos.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.bsCharcoal)
                                .frame(height: 80)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.bsWhite.opacity(0.3))
                                )
                        }
                    }
                    Text("Photos appear here after your Pi captures and uploads them.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bsWhite.opacity(0.4))
                } else {
                    LazyVGrid(columns: photoColumns, spacing: 8) {
                        ForEach(viewModel.photos) { photo in
                            photoThumbnail(photo)
                        }
                    }
                }
            }
        }
    }

    private func photoThumbnail(_ photo: RidePhoto) -> some View {
        AsyncImage(url: photo.url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.bsWhite.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bsCharcoal)
            default:
                ProgressView()
                    .tint(.bsPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bsCharcoal)
            }
        }
        .frame(height: 104)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Mark machine-captured photos.
        .overlay(alignment: .topTrailing) {
            if photo.isMachine {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.bsBlack)
                    .padding(4)
                    .background(Color.bsPrimary, in: Circle())
                    .padding(4)
            }
        }
    }
}

// MARK: - Chips

/// Horizontally scrolling capsule chips (hazard tags / map tags).
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.bsWhite.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.bsCharcoal)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

#Preview {
    // Preview with the first seeded ride (single expression — no `return`, so it
    // stays valid inside the #Preview ViewBuilder closure).
    NavigationStack {
        RideRecapView(rideId: SampleData.makeRides()[0].ride.id)
    }
    .environment(AppEnvironment.preview)
    .preferredColorScheme(.dark)
}
