//
//  footprintApp.swift
//  footprint
//
//  Created by wuyou on 3/7/2026.
//

import SwiftUI

@main
struct footprintApp: App {
    init() {
        #if DEBUG
        do {
            try TrackDatabase.shared.seedRegionAchievementDemoTrackPoints()
        } catch {
            assertionFailure("Failed to seed region achievement demo track points: \(error)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
