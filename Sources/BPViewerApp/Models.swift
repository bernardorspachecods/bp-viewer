import BPViewerCore
import SwiftUI

enum AppThemePreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

extension PreviewStatus {
    var label: String {
        switch self {
        case .idle: "Sem preview"
        case .updating: "A atualizar"
        case .ready: "Atualizado"
        case .stale: "Desatualizado"
        case .failed: "Erro"
        case .unavailable: "Indisponível"
        case .cancelled: "Cancelado"
        case .timeout: "Timeout"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "circle.dashed"
        case .updating: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .stale: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .unavailable: "questionmark.circle.fill"
        case .cancelled: "pause.circle.fill"
        case .timeout: "clock.badge.exclamationmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle, .unavailable: BPTokens.Color.muted
        case .updating: .accentColor
        case .ready: BPTokens.Color.success
        case .stale, .timeout: BPTokens.Color.warning
        case .failed: BPTokens.Color.danger
        case .cancelled: BPTokens.Color.muted
        }
    }
}

extension MarkdownSaveState {
    var label: String {
        switch self {
        case .saved: "Guardado"
        case .unsaved: "Alterações por guardar"
        case .saving: "A guardar…"
        case .conflict: "Conflito externo"
        case .failed: "Não guardado"
        }
    }
}

struct PendingCloseRequest: Identifiable {
    let id: String
    let tabID: String
    let title: String
}
