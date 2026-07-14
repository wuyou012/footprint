import Foundation
import os

/// F002 常驻记录诊断日志。
/// - 连 Xcode：console 过滤 subsystem `com.footprint.f002` 实时看。
/// - 不连 Xcode（带手机行走）：同时写入 app 沙盒文件，回来后在设置页「导出诊断日志」分享给我评估。
enum FootprintLog {
    static let persistent = Logger(subsystem: "com.footprint.f002", category: "persistent")

    /// 同时输出到系统统一日志和 app 沙盒文件。
    static func diag(_ message: String) {
        persistent.info("\(message, privacy: .public)")
        DiagnosticLogFile.shared.append(message)
    }
}

/// 持久化 F002 诊断日志到 app 沙盒，供无法连 Xcode 行走时离线记录、事后导出评估。
final class DiagnosticLogFile: @unchecked Sendable {
    static let shared = DiagnosticLogFile()

    private let queue = DispatchQueue(label: "com.footprint.f002.difflog")
    private let fileURL: URL
    private let formatter: DateFormatter

    var url: URL { fileURL }

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("f002-diagnostics.log")

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter = f
    }

    func append(_ message: String) {
        queue.async { [fileURL, formatter] in
            let line = "\(formatter.string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func clear() {
        queue.async { [fileURL] in
            try? Data().write(to: fileURL, options: .atomic)
        }
    }
}
