import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct RGBColor: Equatable {
    var red: Int
    var green: Int
    var blue: Int

    init(red: Int, green: Int, blue: Int) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    init(color: Color, fallback: RGBColor) {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(
                red: Int((red * 255).rounded()),
                green: Int((green * 255).rounded()),
                blue: Int((blue * 255).rounded())
            )
        } else {
            self = fallback
        }
        #else
        self = fallback
        #endif
    }

    var color: Color {
        Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }

    static let defaultTrack = RGBColor(red: 0, green: 158, blue: 184)
    static let defaultMapTint = RGBColor(red: 84, green: 132, blue: 255)
    static let defaultPhotoMarker = RGBColor(red: 255, green: 62, blue: 128)

    private static func clamp(_ value: Int) -> Int {
        min(255, max(0, value))
    }
}

struct RGBColorEditor: View {
    let title: String
    @Binding var rgb: RGBColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ColorPicker(selection: colorBinding, supportsOpacity: false) {
                Text(title)
            }

            HStack(spacing: 10) {
                RGBChannelField(label: "R", value: channel(\.red))
                RGBChannelField(label: "G", value: channel(\.green))
                RGBChannelField(label: "B", value: channel(\.blue))

                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rgb.color)
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { rgb.color },
            set: { rgb = RGBColor(color: $0, fallback: rgb) }
        )
    }

    private func channel(_ keyPath: WritableKeyPath<RGBColor, Int>) -> Binding<Int> {
        Binding(
            get: { rgb[keyPath: keyPath] },
            set: { rgb[keyPath: keyPath] = min(255, max(0, $0)) }
        )
    }
}

private struct RGBChannelField: View {
    let label: String
    @Binding var value: Int

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(label, text: $text)
                .keyboardType(.numberPad)
                .font(.callout.monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 54)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onAppear { text = "\(value)" }
                .onChange(of: value) { _, newValue in
                    let nextText = "\(newValue)"
                    if text != nextText {
                        text = nextText
                    }
                }
                .onChange(of: text) { _, newText in
                    updateValue(from: newText)
                }
        }
    }

    private func updateValue(from rawText: String) {
        let digits = String(rawText.filter(\.isNumber).prefix(3))
        if digits != rawText {
            text = digits
            return
        }
        guard let intValue = Int(digits) else { return }
        let clamped = min(255, max(0, intValue))
        if clamped != intValue {
            text = "\(clamped)"
        }
        value = clamped
    }
}
