import Foundation

public enum DocumentOpenResult: Sendable, Equatable {
    case external(URL)
    case preview(documentURL: URL, kind: DocumentKind, contextURL: URL?)
}

/// Resolves document URLs and LaTeX context without performing UI actions.
public struct DocumentOpenCoordinator: Sendable {
    public init() {}

    public func resolve(
        _ url: URL,
        workspaceRoot: URL?,
        storedLatexRoot: URL? = nil
    ) -> DocumentOpenResult? {
        let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else { return nil }

        let kind = DocumentKind(url: standardizedURL)
        guard isPreviewable(kind) else { return .external(standardizedURL) }

        var documentURL = standardizedURL
        var contextURL: URL?
        if kind == .latex,
           let workspaceRoot,
           let selectedRoot = storedLatexRoot
               ?? (try? LatexRootDiscovery().resolve(
                   openedFile: standardizedURL,
                   projectRoot: workspaceRoot
               ))?.selectedRoot {
            documentURL = selectedRoot.standardizedFileURL
            contextURL = documentURL == standardizedURL ? nil : standardizedURL
        }

        return .preview(documentURL: documentURL, kind: kind, contextURL: contextURL)
    }

    public func inferredLatexProjectRoot(for fileURL: URL) -> URL {
        var directory = fileURL.deletingLastPathComponent().standardizedFileURL
        while directory.path != "/" {
            if let resolution = try? LatexRootDiscovery().resolve(
                openedFile: fileURL,
                projectRoot: directory
            ), !resolution.candidates.isEmpty {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return fileURL.deletingLastPathComponent().standardizedFileURL
    }

    public func isPreviewable(_ kind: DocumentKind) -> Bool {
        switch kind {
        case .markdown, .latex, .json, .docx, .pdf: true
        case .other: false
        }
    }
}
