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
                    Label("Aparência", systemImage: "paintbrush")
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
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Geral") {
                ShortcutRow(title: "Abrir pasta", shortcut: "⌘O")
                ShortcutRow(title: "Abrir definições", shortcut: "⌘,")
            }

            Section("Visualização") {
                ShortcutRow(title: "Atualizar preview", shortcut: "⌘R")
                ShortcutRow(title: "Pesquisar no preview", shortcut: "⌘F")
                ShortcutRow(title: "Aumentar zoom", shortcut: "⌘+")
                ShortcutRow(title: "Diminuir zoom", shortcut: "⌘−")
                ShortcutRow(title: "Repor zoom", shortcut: "⌘0")
                ShortcutRow(title: "Alternar sidebar", shortcut: "⌥⌘B")
                ShortcutRow(title: "Alternar tema", shortcut: "⌥⌘T")
            }

            Section("Tabs") {
                ShortcutRow(title: "Fechar tab", shortcut: "⌘W")
                ShortcutRow(title: "Próxima tab", shortcut: "⌃Tab")
                ShortcutRow(title: "Selecionar tab", shortcut: "⌘1–⌘9")
            }

            Section("Snapshots") {
                ShortcutRow(title: "Fechar janela flutuante", shortcut: "⌘W")
                ShortcutRow(title: "Cancelar seleção", shortcut: "Esc")
            }

            Text("Os shortcuts são definidos pela app e não são editáveis nesta versão.")
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
            Section("Tema") {
                Picker(
                    "Tema",
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

            Text("Também podes alternar rapidamente o tema com ⌥⌘T.")
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
            Section("Compilação") {
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
                "Shell escape pode permitir que o processo LaTeX execute comandos externos. Ativa-o apenas para documentos em que confias.",
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
