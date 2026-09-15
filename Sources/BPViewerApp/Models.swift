import BPViewerCore
import Foundation
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

struct MarkdownReadingPosition: Codable, Hashable {
    let scrollY: Double
    let anchorID: String?
    let anchorOffset: Double
}

struct PDFReadingPosition: Codable, Hashable {
    let pageIndex: Int
    let x: Double?
    let y: Double?
}

enum MarkdownEditingMode: String, Hashable {
    case visual
    case markdown
}

enum MarkdownSaveState: String, Hashable {
    case saved
    case unsaved
    case saving
    case conflict
    case failed

    var label: String {
        switch self {
        case .saved: "Guardado"
        case .unsaved: "Alterações por guardar"
        case .saving: "A guardar…"
        case .conflict: "Conflito externo"
        case .failed: "Erro ao guardar"
        }
    }
}

struct MarkdownConflict: Hashable {
    let localSource: String
    let externalSource: String
    let blockIDs: [String]
}

struct MarkdownEditSession: Hashable {
    var mode: MarkdownEditingMode = .visual
    var isEditing = true
    var baseSource: String
    var currentSource: String
    var saveState: MarkdownSaveState = .saved
    var undoSources: [String] = []
    var redoSources: [String] = []
    var conflict: MarkdownConflict?
}

struct DocumentTab: Identifiable, Hashable {
    let id: String
    let url: URL
    let kind: DocumentKind
    var contextURL: URL?
    var status: PreviewStatus = .idle
    var isStale: Bool = false
    var previewHTML: String?
    var previewPDFData: Data?
    var markdownOutline: [MarkdownOutlineEntry] = []
    var isOutlineVisible = false
    var previewZoom: Double = 1.0
    var isPreviewZoomCustomized = false
    var previewPageIndex: Int = 0
    var markdownReadingPosition: MarkdownReadingPosition?
    var pdfReadingPosition: PDFReadingPosition?
    var previewUpdatedAt: Date?
    var previewBaseURL: URL?
    var previewDependencies: [URL] = []
    var previewExternalDependencies: [URL] = []
    var errorMessage: String?
    var markdownSource: String?
    var markdownBlocks: [MarkdownEditableBlock] = []
    var markdownEditSession: MarkdownEditSession?

    var title: String { url.deletingPathExtension().lastPathComponent }
    var subtitle: String {
        contextURL?.path ?? url.deletingLastPathComponent().lastPathComponent
    }
}
