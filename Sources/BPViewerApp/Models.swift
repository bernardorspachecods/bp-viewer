import BPViewerCore
import SwiftUI

enum FindTarget: Equatable {
    case preview
    case source
}

enum AppThemePreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
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
        case .idle: "No Preview"
        case .updating: "Updating"
        case .ready: "Updated"
        case .stale: "Out of Date"
        case .failed: "Error"
        case .unavailable: "Unavailable"
        case .cancelled: "Cancelled"
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
        case .saved: "Saved"
        case .unsaved: "Unsaved Changes"
        case .saving: "Saving…"
        case .conflict: "External Conflict"
        case .failed: "Not Saved"
        }
    }
}

struct PendingCloseRequest: Identifiable {
    let id: String
    let tabID: String
    let title: String
    let closesTab: Bool
    let unsavedCount: Int
}

struct PendingFileMoveRequest: Identifiable {
    let id: String
    let sourceURLs: [URL]
    let destinationDirectory: URL

    var itemTitles: [String] {
        sourceURLs.map(\.lastPathComponent)
    }
}
