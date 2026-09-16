import AppKit
import BPViewerCore
import Foundation
@preconcurrency import PDFKit

struct DocumentRenderRequest: Sendable {
    let tabID: String
    let url: URL
    let kind: DocumentKind
    let projectRoot: URL?
    let markdownSourceOverride: String?
    let latexRootURL: URL?
    let latexShellEscapeMode: LatexShellEscapeMode
    let approvedLatexExternalPaths: [String: Set<String>]
    let force: Bool
}

struct DocumentPreviewOutput: Sendable {
    let kind: DocumentKind
    let html: String?
    let json: String?
    let pdfData: Data?
    let source: String?
    let baseURL: URL?
    let dependencies: [URL]
    let externalDependencies: [URL]
    let outline: [MarkdownOutlineEntry]
    let blocks: [MarkdownEditableBlock]
}

struct DocumentRenderFailure: Sendable {
    let status: PreviewStatus
    let message: String
    let latexRootSelectionCandidates: [LatexRootCandidate]?
    let latexRootURL: URL?
    let latexExternalDependencies: [LatexExternalDependency]?
    let projectRoot: URL?
}

enum DocumentRenderEvent {
    case started(tabID: String)
    case ready(tabID: String, output: DocumentPreviewOutput)
    case failed(tabID: String, failure: DocumentRenderFailure)
}

/// Owns preview work and its asynchronous lifecycle. The app remains the
/// owner of DocumentTab and applies these events to observable UI state.
@MainActor
final class DocumentRenderCoordinator {
    private let markdownAdapter: any MarkdownAdapter
    private let latexRenderCache: LatexRenderCache
    private let onEvent: (DocumentRenderEvent) -> Void
    private var tasks: [String: Task<Void, Never>] = [:]
    private var generations: [String: Int] = [:]

    init(
        markdownAdapter: any MarkdownAdapter = SwiftMarkdownAdapter(),
        latexRenderCache: LatexRenderCache = LatexRenderCache(),
        onEvent: @escaping (DocumentRenderEvent) -> Void
    ) {
        self.markdownAdapter = markdownAdapter
        self.latexRenderCache = latexRenderCache
        self.onEvent = onEvent
    }

