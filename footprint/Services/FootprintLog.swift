import Foundation
import os

/// F002 常驻记录诊断日志。
/// - 连 Xcode：console 过滤 subsystem `com.footprint.f002`（调试器 attached 时 .private 明细仍可见）。
/// - 不连 Xcode（带手机行走）：写入 app 沙盒文件（完整明细），设置页「导出诊断日志」分享评估。
///
/// 隐私边界（review P1）：精确坐标**不进** public 统一日志（可能被系统/其他工具收集）——
/// 统一日志用 `.private` redact；完整坐标只留 app 沙盒文件 + 用户主动导出。
enum FootprintLog {
    static let persistent = Logger(subsystem: "com.footprint.f002", category: "persistent")

    static func diag(_ message: String) {
        // .private：非调试环境对明细(含坐标)做 redact；仅 Xcode attached 调试时可见。
        persistent.info("\(message, privacy: .private)")
        DiagnosticLogFile.shared.append(message)
    }
}

/// 持久化 F002 诊断日志到 app 沙盒，供无法连 Xcode 行走时离线记录、事后导出评估。
/// 带大小上限轮转（review P2），避免常驻长期运行文件无限增长。
final class DiagnosticLogFile: @unchecked Sendable {
    static let shared = DiagnosticLogFile()

    private let queue = DispatchQueue(label: "com.footprint.f002.difflog")
    private let fileURL: URL
    private let formatter: DateFormatter
    private let maxBytes = 1_000_000   // 超过 ~1MB 触发轮转
    private let keepBytes = 500_000    // 轮转时保留最近 ~512KB

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
        queue.async { [self] in
            rotateIfNeeded()
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

    /// 文件超过上限时保留最近部分，防止常驻长期运行无限增长。
    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > maxBytes,
              let data = try? Data(contentsOf: fileURL) else { return }
        let trimmed = Data(data.suffix(keepBytes))
        try? trimmed.write(to: fileURL, options: .atomic)
    }
}
