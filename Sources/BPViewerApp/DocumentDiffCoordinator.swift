import BPViewerCore
import Foundation

/// Selects a document baseline without exposing filesystem or Git details to
/// the SwiftUI surfaces.
@MainActor
final class DocumentDiffCoordinator {
    private let diskProvider: any DocumentDiffBaselineProviding
    private let gitProvider: any DocumentDiffBaselineProviding
    private let gitRestorer: GitHeadDocumentRestorer

    init(
        diskProvider: any DocumentDiffBaselineProviding = DiskDocumentDiffBaselineProvider(),
        gitProvider: any DocumentDiffBaselineProviding = GitHeadDocumentDiffBaselineProvider(),
        gitRestorer: GitHeadDocumentRestorer = GitHeadDocumentRestorer()
    ) {
        self.diskProvider = diskProvider
        self.gitProvider = gitProvider
        self.gitRestorer = gitRestorer
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

    func restoreGitChanges(for url: URL) async -> GitDocumentRestoreResolution {
        let gitRestorer = self.gitRestorer
        return await Task.detached(priority: .userInitiated) {
            gitRestorer.restoreToHead(for: url)
        }.value
    }
}
