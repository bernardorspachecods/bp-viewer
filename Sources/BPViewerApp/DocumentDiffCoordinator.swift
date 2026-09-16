import BPViewerCore
import Foundation

/// Selects a document baseline without exposing filesystem or Git details to
/// the SwiftUI surfaces.
@MainActor
final class DocumentDiffCoordinator {
    private let diskProvider: any DocumentDiffBaselineProviding
    private let gitProvider: any DocumentDiffBaselineProviding

    init(
        diskProvider: any DocumentDiffBaselineProviding = DiskDocumentDiffBaselineProvider(),
        gitProvider: any DocumentDiffBaselineProviding = GitHeadDocumentDiffBaselineProvider()
    ) {
        self.diskProvider = diskProvider
        self.gitProvider = gitProvider
    }

    func baseline(
        for mode: DocumentDiffMode,
        url: URL
    ) -> DocumentDiffBaselineResolution {
        switch mode {
        case .savedOnDisk:
            diskProvider.baseline(for: url)
        case .gitHead:
            gitProvider.baseline(for: url)
        }
    }
}
