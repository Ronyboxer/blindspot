//
//  MapScreen.swift
//  Blind Spot
//
//  The hazard map: a SwiftUI `Map` centered on San Jose with an `Annotation`
//  per mock hazard (rendered via `HazardBadge` pins), plus a small severity
//  legend. Reads hazards through the repository (via the app environment).
//

import SwiftUI
import MapKit
import CoreLocation

struct MapScreen: View {

    // The dependency container; gives us the hazard repository.
    @Environment(AppEnvironment.self) private var environment

    @State private var viewModel = MapViewModel()
    // Where the user tapped to drop a new hazard, + the type-picker toggle.
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var showAddPicker = false
    // A tapped hazard (shows the Report/Delete actions) + the one being emailed.
    @State private var selectedHazard: Hazard?
    @State private var hazardToEmail: Hazard?

    private let reportEmail = "ronak.k.rupani@gmail.com"

    // Follow the rider's real location; fall back to San Jose until it's available.
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        fallback: .region(
            MKCoordinateRegion(
                center: SampleData.sanJose,
                span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
            )
        )
    )

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                // MapReader gives us a proxy to convert a tap point → coordinate.
                MapReader { proxy in
                    // MARK: Map with hazard annotations + the rider's live location
                    Map(position: $cameraPosition) {
                        // The blue user-location dot (requires location permission).
                        UserAnnotation()

                        ForEach(viewModel.hazards) { hazard in
                            Annotation(
                                hazard.type.displayName,
                                coordinate: CLLocationCoordinate2D(latitude: hazard.lat, longitude: hazard.lng)
                            ) {
                                // Tap a hazard to report (email) or delete it.
                                Button { selectedHazard = hazard } label: {
                                    HazardBadge(type: hazard.type, style: .pin)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .mapControls {
                        MapUserLocationButton()   // recenter on the rider
                        MapCompass()
                    }
                    .ignoresSafeArea(edges: .top)
                    // Tap empty map → drop a hazard at that point (pin taps are
                    // handled by their own Button above and won't trigger this).
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            pendingCoordinate = coordinate
                            showAddPicker = true
                        }
                    }
                }

                // Hint.
                Text("Tap the map to add a hazard")
                    .font(.bsCaption)
                    .foregroundStyle(Color.bsWhite.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.bsCharcoal.opacity(0.9), in: Capsule())
                    .padding(.bottom, 24)
            }
            .navigationTitle("Hazard Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bsCharcoal, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Ask for location + start foreground updates so the blue dot shows,
            // the camera can follow the rider, and "report here" knows the location.
            .task {
                environment.locationService.requestAuthorization()
                environment.locationService.startUpdates()
                await viewModel.load(using: environment.hazardRepository)
            }
            .onDisappear { environment.locationService.stopUpdates() }
            .overlay {
                if viewModel.isLoading && viewModel.hazards.isEmpty {
                    ProgressView().tint(.bsPrimary)
                }
            }
            // Pick the hazard type to drop at the tapped location.
            .confirmationDialog("Add a hazard here", isPresented: $showAddPicker,
                                titleVisibility: .visible) {
                ForEach(HazardType.allCases) { type in
                    Button(type.displayName) { addHazard(type) }
                }
                Button("Cancel", role: .cancel) {}
            }
            // Tapped a hazard → Report (email) or Delete.
            .confirmationDialog(
                selectedHazard?.type.displayName ?? "Hazard",
                isPresented: Binding(get: { selectedHazard != nil },
                                     set: { if !$0 { selectedHazard = nil } }),
                titleVisibility: .visible,
                presenting: selectedHazard
            ) { hazard in
                Button("Report (email)") { reportByEmail(hazard); selectedHazard = nil }
                Button("Delete", role: .destructive) { deleteHazard(hazard); selectedHazard = nil }
                Button("Cancel", role: .cancel) { selectedHazard = nil }
            }
            // Mail composer for reporting a hazard (user reviews + sends).
            .sheet(item: $hazardToEmail) { hazard in
                MailView(recipients: [reportEmail],
                         subject: "Blind Spot — Hazard report: \(hazard.type.displayName)",
                         body: hazardEmailBody(hazard))
            }
        }
    }

    // MARK: Hazard actions

    private func deleteHazard(_ hazard: Hazard) {
        Task {
            try? await environment.hazardRepository.deleteHazard(id: hazard.id)
            await viewModel.load(using: environment.hazardRepository)
        }
    }

    private func reportByEmail(_ hazard: Hazard) {
        if MailView.canSend {
            hazardToEmail = hazard
        } else if let url = mailtoURL(for: hazard) {
            UIApplication.shared.open(url)
        }
    }

    private func hazardEmailBody(_ hazard: Hazard) -> String {
        """
        Blind Spot hazard report

        Type: \(hazard.type.displayName)
        Location: \(Format.coord(lat: hazard.lat, lng: hazard.lng))
        Reported: \(Format.rideDate(hazard.firstReportedAt))
        Status: \(hazard.status.displayName)
        Confirmations: \(hazard.confirmCount)
        """
    }

    private func mailtoURL(for hazard: Hazard) -> URL? {
        var c = URLComponents(string: "mailto:\(reportEmail)")
        c?.queryItems = [
            URLQueryItem(name: "subject", value: "Blind Spot — Hazard report: \(hazard.type.displayName)"),
            URLQueryItem(name: "body", value: hazardEmailBody(hazard))
        ]
        return c?.url
    }

    /// Add a hazard of `type` at the tapped map coordinate.
    private func addHazard(_ type: HazardType) {
        guard let coordinate = pendingCoordinate else { return }
        let hazard = Hazard(
            lat: coordinate.latitude, lng: coordinate.longitude,
            type: type, severity: .moderate, status: .reported,
            firstReportedAt: Date()
        )
        pendingCoordinate = nil
        Task {
            try? await environment.hazardRepository.reportHazard(hazard)
            await viewModel.load(using: environment.hazardRepository)
        }
    }
}

#Preview {
    MapScreen()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
