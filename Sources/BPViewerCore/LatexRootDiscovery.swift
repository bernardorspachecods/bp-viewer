import Foundation

public struct LatexRootCandidate: Equatable, Sendable {
    public let url: URL
    public let reasons: [String]

    public init(url: URL, reasons: [String]) {
        self.url = url.standardizedFileURL
        self.reasons = reasons
    }
}

public struct LatexRootResolution: Equatable, Sendable {
    public let candidates: [LatexRootCandidate]
    public let selectedRoot: URL?

    public init(candidates: [LatexRootCandidate], selectedRoot: URL?) {
        self.candidates = candidates
        self.selectedRoot = selectedRoot?.standardizedFileURL
    }

    public var requiresSelection: Bool {
        selectedRoot == nil
    }
}

public enum LatexRootDiscoveryError: LocalizedError, Sendable {
    case projectRootIsNotDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case let .projectRootIsNotDirectory(url):
            "A pasta do projeto LaTeX não existe ou não é uma pasta: \(url.path)"
        }
    }
}

/// Finds complete LaTeX documents without compiling them.
///
/// A root is currently identified by the structural markers that make it a
/// complete document. Selection is automatic only when exactly one candidate
/// exists; callers must ask the user when there are zero or multiple roots.
public struct LatexRootDiscovery: Sendable {
    public init() {}

    public func resolve(openedFile: URL, projectRoot: URL) throws -> LatexRootResolution {
        let root = projectRoot.standardizedFileURL
        guard isDirectory(root) else {
            throw LatexRootDiscoveryError.projectRootIsNotDirectory(root)
        }

        let candidates = candidateFiles(openedFile: openedFile, projectRoot: root).compactMap { url -> LatexRootCandidate? in
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }

            var reasons: [String] = []
            if source.range(of: #"\\documentclass(?:\[[^\]]*\])?\s*\{"#, options: .regularExpression) != nil {
                reasons.append("documentclass")
            }
            if source.range(of: #"\\begin\s*\{\s*document\s*\}"#, options: .regularExpression) != nil {
                reasons.append("begin{document}")
            }
            guard !reasons.isEmpty else { return nil }
            return LatexRootCandidate(url: url, reasons: reasons)
        }
        .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }

        let selectedRoot: URL?
        if candidates.count == 1 {
            selectedRoot = candidates[0].url
        } else {
            selectedRoot = nil
        }

        return LatexRootResolution(candidates: candidates, selectedRoot: selectedRoot)
    }

    private func candidateFiles(openedFile: URL, projectRoot: URL) -> [URL] {
        let opened = openedFile.standardizedFileURL
        var directory = opened.deletingLastPathComponent()
        var candidates = Set<URL>()

        while isInside(directory, project: projectRoot) {
            candidates.formUnion(texFiles(in: directory))
            if directory == projectRoot { break }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }

        return candidates.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func texFiles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "tex",
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
                return nil
            }
            return url.standardizedFileURL
        }
    }

    private func isInside(_ url: URL, project: URL) -> Bool {
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let projectPath = project.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == projectPath || candidatePath.hasPrefix(projectPath + "/")
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
