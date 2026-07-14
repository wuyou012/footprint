import SwiftUI

struct RecordSettingsView: View {
    @Binding var selectedProfile: RecordingProfile
    @Binding var persistentRecordingEnabled: Bool
    @Binding var mapStyle: FootprintMapStyle
    @Binding var mapDimension: FootprintMapDimension
    @Binding var poiVisibility: FootprintPOIVisibility
    @Binding var mapTintColor: RGBColor
    @Binding var mapTintStrength: Double
    @Binding var trackColor: RGBColor

    let recording: Bool
    let backgroundRecordingEnabled: Bool
    let persistentStatus: String
    let canExport: Bool
    let exporting: Bool
    let exportError: String?
    let onBack: () -> Void
    let onPersistentRecordingChanged: (Bool) -> Void
    let onExport: () -> Void
    let onExportDiagnostics: () -> Void
    let onClearDiagnostics: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Recording") {
                    Picker("Mode", selection: $selectedProfile) {
                        ForEach(RecordingProfile.allCases) { profile in
                            Text(profile.label)
                                .tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(recording)

                    Text(selectedProfile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { persistentRecordingEnabled },
                        set: { onPersistentRecordingChanged($0) }
                    )) {
                        Label("后台常驻记录", systemImage: "location.circle")
                    }
                    .disabled(recording && !persistentRecordingEnabled)

                    Text(persistentRecordingEnabled
                         ? "Persistent \(persistentStatus). Manual Start is disabled until this is turned off."
                         : "Records automatically in the background with Significant Location, Visit, and motion gating.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if recording {
                        LabeledContent("Status", value: backgroundRecordingEnabled ? "Background enabled" : "Recording")
                    } else if persistentRecordingEnabled {
                        LabeledContent("Status", value: persistentStatus)
                    } else {
                        LabeledContent("Background", value: backgroundRecordingEnabled ? "Ready" : "Needs Always Location")
                    }
                }

                Section("Map") {
                    Picker("Perspective", selection: $mapDimension) {
                        ForEach(FootprintMapDimension.allCases) { dimension in
                            Text(dimension.label)
                                .tag(dimension)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Place names", selection: $poiVisibility) {
                        ForEach(FootprintPOIVisibility.allCases) { visibility in
                            Text(visibility.label)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Color", selection: $mapStyle) {
                        ForEach(FootprintMapStyle.allCases) { style in
                            Label(style.label, systemImage: style.symbolName)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.inline)

                    RGBColorEditor(title: "Map tint", rgb: $mapTintColor)

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Tint strength", value: "\(Int((mapTintStrength * 100).rounded()))%")
                            .font(.subheadline)
                        Slider(value: $mapTintStrength, in: 0...0.60, step: 0.05)
                    }
                }

                Section("Track") {
                    RGBColorEditor(title: "Track color", rgb: $trackColor)
                }

                Section("Export") {
                    Button {
                        onExport()
                    } label: {
                        Label(exporting ? "Exporting..." : "Export GPX", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canExport || exporting)

                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("F002 诊断日志") {
                    Button {
                        onExportDiagnostics()
                    } label: {
                        Label("导出诊断日志", systemImage: "doc.text.magnifyingglass")
                    }
                    Button(role: .destructive) {
                        onClearDiagnostics()
                    } label: {
                        Label("清空诊断日志", systemImage: "trash")
                    }
                    Text("常驻记录诊断（CMMotion 决策 / 采集开关 / 记点）。行走后导出发我评估。测试前建议先清空。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
    }
}
