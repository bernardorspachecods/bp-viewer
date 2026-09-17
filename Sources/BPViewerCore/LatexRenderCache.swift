import Foundation

public struct LatexCacheKey: Codable, Hashable, Sendable {
    public let projectRootPath: String
    public let rootPath: String
    public let compilerIdentity: String
    public let shellEscapeMode: LatexShellEscapeMode

    public init(
        projectRoot: URL,
        rootURL: URL,
        compilerIdentity: String,
        shellEscapeMode: LatexShellEscapeMode
    ) {
        projectRootPath = projectRoot.resolvingSymlinksInPath().standardizedFileURL.path
        rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        self.compilerIdentity = compilerIdentity
        self.shellEscapeMode = shellEscapeMode
    }

    fileprivate var stableValue: String {
        [projectRootPath, rootPath, compilerIdentity, shellEscapeMode.rawValue]
            .joined(separator: "\u{1f}")
    }
}

public struct CachedLatexPreview: Sendable {
    public let pdfData: Data
    public let rootURL: URL
    public let dependencies: [URL]
    public let externalDependencies: [URL]
    public let createdAt: Date
    public let syncTeXData: Data?
    public let generatedBibliographySource: String?

    public init(
        pdfData: Data,
        rootURL: URL,
        dependencies: [URL],
        externalDependencies: [URL],
        createdAt: Date,
        syncTeXData: Data? = nil,
        generatedBibliographySource: String? = nil
    ) {
        self.pdfData = pdfData
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.dependencies = dependencies.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.externalDependencies = externalDependencies.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.createdAt = createdAt
        self.syncTeXData = syncTeXData
        self.generatedBibliographySource = generatedBibliographySource
    }
}

public struct LatexRenderCache: Sendable {
    private static let currentCacheVersion = 3
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    public func load(key: LatexCacheKey) -> CachedLatexPreview? {
        let fileURL = entryURL(for: key)
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
              entry.version == Self.currentCacheVersion,
              entry.key == key.stableValue,
              let pdfData = Data(base64Encoded: entry.pdfBase64),
              !pdfData.isEmpty,
              pdfData.starts(with: Data("%PDF".utf8)),
              entry.dependencies.allSatisfy(isCurrent) else {
            return nil
        }

        return CachedLatexPreview(
            pdfData: pdfData,
            rootURL: URL(fileURLWithPath: entry.rootPath),
            dependencies: entry.dependencies.map { URL(fileURLWithPath: $0.path) },
            externalDependencies: entry.externalDependencies.map { URL(fileURLWithPath: $0.path) },
            createdAt: entry.createdAt,
            syncTeXData: entry.syncTeXData.flatMap { Data(base64Encoded: $0) },
            generatedBibliographySource: entry.generatedBibliographySource
        )
    }

    public func store(key: LatexCacheKey, result: LatexRenderResult) throws {
        guard result.processResult.status == .success,
              result.pdfData.starts(with: Data("%PDF".utf8)) else { return }

        let dependencyURLs = Set(result.dependencies + result.externalDependencies)
            .map(\.standardizedFileURL)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let fingerprints = dependencyURLs.compactMap(CacheDependency.init(url:))
        guard fingerprints.count == dependencyURLs.count else { return }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = CacheEntry(
            version: Self.currentCacheVersion,
            key: key.stableValue,
            rootPath: result.rootURL.resolvingSymlinksInPath().standardizedFileURL.path,
            dependencies: fingerprints,
            externalDependencies: result.externalDependencies.map { CachePath(path: $0.standardizedFileURL.path) },
            pdfBase64: result.pdfData.base64EncodedString(),
            syncTeXData: result.syncTeXData?.base64EncodedString(),
            generatedBibliographySource: result.generatedBibliographySource,
            createdAt: Date()
        )
        let data = try JSONEncoder().encode(entry)
        try data.write(to: entryURL(for: key), options: .atomic)
    }

    public func remove(key: LatexCacheKey) {
        try? FileManager.default.removeItem(at: entryURL(for: key))
    }

    private func entryURL(for key: LatexCacheKey) -> URL {
        directory.appendingPathComponent(Self.stableIdentifier(key.stableValue) + ".json")
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("bp-viewer/latex", isDirectory: true)
    }

    private static func stableIdentifier(_ value: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    private func isCurrent(_ dependency: CacheDependency) -> Bool {
        guard let current = CacheDependency(url: URL(fileURLWithPath: dependency.path)) else {
            return false
        }
        return current == dependency
    }

    private struct CacheEntry: Codable {
        let version: Int
        let key: String
        let rootPath: String
        let dependencies: [CacheDependency]
        let externalDependencies: [CachePath]
        let pdfBase64: String
        let syncTeXData: String?
        let generatedBibliographySource: String?
        let createdAt: Date
    }

    private struct CachePath: Codable, Sendable {
        let path: String
    }

    private struct CacheDependency: Codable, Equatable, Sendable {
        let path: String
        let byteCount: Int64
        let modificationDate: Date
        let contentFingerprint: String

        init?(url: URL) {
            let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard let values = try? standardizedURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ),
            values.isRegularFile == true,
            let fileSize = values.fileSize,
            let modificationDate = values.contentModificationDate,
            let data = try? Data(contentsOf: standardizedURL) else {
                return nil
            }
            self.path = standardizedURL.path
            byteCount = Int64(fileSize)
            self.modificationDate = modificationDate
            contentFingerprint = Self.fingerprint(data)
        }

        private static func fingerprint(_ data: Data) -> String {
            var hash: UInt64 = 14695981039346656037
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
            return String(hash, radix: 16)
        }
    }
}
