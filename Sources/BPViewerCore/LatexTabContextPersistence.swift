import Foundation

/// Keeps a LaTeX chapter context separate from the persisted root tab path.
/// A context is restored only while it remains a real file inside the project.
public enum LatexTabContextPersistence {
    public static func store(
        contextURL: URL,
        forTabID tabID: String,
        in paths: inout [String: String]
    ) {
        paths[tabID] = contextURL.standardizedFileURL.path
    }

    public static func restore(
        forTabID tabID: String,
        tabURL: URL,
        kind: DocumentKind,
        from paths: [String: String],
        projectRoot: URL
    ) -> URL? {
        guard kind == .latex, let contextPath = paths[tabID] else { return nil }

        let contextURL = URL(fileURLWithPath: contextPath).standardizedFileURL
        guard isRegularFile(contextURL),
              contextURL != tabURL.standardizedFileURL,
              isInside(contextURL, project: projectRoot) else {
            return nil
        }
        return contextURL
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        return values?.isRegularFile == true && values?.isDirectory != true
    }

    private static func isInside(_ url: URL, project: URL) -> Bool {
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let projectPath = project.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == projectPath || candidatePath.hasPrefix(projectPath + "/")
    }
}
