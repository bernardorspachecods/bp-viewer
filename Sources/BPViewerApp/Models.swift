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

enum DocumentKind: String, Hashable {
    case markdown
    case latex
    case other

    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "tex", "latex": self = .latex
        default: self = .other
        }
    }

    var label: String {
        switch self {
        case .markdown: "Markdown"
        case .latex: "LaTeX"
        case .other: "Não suportado"
        }
    }
}

enum PreviewStatus: Hashable {
    case idle
    case updating
    case ready
    case stale
    case failed
    case unavailable
    case cancelled
    case timeout

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

struct FileNode: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let relativePath: String
    let isDirectory: Bool
    let kind: DocumentKind
    var children: [FileNode]

    var title: String { url.lastPathComponent }
}

struct DocumentTab: Identifiable, Hashable {
    let id: String
    let url: URL
    let kind: DocumentKind
    var status: PreviewStatus = .idle
    var isStale: Bool = false
    var previewHTML: String?
    var previewBaseURL: URL?
    var errorMessage: String?

    var title: String { url.deletingPathExtension().lastPathComponent }
    var subtitle: String { url.deletingLastPathComponent().lastPathComponent }
}
