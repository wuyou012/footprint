import SwiftUI

struct RecordSettingsView: View {
    @Binding var selectedProfile: RecordingProfile
    @Binding var mapStyle: FootprintMapStyle
    @Binding var mapDimension: FootprintMapDimension
    @Binding var poiVisibility: FootprintPOIVisibility
    @Binding var mapTintColor: RGBColor
    @Binding var mapTintStrength: Double
    @Binding var trackColor: RGBColor

    let recording: Bool
    let backgroundRecordingEnabled: Bool
    let canExport: Bool
    let exporting: Bool
    let exportError: String?
    let onBack: () -> Void
    let onExport: () -> Void

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

                    if recording {
                        LabeledContent("Status", value: backgroundRecordingEnabled ? "Background enabled" : "Recording")
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
