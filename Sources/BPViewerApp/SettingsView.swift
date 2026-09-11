import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Zoom predefinido") {
                ZoomPreferenceRow(
                    title: "Markdown",
                    value: Binding(
                        get: { model.defaultMarkdownZoom },
                        set: { model.setDefaultMarkdownZoom($0) }
                    )
                )
                ZoomPreferenceRow(
                    title: "LaTeX / PDF",
                    value: Binding(
                        get: { model.defaultLatexZoom },
                        set: { model.setDefaultLatexZoom($0) }
                    )
                )
            }

            Text("Aplica-se a documentos sem um zoom individual guardado.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .frame(minHeight: 180)
    }
}

private struct ZoomPreferenceRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 96, alignment: .leading)
            Spacer()
            HStack(spacing: 5) {
                ZoomValueControl(value: $value)
                Text("%")
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .leading)
            }
        }
    }
}

private struct ZoomValueControl: View {
    @Binding var value: Double
    @FocusState private var isFocused: Bool

    private var percentageValue: Binding<Double> {
        Binding(
            get: { value * 100 },
            set: { value = min(max($0 / 100, 0.7), 2.0) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            TextField(
                "",
                value: percentageValue,
                format: .number.precision(.fractionLength(0))
            )
            .focused($isFocused)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .padding(.leading, 7)
            .padding(.trailing, 3)
            .frame(width: 64, height: 24)
            .monospacedDigit()

            VStack(spacing: 0) {
                Button {
                    adjust(by: 0.1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 11)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Aumentar zoom")

                Button {
                    adjust(by: -0.1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 11)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Diminuir zoom")
            }
            .frame(width: 18, height: 24)
        }
        .frame(width: 82, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isFocused ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: isFocused ? 2 : 1
                )
        }
    }

    private func adjust(by amount: Double) {
        value = min(max(value + amount, 0.7), 2.0)
    }
}
