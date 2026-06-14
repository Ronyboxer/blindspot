//
//  RideListView.swift
//  Blind Spot
//
//  Lists recorded rides (date, distance, duration, safety-score badge). Tapping
//  a row pushes the ride recap.
//

import SwiftUI

struct RideListView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = RidesViewModel()
    // The ride pending a delete-confirmation.
    @State private var rideToDelete: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bsBlack.ignoresSafeArea()

                if viewModel.rides.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    // A List (not ScrollView) so we get native swipe actions,
                    // themed to the dark design system.
                    List {
                        ForEach(viewModel.rides) { ride in
                            NavigationLink(value: ride.id) {
                                RideRow(ride: ride)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            // Swipe LEFT (trailing edge) → Favorite / Delete.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    rideToDelete = ride.id
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }

                                Button {
                                    Task {
                                        await viewModel.toggleFavorite(
                                            id: ride.id, using: environment.rideRepository)
                                    }
                                } label: {
                                    Label(ride.favorite ? "Unfavorite" : "Favorite",
                                          systemImage: ride.favorite ? "star.slash.fill" : "star.fill")
                                }
                                .tint(.bsPrimary)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.bsBlack)
                    // Remove the List's default top inset.
                    .contentMargins(.top, 0, for: .scrollContent)
                    .environment(\.defaultMinListRowHeight, 0)
                }
            }
            .navigationTitle("Rides")
            // Inline (not the tall large-title bar) — that big bar was the gray space.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bsBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Confirm before deleting.
            .confirmationDialog(
                "Delete this ride?",
                isPresented: Binding(get: { rideToDelete != nil },
                                     set: { if !$0 { rideToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = rideToDelete {
                        Task { await viewModel.delete(id: id, using: environment.rideRepository) }
                    }
                    rideToDelete = nil
                }
                Button("Cancel", role: .cancel) { rideToDelete = nil }
            } message: {
                Text("This permanently removes the ride and its route.")
            }
            // Push the recap, keyed by ride id (the recap re-fetches detail).
            .navigationDestination(for: UUID.self) { rideId in
                RideRecapView(rideId: rideId)
            }
            // Reload each time the list appears so a freshly saved ride shows up.
            .task {
                await viewModel.load(using: environment.rideRepository)
            }
            .refreshable {
                await viewModel.load(using: environment.rideRepository)
            }
            .overlay {
                if viewModel.isLoading && viewModel.rides.isEmpty {
                    ProgressView().tint(.bsPrimary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Color.bsWhite.opacity(0.4))
            Text("No rides yet")
                .font(.bsHeadline)
                .foregroundStyle(Color.bsWhite)
            Text("Start a ride from the Record tab.")
                .font(.bsBody)
                .foregroundStyle(Color.bsWhite.opacity(0.6))
        }
        .padding()
    }
}

// MARK: - Ride row

/// One row in the rides list.
private struct RideRow: View {
    let ride: Ride

    var body: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    // Favorite star (filled when starred).
                    if ride.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.bsPrimary)
                    }
                    Text(Format.rideDate(ride.startedAt))
                        .font(.bsHeadline)
                        .foregroundStyle(Color.bsWhite)
                    Spacer()
                    SafetyScoreBadge(score: ride.safetyScore)
                }

                HStack(spacing: 24) {
                    rowStat(value: Format.miles(ride.distanceMeters), unit: "mi", label: "Distance")
                    rowStat(value: Format.duration(ride.durationSeconds), unit: nil, label: "Duration")
                    rowStat(value: Format.mph(ride.avgSpeed), unit: "mph", label: "Avg")
                }

                // Show the rider's star rating if present.
                if let rating = ride.rating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundStyle(star <= rating ? Color.bsPrimary : Color.bsWhite.opacity(0.3))
                        }
                    }
                }
            }
        }
    }

    // A compact monospaced stat for the row (smaller than the full StatTile).
    private func rowStat(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.bsStatMedium)
                    .foregroundStyle(Color.bsWhite)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.bsWhite.opacity(0.5))
                }
            }
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.bsWhite.opacity(0.5))
        }
    }
}

// MARK: - Safety score badge

/// A small pill showing 0–100 safety score, colored by band (data viz only,
/// paired with the number + a shield icon so it's never color-only).
struct SafetyScoreBadge: View {
    let score: Int?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .bold))
            Text(score.map(String.init) ?? "—")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(Color.bsBlack)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color)
        .clipShape(Capsule())
        .accessibilityLabel(score.map { "Safety score \($0)" } ?? "No safety score")
    }

    // Band the score into the semantic colors (data viz).
    private var color: Color {
        guard let score else { return .bsWhite.opacity(0.3) }
        switch score {
        case 80...:  return .bsGood
        case 60..<80: return .bsModerate
        default:      return .bsSevere
        }
    }
}

#Preview {
    RideListView()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
