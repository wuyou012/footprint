import SwiftUI

enum AppRoute: Equatable {
    case record
    case history
    case dayDetail(String)
    case achievements
    case achievementMap
}

struct ContentView: View {
    @StateObject private var recorder = RecordingManager()
    @State private var route: AppRoute

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let initialRoute: AppRoute
        if arguments.contains("--region-achievement-map-demo") {
            initialRoute = .achievementMap
        } else if arguments.contains("--region-achievement-demo") {
            initialRoute = .achievements
        } else {
            initialRoute = .record
        }
        #else
        let initialRoute: AppRoute = .record
        #endif
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        switch route {
        case .record:
            RecordView(
                recorder: recorder,
                onOpenHistory: { route = .history },
                onOpenAchievements: { route = .achievements }
            )
        case .history:
            HistoryView(
                onBack: { route = .record },
                onSelectDay: { dayKey in route = .dayDetail(dayKey) }
            )
        case .dayDetail(let dayKey):
            DayDetailView(
                dayKey: dayKey,
                onBack: { route = .history },
                onDeleted: {
                    Task {
                        await recorder.reload()
                        route = .history
                    }
                }
            )
        case .achievements:
            RegionAchievementsView(
                onBack: { route = .record }
            )
        case .achievementMap:
            NavigationStack {
                RegionAchievementMapView()
            }
        }
    }
}

#Preview {
    ContentView()
}
