import SwiftUI

enum AppRoute: Equatable {
    case record
    case history
    case dayDetail(String)
}

struct ContentView: View {
    @StateObject private var recorder = RecordingManager()
    @State private var route: AppRoute = .record

    var body: some View {
        switch route {
        case .record:
            RecordView(
                recorder: recorder,
                onOpenHistory: { route = .history }
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
        }
    }
}

#Preview {
    ContentView()
}
