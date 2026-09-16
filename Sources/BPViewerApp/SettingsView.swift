import BPViewerCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ZoomSettingsView()
                .tabItem {
                    Label("Zoom", systemImage: "textformat.size")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            LatexSettingsView()
                .tabItem {
                    Label("LaTeX", systemImage: "doc.text")
                }
        }
        .frame(width: 460)
        .frame(minHeight: 340)
    }
}

private struct ZoomSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Default Zoom") {
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

            Text("Applies to documents without an individually saved zoom level.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("General") {
                ShortcutRow(title: "Open Folder", shortcut: "⌘O")
                ShortcutRow(title: "Open Settings", shortcut: "⌘,")
            }

            Section("Markdown Editing") {
                ShortcutRow(title: "Bold", shortcut: "⌘B")
                ShortcutRow(title: "Italic", shortcut: "⌘I")
                ShortcutRow(title: "Inline Code", shortcut: "⌘K")
            }

            Section("View") {
                ShortcutRow(title: "Refresh Preview", shortcut: "⌘R")
                ShortcutRow(title: "Find in Preview", shortcut: "⌘F")
                ShortcutRow(title: "Zoom In", shortcut: "⌘+")
                ShortcutRow(title: "Zoom Out", shortcut: "⌘−")
                ShortcutRow(title: "Reset Zoom", shortcut: "⌘0")
                ShortcutRow(title: "Toggle Sidebar", shortcut: "⌥⌘B")
                ShortcutRow(title: "Toggle Theme", shortcut: "⌥⌘T")
            }

            Section("Tabs") {
                ShortcutRow(title: "Close Tab", shortcut: "⌘W")
                ShortcutRow(title: "Next Tab", shortcut: "⌃Tab")
                ShortcutRow(title: "Select Tab", shortcut: "⌘1–⌘9")
            }

            Section("Snapshots") {
                ShortcutRow(title: "Close Floating Window", shortcut: "⌘W")
                ShortcutRow(title: "Cancel Selection", shortcut: "Esc")
            }

            Text("Shortcuts are defined by the app and cannot be edited in this version.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { model.theme },
                        set: { model.setTheme($0) }
                    )
                ) {
                    ForEach(AppThemePreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Text("You can also quickly toggle the theme with ⌥⌘T.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct LatexSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Compilation") {
                Picker(
                    "Shell escape",
                    selection: Binding(
                        get: { model.latexShellEscapeMode },
                        set: { model.setLatexShellEscapeMode($0) }
                    )
                ) {
                    ForEach(LatexShellEscapeMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Label(
                "Shell escape can allow the LaTeX process to run external commands. Enable it only for documents you trust.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
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
                .accessibilityLabel("Zoom In")

                Button {
                    adjust(by: -0.1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 11)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Zoom Out")
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
