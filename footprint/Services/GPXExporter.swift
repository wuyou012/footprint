import Foundation

enum GPXExporter {
    static func write(points: [TrackPoint]) throws -> URL {
        let validPoints = points.filter { isValid($0) }
        guard !validPoints.isEmpty else {
            throw NSError(domain: "footprint.gpx", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid track points to export"])
        }
        let fileName = fileName(for: validPoints)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent(fileName)
        try gpx(points: validPoints).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func write(dayKey: String) throws -> URL {
        try write(
            fileName: "footprint-\(dayKey).gpx",
            name: "footprint \(dayKey)",
            enumerate: { body in
                try TrackDatabase.shared.forEachTrackPoint(for: dayKey, body: body)
            }
        )
    }

    static func write(sessionID: Int64) throws -> URL {
        try write(
            fileName: "footprint-session-\(sessionID).gpx",
            name: "footprint session \(sessionID)",
            enumerate: { body in
                try TrackDatabase.shared.forEachTrackPoint(forSessionID: sessionID, body: body)
            }
        )
    }

    private static func write(
        fileName: String,
        name rawName: String,
        enumerate: (_ body: (TrackPoint) throws -> Void) throws -> Void
    ) throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let createdAt = ISO8601DateFormatter().string(from: Date())
        let name = escape(rawName)
        try handle.writeText(header(name: name, createdAt: createdAt))

        var currentSegmentKey: String?
        var wrotePoint = false
        try enumerate { point in
            guard isValid(point) else { return }
            let segmentKey = point.segmentID.map { "segment-\($0)" } ?? "legacy"
            if currentSegmentKey != segmentKey {
                if currentSegmentKey != nil {
                    try handle.writeText("    </trkseg>\n")
                }
                try handle.writeText("    <trkseg>\n")
                currentSegmentKey = segmentKey
            }
            try handle.writeText("\(trackPointXML(point))\n")
            wrotePoint = true
        }

        if currentSegmentKey != nil {
            try handle.writeText("    </trkseg>\n")
        }
        try handle.writeText(footer())

        guard wrotePoint else {
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: "footprint.gpx", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid track points to export"])
        }
        return url
    }

    private static func isValid(_ point: TrackPoint) -> Bool {
        point.longitude.isFinite
            && point.latitude.isFinite
            && abs(point.longitude) <= 180
            && abs(point.latitude) <= 90
            && point.timestampMs > 0
    }

    private static func fileName(for points: [TrackPoint]) -> String {
        let firstDate = points.first?.date ?? Date()
        let stamp = ISO8601DateFormatter().string(from: firstDate)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "footprint-\(stamp).gpx"
    }

    private static func gpx(points: [TrackPoint]) -> String {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let name = escape("footprint \(createdAt)")
        let segments = groupedSegments(points)
            .map { segment in
                [
                    "    <trkseg>",
                    segment.map { trackPointXML($0) }.joined(separator: "\n"),
                    "    </trkseg>"
                ].joined(separator: "\n")
            }
            .joined(separator: "\n")

        return [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx",
            "  version=\"1.1\"",
            "  creator=\"footprint\"",
            "  xmlns=\"http://www.topografix.com/GPX/1/1\"",
            "  xmlns:footprint=\"https://github.com/wuyou012/footprint/gpx/1\"",
            "  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"",
            "  xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\"",
            ">",
            "  <metadata>",
            "    <name>\(name)</name>",
            "    <time>\(createdAt)</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(name)</name>",
            segments,
            "  </trk>",
            "</gpx>",
            ""
        ].joined(separator: "\n")
    }

    private static func header(name: String, createdAt: String) -> String {
        [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx",
            "  version=\"1.1\"",
            "  creator=\"footprint\"",
            "  xmlns=\"http://www.topografix.com/GPX/1/1\"",
            "  xmlns:footprint=\"https://github.com/wuyou012/footprint/gpx/1\"",
            "  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"",
            "  xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\"",
            ">",
            "  <metadata>",
            "    <name>\(name)</name>",
            "    <time>\(createdAt)</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(name)</name>",
            ""
        ].joined(separator: "\n")
    }

    private static func footer() -> String {
        [
            "  </trk>",
            "</gpx>",
            ""
        ].joined(separator: "\n")
    }

    private static func groupedSegments(_ points: [TrackPoint]) -> [[TrackPoint]] {
        var groups: [[TrackPoint]] = []
        var index: [String: Int] = [:]
        for point in points {
            let key = point.segmentID.map { "segment-\($0)" } ?? "legacy"
            if let groupIndex = index[key] {
                groups[groupIndex].append(point)
            } else {
                index[key] = groups.count
                groups.append([point])
            }
        }
        return groups
    }

    private static func trackPointXML(_ point: TrackPoint) -> String {
        let lat = String(format: "%.7f", point.latitude)
        let lon = String(format: "%.7f", point.longitude)
        let time = ISO8601DateFormatter().string(from: point.date)
        let ele = point.altitude.map { "\n        <ele>\(String(format: "%.2f", $0))</ele>" } ?? ""
        let extensions = pointExtensions(point)
        return "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\">\(ele)\n        <time>\(time)</time>\(extensions)\n      </trkpt>"
    }

    private static func pointExtensions(_ point: TrackPoint) -> String {
        var fields: [String] = []
        if let sessionID = point.sessionID {
            fields.append("          <footprint:sessionId>\(sessionID)</footprint:sessionId>")
        }
        if let segmentID = point.segmentID {
            fields.append("          <footprint:segmentId>\(segmentID)</footprint:segmentId>")
        }
        if let profile = point.profile?.rawValue {
            fields.append("          <footprint:profile>\(escape(profile))</footprint:profile>")
        }
        if let source = point.source {
            fields.append("          <footprint:source>\(escape(source))</footprint:source>")
        }
        if let localDayKey = point.localDayKey {
            fields.append("          <footprint:localDayKey>\(escape(localDayKey))</footprint:localDayKey>")
        }
        if let accuracy = point.accuracy {
            fields.append("          <footprint:accuracyMeters>\(String(format: "%.2f", accuracy))</footprint:accuracyMeters>")
        }
        guard !fields.isEmpty else { return "" }
        return "\n        <extensions>\n\(fields.joined(separator: "\n"))\n        </extensions>"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private extension FileHandle {
    func writeText(_ value: String) throws {
        if let data = value.data(using: .utf8) {
            try write(contentsOf: data)
        }
    }
}
