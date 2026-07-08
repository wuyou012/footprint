import SwiftUI

enum AppRoute: Equatable {
    case record
    case history
    case dayDetail(String)
    case achievements
}

struct ContentView: View {
    @StateObject private var recorder = RecordingManager()
    @State private var route: AppRoute = .record

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
        }
    }
}

#Preview {
    ContentView()
}