    func render(_ request: DocumentRenderRequest) {
        guard request.kind == .markdown
                || request.kind == .json
                || request.kind == .latex
                || request.kind == .pdf else { return }

        tasks[request.tabID]?.cancel()
        let generation = (generations[request.tabID] ?? 0) + 1
        generations[request.tabID] = generation
        onEvent(.started(tabID: request.tabID))

        let markdownAdapter = markdownAdapter
        let latexRenderCache = latexRenderCache
        let task = Task { [weak self] in
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try Self.render(
                        request,
                        markdownAdapter: markdownAdapter,
                        latexRenderCache: latexRenderCache
                    )
                }.value

                guard let self,
                      self.generations[request.tabID] == generation else { return }
                self.tasks.removeValue(forKey: request.tabID)
                self.onEvent(.ready(tabID: request.tabID, output: output))
            } catch {
                guard let self,
                      self.generations[request.tabID] == generation,
                      !Task.isCancelled else { return }
                self.tasks.removeValue(forKey: request.tabID)
                self.onEvent(.failed(
                    tabID: request.tabID,
                    failure: Self.failure(for: error, request: request)
                ))
            }
        }
        tasks[request.tabID] = task
    }

    func cancel(tabIDs: some Sequence<String>) {
        for tabID in tabIDs {
            tasks[tabID]?.cancel()
            tasks.removeValue(forKey: tabID)
            generations[tabID, default: 0] += 1
        }
    }

    func cancelAll() {
        cancel(tabIDs: tasks.keys)
    }

    nonisolated private static func render(
        _ request: DocumentRenderRequest,
        markdownAdapter: any MarkdownAdapter,
        latexRenderCache: LatexRenderCache
    ) throws -> DocumentPreviewOutput {
        switch request.kind {
        case .markdown:
            let source = try request.markdownSourceOverride
                ?? String(contentsOf: request.url, encoding: .utf8)
            let result = try markdownAdapter.render(
                source: source,
                baseURL: request.url.deletingLastPathComponent()
            )
            return DocumentPreviewOutput(
                kind: .markdown,
                html: result.html,
                json: nil,
                pdfData: nil,
                source: source,
                baseURL: result.baseURL,
                dependencies: result.dependencies,
                externalDependencies: [],
                outline: result.outline,
                blocks: result.blocks
            )

        case .json:
            let source = try String(contentsOf: request.url, encoding: .utf8)
            return DocumentPreviewOutput(
                kind: .json,
                html: nil,
                json: try JSONPreviewAdapter().format(source: source),
                pdfData: nil,
                source: source,
                baseURL: nil,
                dependencies: [],
                externalDependencies: [],
                outline: [],
                blocks: []
            )

        case .pdf:
            let data = try Data(contentsOf: request.url)
            guard data.starts(with: Data("%PDF".utf8)), PDFDocument(data: data) != nil else {
                throw PDFPreviewError.invalidDocument
            }
            return DocumentPreviewOutput(
                kind: .pdf,
                html: nil,
                json: nil,
                pdfData: data,
                source: nil,
                baseURL: nil,
                dependencies: [],
                externalDependencies: [],
                outline: [],
                blocks: []
            )

        case .latex:
            guard let projectRoot = request.projectRoot else {
                throw DocumentRenderError.missingProjectRoot
            }
            let storedRootURL = request.latexRootURL
            let adapter = LocalLatexAdapter(shellEscapeMode: request.latexShellEscapeMode)
            let resolvedRootURL: URL
            if let storedRootURL {
                resolvedRootURL = storedRootURL
            } else {
                let resolution = try LatexRootDiscovery().resolve(
                    openedFile: request.url,
                    projectRoot: projectRoot
                )
                guard let selectedRoot = resolution.selectedRoot else {
                    throw LatexRenderError.rootSelectionRequired(resolution.candidates)
                }
                resolvedRootURL = selectedRoot
            }

            let externalDependencies = adapter.externalDependencies(
                rootURL: resolvedRootURL,
                projectRoot: projectRoot
            )
            let grantKey = latexExternalGrantKey(
                projectRoot: projectRoot,
                rootURL: resolvedRootURL
            )
            let unapprovedDependencies = externalDependencies.filter {
                !request.approvedLatexExternalPaths[grantKey, default: []].contains($0.url.path)
            }
            if !unapprovedDependencies.isEmpty {
                throw LatexRenderError.externalDependenciesRequireConfirmation(
                    resolvedRootURL,
                    unapprovedDependencies
                )
            }

            let cacheKey = LatexCacheKey(
                projectRoot: projectRoot,
                rootURL: resolvedRootURL,
                compilerIdentity: try adapter.compilerIdentity(
                    rootURL: resolvedRootURL,
                    projectRoot: projectRoot
                ),
                shellEscapeMode: request.latexShellEscapeMode
            )
            if !request.force, let cached = latexRenderCache.load(key: cacheKey) {
                return DocumentPreviewOutput(
                    kind: .latex,
                    html: nil,
                    json: nil,
                    pdfData: cached.pdfData,
                    source: nil,
                    baseURL: nil,
                    dependencies: cached.dependencies,
                    externalDependencies: cached.externalDependencies,
                    outline: [],
                    blocks: []
                )
            }

            let result = try adapter.render(rootURL: resolvedRootURL, projectRoot: projectRoot)
            try? latexRenderCache.store(key: cacheKey, result: result)
            return DocumentPreviewOutput(
                kind: .latex,
                html: nil,
                json: nil,
                pdfData: result.pdfData,
                source: nil,
                baseURL: nil,
                dependencies: result.dependencies,
                externalDependencies: result.externalDependencies,
                outline: [],
                blocks: []
            )

        case .docx, .other:
            throw DocumentRenderError.unsupportedKind
        }
    }

    nonisolated private static func failure(
        for error: Error,
        request: DocumentRenderRequest
    ) -> DocumentRenderFailure {
        if let latexError = error as? LatexRenderError {
            switch latexError {
            case let .rootSelectionRequired(candidates):
                return DocumentRenderFailure(
                    status: .failed,
                    message: error.localizedDescription,
                    latexRootSelectionCandidates: candidates,
                    latexRootURL: nil,
                    latexExternalDependencies: nil,
                    projectRoot: request.projectRoot
                )
            case let .externalDependenciesRequireConfirmation(rootURL, dependencies):
                return DocumentRenderFailure(
                    status: .failed,
                    message: error.localizedDescription,
                    latexRootSelectionCandidates: nil,
                    latexRootURL: rootURL,
                    latexExternalDependencies: dependencies,
                    projectRoot: request.projectRoot
                )
            default:
                return DocumentRenderFailure(
                    status: previewStatus(for: latexError),
                    message: error.localizedDescription,
                    latexRootSelectionCandidates: nil,
                    latexRootURL: nil,
                    latexExternalDependencies: nil,
                    projectRoot: request.projectRoot
                )
            }
        }

        return DocumentRenderFailure(
            status: .failed,
            message: error.localizedDescription,
            latexRootSelectionCandidates: nil,
            latexRootURL: nil,
            latexExternalDependencies: nil,
            projectRoot: request.projectRoot
        )
    }

    nonisolated private static func previewStatus(for error: LatexRenderError) -> PreviewStatus {
        switch error {
        case .toolUnavailable:
            return .unavailable
        case let .compilationFailed(result), let .outputPDFMissing(_, result):
            switch result.status {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            case .launchFailed: return .unavailable
            case .failed, .success: return .failed
            }
        default:
            return .failed
        }
    }

    nonisolated private static func latexExternalGrantKey(projectRoot: URL, rootURL: URL) -> String {
        "\(projectRoot.standardizedFileURL.path)\n\(rootURL.standardizedFileURL.path)"
    }
}

private enum PDFPreviewError: LocalizedError, Sendable {
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "O ficheiro não contém um PDF válido."
        }
    }
}

private enum DocumentRenderError: LocalizedError, Sendable {
    case missingProjectRoot
    case unsupportedKind

    var errorDescription: String? {
        switch self {
        case .missingProjectRoot:
            "Não existe um workspace LaTeX ativo."
        case .unsupportedKind:
            "Este tipo de documento não tem um renderer disponível."
        }
    }
}
