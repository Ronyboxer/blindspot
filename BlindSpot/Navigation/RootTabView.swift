//
//  RootTabView.swift
//  Blind Spot
//
//  The root navigation: a four-tab bar — Map, Record, Rides, Profile.
//  Tab bar chrome is themed to the dark instrument-panel look.
//

import SwiftUI
import UIKit   // for UITabBarAppearance / UIColor theming below

struct RootTabView: View {

    init() {
        // Theme the UITabBar to charcoal with yellow selection. SwiftUI's TabView
        // still relies on UIKit appearance for full control of these colors.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.bsCharcoal)

        // Selected = brand yellow; unselected = muted off-white.
        let selected = UIColor(Color.bsPrimary)
        let unselected = UIColor(Color.bsWhite.opacity(0.5))

        appearance.stackedLayoutAppearance.selected.iconColor = selected
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selected]
        appearance.stackedLayoutAppearance.normal.iconColor = unselected
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselected]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }

            RecordRideView()
                .tabItem { Label("Record", systemImage: "record.circle") }

            RideListView()
                .tabItem { Label("Rides", systemImage: "list.bullet.rectangle.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(.bsPrimary)
    }
}

#Preview {
    RootTabView()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
