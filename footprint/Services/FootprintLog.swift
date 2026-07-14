import os

/// F002 常驻记录诊断日志。
/// 真机调试：Xcode console（或 Console.app）过滤 subsystem `com.footprint.f002`
/// 或搜 "F002" 即可看到 CMMotion 决策 / 采集开关 / 记点。
enum FootprintLog {
    static let persistent = Logger(subsystem: "com.footprint.f002", category: "persistent")
}
