import Foundation

enum AppFormatters {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let weekdayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    static func localDayKey(for timestampMs: Int64 = nowMs()) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 1970
        let month = String(format: "%02d", parts.month ?? 1)
        let day = String(format: "%02d", parts.day ?? 1)
        return "\(year)-\(month)-\(day)"
    }

    static func timezoneOffsetMinutes(for timestampMs: Int64 = nowMs()) -> Int {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        return TimeZone.current.secondsFromGMT(for: date) / 60
    }

    static func formatDayKey(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return dayKey }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return dayKey }
        return weekdayDayFormatter.string(from: date)
    }

    static func formatClock(_ timestampMs: Int64?) -> String {
        guard let timestampMs else { return "never" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        return clockFormatter.string(from: date)
    }

    static func formatClockRange(start: Int64?, end: Int64?) -> String {
        "\(start.map { formatClock($0) } ?? "unknown") - \(end.map { formatClock($0) } ?? "ongoing")"
    }

    static func formatDistance(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "0 m" }
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.2f km", meters / 1000)
    }

    static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formatAccuracy(_ accuracy: Double?) -> String {
        guard let accuracy, accuracy.isFinite else { return "n/a" }
        return "\(Int(accuracy.rounded()))m"
    }

    static func formatRelativeTime(_ timestampMs: Int64?) -> String {
        guard let timestampMs else { return "never" }
        let delta = max(0, nowMs() - timestampMs)
        if delta < 1_000 { return "just now" }
        let seconds = delta / 1000
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    static func errorMessage(_ error: Error) -> String {
        (error as NSError).localizedDescription
    }
}
