import Foundation
import Darwin

public enum ProcessRunStatus: String, Sendable {
    case success
    case failed
    case cancelled
    case timedOut
    case launchFailed
}

public struct ProcessRequest: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let workingDirectory: URL
    public let environment: [String: String]
    public let timeout: TimeInterval
    public let maxOutputBytes: Int

    public init(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String] = [:],
        timeout: TimeInterval = 120,
        maxOutputBytes: Int = 2_000_000
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.maxOutputBytes = max(0, maxOutputBytes)
    }
}

public struct ProcessResult: Sendable {
    public let status: ProcessRunStatus
    public let exitCode: Int32?
    public let standardOutput: String
    public let standardError: String
    public let duration: TimeInterval

    public init(
        status: ProcessRunStatus,
        exitCode: Int32?,
        standardOutput: String,
        standardError: String,
        duration: TimeInterval = 0
    ) {
        self.status = status
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.duration = duration
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) throws -> ProcessResult
}

public enum LatexRenderError: LocalizedError, Sendable {
    case rootIsNotFile(URL)
    case rootOutsideProject(URL)
    case projectRootIsNotDirectory(URL)
    case rootSelectionRequired([LatexRootCandidate])
    case externalDependenciesRequireConfirmation(URL, [LatexExternalDependency])
    case toolUnavailable(String)
    case compilationFailed(ProcessResult)
    case outputPDFMissing(URL, ProcessResult)
    case outputPDFUnreadable(URL)
    case outputPDFInvalid(URL)
    case workspaceFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .rootIsNotFile(url):
            return "The LaTeX root is not a file: \(url.path)"
        case let .rootOutsideProject(url):
            return "The LaTeX root is outside the project folder: \(url.path)"
        case let .projectRootIsNotDirectory(url):
            return "The LaTeX project folder does not exist or is not a folder: \(url.path)"
        case let .rootSelectionRequired(candidates):
            if candidates.isEmpty {
                return "No main LaTeX document was found in this folder."
            }
            let paths = candidates.map(\.url.path).joined(separator: ", ")
            return "You must choose the main LaTeX document from: \(paths)"
        case let .externalDependenciesRequireConfirmation(_, dependencies):
            let paths = dependencies.map(\.url.path).joined(separator: ", ")
            return "The LaTeX document references files outside the project folder and requires confirmation: \(paths)"
        case let .toolUnavailable(name):
            return "The LaTeX tool '\(name)' was not found. Install a local LaTeX distribution and try again."
        case let .compilationFailed(result):
            let output = result.combinedOutput
            if output.isEmpty {
                return "LaTeX compilation failed (code \(result.exitCode.map(String.init) ?? "unknown"))."
            }
            return "LaTeX compilation failed:\n\(output)"
        case let .outputPDFMissing(url, result):
            return "Compilation finished without producing the expected PDF at \(url.path).\n\(result.combinedOutput)"
        case let .outputPDFUnreadable(url):
            return "Unable to read the compiled PDF: \(url.path)"
        case let .outputPDFInvalid(url):
            return "The tool produced a file that is not a valid PDF: \(url.path)"
        case let .workspaceFailed(message):
            return "Unable to prepare the temporary LaTeX workspace: \(message)"
        }
    }
}

public struct LiveProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ request: ProcessRequest) throws -> ProcessResult {
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectory
        if !request.environment.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            request.environment.forEach { environment[$0.key] = $0.value }
            process.environment = environment
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let startedAt = Date()

        do {
            try process.run()
        } catch {
            return ProcessResult(
                status: .launchFailed,
                exitCode: nil,
                standardOutput: "",
                standardError: error.localizedDescription,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        let processIdentifier = process.processIdentifier
        let processGroupConfigured = processIdentifier > 0
            && setpgid(processIdentifier, processIdentifier) == 0

        let outputBuffer = ProcessOutputBuffer(handle: outputPipe.fileHandleForReading)
        let errorBuffer = ProcessOutputBuffer(handle: errorPipe.fileHandleForReading)
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBuffer.capture(maxBytes: request.maxOutputBytes)
            outputGroup.leave()
        }
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBuffer.capture(maxBytes: request.maxOutputBytes)
            outputGroup.leave()
        }

        var status: ProcessRunStatus = .success
        while process.isRunning {
            if Task.isCancelled {
                terminate(
                    process,
                    processIdentifier: processIdentifier,
                    processGroupConfigured: processGroupConfigured
                )
                status = .cancelled
                break
            }
            if request.timeout > 0, Date().timeIntervalSince(startedAt) >= request.timeout {
                terminate(
                    process,
                    processIdentifier: processIdentifier,
                    processGroupConfigured: processGroupConfigured
                )
                status = .timedOut
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        process.waitUntilExit()
        outputGroup.wait()
        if status == .success, process.terminationStatus != 0 {
            status = .failed
        }

        return ProcessResult(
            status: status,
            exitCode: process.terminationStatus,
            standardOutput: outputBuffer.string,
            standardError: errorBuffer.string,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func terminate(
        _ process: Process,
        processIdentifier: pid_t,
        processGroupConfigured: Bool
    ) {
        if processGroupConfigured {
            _ = kill(-processIdentifier, SIGTERM)
        }
        process.terminate()
        Thread.sleep(forTimeInterval: 0.1)
        guard process.isRunning else { return }
        if processGroupConfigured {
            _ = kill(-processIdentifier, SIGKILL)
        }
        process.terminate()
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func capture(maxBytes: Int) {
        let chunkSize = 64 * 1024
        var capturedData = Data()
        var wasTruncated = false
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { break }
            guard capturedData.count < maxBytes else {
                wasTruncated = true
                continue
            }
            let remaining = maxBytes - capturedData.count
            if chunk.count <= remaining {
                capturedData.append(chunk)
            } else {
                capturedData.append(chunk.prefix(remaining))
                wasTruncated = true
            }
        }
        if wasTruncated {
            capturedData.append(Data("\n[output truncated by bp-viewer]\n".utf8))
        }
        lock.lock()
        data = capturedData
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct LatexExecutableLocator: Sendable {
    private let injectedCandidates: [URL]?

    public init(candidateURLs: [URL]? = nil) {
        injectedCandidates = candidateURLs?.map(\.standardizedFileURL)
    }

    public func findTool(named name: String) -> URL? {
        let candidates = injectedCandidates ?? [
            URL(fileURLWithPath: "/Library/TeX/texbin/\(name)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            URL(fileURLWithPath: "/usr/bin/\(name)")
        ]
        return candidates
            .filter { $0.lastPathComponent == name }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func findCompiler(preferredKind: LatexCompilerKind? = nil) -> LatexCompiler? {
        let candidates: [(String, LatexCompilerKind)] = injectedCandidates?.compactMap { url in
            guard let kind = LatexCompilerKind(rawValue: url.lastPathComponent.lowercased()) else {
                return nil
            }
            return (url.path, kind)
        } ?? [
            ("/Library/TeX/texbin/latexmk", .latexmk),
            ("/opt/homebrew/bin/latexmk", .latexmk),
            ("/usr/local/bin/latexmk", .latexmk),
            ("/usr/bin/latexmk", .latexmk),
            ("/Library/TeX/texbin/pdflatex", .pdflatex),
            ("/opt/homebrew/bin/pdflatex", .pdflatex),
            ("/usr/local/bin/pdflatex", .pdflatex),
            ("/usr/bin/pdflatex", .pdflatex),
            ("/Library/TeX/texbin/xelatex", .xelatex),
            ("/opt/homebrew/bin/xelatex", .xelatex),
            ("/usr/local/bin/xelatex", .xelatex),
            ("/usr/bin/xelatex", .xelatex),
            ("/Library/TeX/texbin/lualatex", .lualatex),
            ("/opt/homebrew/bin/lualatex", .lualatex),
            ("/usr/local/bin/lualatex", .lualatex),
            ("/usr/bin/lualatex", .lualatex)
        ]
        let orderedCandidates: [(String, LatexCompilerKind)]
        if let preferredKind {
            let latexmkCandidates = candidates.filter { $0.1 == .latexmk }
            let preferredCandidates = candidates.filter { $0.1 == preferredKind && $0.1 != .latexmk }
            let remainingCandidates = candidates.filter {
                $0.1 != .latexmk && $0.1 != preferredKind
            }
            orderedCandidates = latexmkCandidates + preferredCandidates + remainingCandidates
        } else {
            orderedCandidates = candidates
        }
        let candidatesToProbe: [(String, LatexCompilerKind)]
        if preferredKind == .xelatex || preferredKind == .lualatex {
            // A document that requires a specialised engine must not silently
            // fall back to pdfLaTeX. latexmk remains a valid wrapper because
            // it is invoked with the corresponding engine flag above.
            candidatesToProbe = orderedCandidates.filter {
                $0.1 == .latexmk || $0.1 == preferredKind
            }
        } else {
            candidatesToProbe = orderedCandidates
        }

        return candidatesToProbe
            .map { LatexCompiler(url: URL(fileURLWithPath: $0.0), kind: $0.1) }
            .first { FileManager.default.isExecutableFile(atPath: $0.url.path) }
    }
}

public enum LatexCompilerKind: String, Sendable {
    case latexmk
    case pdflatex
    case xelatex
    case lualatex
}

public enum LatexShellEscapeMode: String, CaseIterable, Codable, Sendable {
    case disabled
    case restricted
    case enabled

    public var label: String {
        switch self {
        case .disabled: "Disabled"
        case .restricted: "Restricted"
        case .enabled: "Enabled"
        }
    }
}

public struct LatexCompiler: Sendable {
    public let url: URL
    public let kind: LatexCompilerKind

    public init(url: URL, kind: LatexCompilerKind) {
        self.url = url.standardizedFileURL
        self.kind = kind
    }
}

public struct LatexRenderResult: Sendable {
    public let pdfData: Data
    public let rootURL: URL
    public let dependencies: [URL]
    public let externalDependencies: [URL]
    public let processResult: ProcessResult
    public let wasCached: Bool

    public init(
        pdfData: Data,
        rootURL: URL,
        dependencies: [URL],
        externalDependencies: [URL] = [],
        processResult: ProcessResult,
        wasCached: Bool = false
    ) {
        self.pdfData = pdfData
        self.rootURL = rootURL.standardizedFileURL
        self.dependencies = dependencies.map(\.standardizedFileURL)
        self.externalDependencies = externalDependencies.map(\.standardizedFileURL)
        self.processResult = processResult
        self.wasCached = wasCached
    }
}

public struct LatexExternalDependency: Hashable, Sendable {
    public let url: URL
    public let sourceURL: URL

    public init(url: URL, sourceURL: URL) {
        self.url = url.resolvingSymlinksInPath().standardizedFileURL
        self.sourceURL = sourceURL.resolvingSymlinksInPath().standardizedFileURL
    }
}

public struct LocalLatexAdapter: Sendable {
    private let runner: any ProcessRunning
    private let executableURL: URL?
    private let biberExecutableURL: URL?
    private let bibtexExecutableURL: URL?
    private let shellEscapeMode: LatexShellEscapeMode
    private let timeout: TimeInterval

    public init(
        runner: any ProcessRunning = LiveProcessRunner(),
        executableURL: URL? = nil,
        biberExecutableURL: URL? = nil,
        bibtexExecutableURL: URL? = nil,
        shellEscapeMode: LatexShellEscapeMode = .disabled,
        timeout: TimeInterval = 120
    ) {
        self.runner = runner
        self.executableURL = executableURL
        self.biberExecutableURL = biberExecutableURL
        self.bibtexExecutableURL = bibtexExecutableURL
        self.shellEscapeMode = shellEscapeMode
        self.timeout = timeout
    }

    public func externalDependencies(rootURL: URL, projectRoot: URL) -> [LatexExternalDependency] {
        let root = rootURL.standardizedFileURL
        let project = projectRoot.standardizedFileURL
        guard isDirectory(project), isRegularFile(root), isInside(root, project: project) else {
            return []
        }

        var visited = Set([root])
        var pending = [root]
        var discovered = Set<LatexExternalDependency>()

        while let current = pending.popLast() {
            guard let source = try? String(contentsOf: current, encoding: .utf8) else { continue }
            for reference in referencedPaths(in: source) {
                let candidates = candidateURLs(reference: reference, relativeTo: current)
                if let externalURL = candidates.first(where: {
                    isRegularFile($0) && !isInside($0, project: project)
                }) {
                    discovered.insert(
                        LatexExternalDependency(url: externalURL, sourceURL: current)
                    )
                    continue
                }
                if let localURL = candidates.first(where: {
                    isRegularFile($0) && isInside($0, project: project)
                }), visited.insert(localURL).inserted {
                    pending.append(localURL)
                }
            }
        }

        return discovered.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    public func sourceDependencies(rootURL: URL, projectRoot: URL) -> [URL] {
        let root = rootURL.standardizedFileURL
        let project = projectRoot.standardizedFileURL
        guard isDirectory(project), isRegularFile(root), isInside(root, project: project) else {
            return []
        }
        return dependencies(for: root, project: project)
    }

    public func compilerIdentity(rootURL: URL, projectRoot: URL) throws -> String {
        let root = rootURL.standardizedFileURL
        let project = projectRoot.standardizedFileURL
        guard isDirectory(project) else {
            throw LatexRenderError.projectRootIsNotDirectory(project)
        }
        guard isRegularFile(root) else {
            throw LatexRenderError.rootIsNotFile(root)
        }
        guard isInside(root, project: project) else {
            throw LatexRenderError.rootOutsideProject(root)
        }

        let dependencies = dependencies(for: root, project: project)
        let hint = engineHint(for: dependencies)
        let compiler: LatexCompiler
        if let executableURL {
            let name = executableURL.lastPathComponent.lowercased()
            compiler = LatexCompiler(
                url: executableURL,
                kind: LatexCompilerKind(rawValue: name) ?? .latexmk
            )
        } else if let discovered = LatexExecutableLocator().findCompiler(preferredKind: hint) {
            compiler = discovered
        } else {
            throw LatexRenderError.toolUnavailable(hint?.rawValue ?? "latexmk")
        }

        let values = try? compiler.url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        let effectiveEngine = compiler.kind == .latexmk
            ? (hint ?? .pdflatex)
            : compiler.kind
        return [
            compiler.kind.rawValue,
            effectiveEngine.rawValue,
            compiler.url.standardizedFileURL.path,
            values?.fileSize.map(String.init) ?? "",
            values?.contentModificationDate?.timeIntervalSinceReferenceDate.description ?? ""
        ].joined(separator: "\u{1f}")
    }

    public func render(rootURL: URL, projectRoot: URL) throws -> LatexRenderResult {
        let root = rootURL.standardizedFileURL
        let project = projectRoot.standardizedFileURL
        guard isDirectory(project) else {
            throw LatexRenderError.projectRootIsNotDirectory(project)
        }
        guard isRegularFile(root) else {
            throw LatexRenderError.rootIsNotFile(root)
        }
        guard isInside(root, project: project) else {
            throw LatexRenderError.rootOutsideProject(root)
        }

        let sourceDependencies = dependencies(for: root, project: project)
        let engineHint = engineHint(for: sourceDependencies)
        let externalDependencyURLs = externalDependencies(rootURL: root, projectRoot: project)
            .map(\.url)
        let compiler: LatexCompiler
        if let executableURL {
            let executableName = executableURL.lastPathComponent.lowercased()
            compiler = LatexCompiler(
                url: executableURL,
                kind: LatexCompilerKind(rawValue: executableName) ?? .latexmk
            )
        } else if let discoveredCompiler = LatexExecutableLocator().findCompiler(preferredKind: engineHint) {
            compiler = discoveredCompiler
        } else {
            throw LatexRenderError.toolUnavailable(engineHint?.rawValue ?? "latexmk")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-viewer-latex-" + UUID().uuidString, isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            throw LatexRenderError.workspaceFailed(error.localizedDescription)
        }

        let bibliographyTool = compiler.kind != .latexmk
            ? bibliographyTool(for: sourceDependencies)
            : nil
        let bibliographyExecutable: URL?
        switch bibliographyTool {
        case .biber:
            bibliographyExecutable = biberExecutableURL ?? LatexExecutableLocator().findTool(named: "biber")
        case .bibtex:
            bibliographyExecutable = bibtexExecutableURL ?? LatexExecutableLocator().findTool(named: "bibtex")
        case nil:
            bibliographyExecutable = nil
        }
        if bibliographyTool != nil, bibliographyExecutable == nil {
            throw LatexRenderError.toolUnavailable(bibliographyTool?.rawValue ?? "bibliography tool")
        }

        var arguments: [String] = []
        if compiler.kind == .latexmk {
            arguments.append("-pdf")
            if engineHint == .xelatex {
                arguments.append("-xelatex")
            } else if engineHint == .lualatex {
                arguments.append("-lualatex")
            }
        }
        let outputArgument = compiler.kind == .latexmk
            ? "-outdir=\(outputDirectory.path)"
            : "-output-directory=\(outputDirectory.path)"
        arguments += [
            "-interaction=nonstopmode",
            "-halt-on-error",
            "-file-line-error",
            "-recorder",
            outputArgument,
            root.path
        ]
        arguments.insert(shellEscapeArgument, at: 0)
        let request = ProcessRequest(
            executable: compiler.url,
            arguments: arguments,
            workingDirectory: workspace,
            environment: searchEnvironment(
                root: root,
                project: project,
                dependencies: sourceDependencies + externalDependencyURLs
            ),
            timeout: timeout
        )
        var processResults = [try runner.run(request)]
        guard processResults[0].status == .success else {
            throw LatexRenderError.compilationFailed(combinedResult(processResults))
        }

        if let bibliographyTool, let bibliographyExecutable {
            let bibliographyArguments: [String]
            switch bibliographyTool {
            case .biber:
                bibliographyArguments = [
                    "--input-directory=\(outputDirectory.path)",
                    "--output-directory=\(outputDirectory.path)",
                    root.deletingPathExtension().lastPathComponent
                ]
            case .bibtex:
                bibliographyArguments = [root.deletingPathExtension().lastPathComponent]
            }

            let bibliographyResult = try runner.run(
                ProcessRequest(
                    executable: bibliographyExecutable,
                    arguments: bibliographyArguments,
                    workingDirectory: outputDirectory,
                    environment: searchEnvironment(
                        root: root,
                        project: project,
                        dependencies: sourceDependencies + externalDependencyURLs
                    ),
                    timeout: timeout
                )
            )
            processResults.append(bibliographyResult)
            guard bibliographyResult.status == .success else {
                throw LatexRenderError.compilationFailed(combinedResult(processResults))
            }

            for _ in 0..<2 {
                let rerunResult = try runner.run(request)
                processResults.append(rerunResult)
                guard rerunResult.status == .success else {
                    throw LatexRenderError.compilationFailed(combinedResult(processResults))
                }
            }
        } else if compiler.kind != .latexmk {
            // Without latexmk, resolve cross-references and PDF outlines with
            // the same extra passes that a normal local LaTeX workflow uses.
            for _ in 0..<2 {
                let rerunResult = try runner.run(request)
                processResults.append(rerunResult)
                guard rerunResult.status == .success else {
                    throw LatexRenderError.compilationFailed(combinedResult(processResults))
                }
            }
        }
        let result = combinedResult(processResults)

        let outputURL = outputDirectory
            .appendingPathComponent(root.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw LatexRenderError.outputPDFMissing(outputURL, result)
        }
        guard let pdfData = try? Data(contentsOf: outputURL), !pdfData.isEmpty else {
            throw LatexRenderError.outputPDFUnreadable(outputURL)
        }
        guard pdfData.starts(with: Data("%PDF".utf8)) else {
            throw LatexRenderError.outputPDFInvalid(outputURL)
        }

        let recorderDependencies = dependenciesFromRecorder(
            at: outputDirectory.appendingPathComponent(root.deletingPathExtension().lastPathComponent + ".fls"),
            project: project
        )
        let allDependencies = Set(sourceDependencies).union(recorderDependencies).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        return LatexRenderResult(
            pdfData: pdfData,
            rootURL: root,
            dependencies: allDependencies,
            externalDependencies: externalDependencyURLs,
            processResult: result
        )
    }

    private func searchEnvironment(
        root: URL,
        project: URL,
        dependencies: [URL]
    ) -> [String: String] {
        var directories = Set<URL>([
            project.standardizedFileURL,
            root.deletingLastPathComponent().standardizedFileURL
        ])
        directories.formUnion(
            dependencies.map { $0.deletingLastPathComponent().standardizedFileURL }
        )

        let searchPath = directories
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map(\.path)
            .joined(separator: ":") + ":"
        return [
            // Keep all project paths non-recursive. A broad user-selected
            // root must not make kpathsea traverse protected folders; local
            // dependency directories are already represented in `directories`.
            "TEXINPUTS": searchPath,
            "BIBINPUTS": searchPath,
            "BSTINPUTS": searchPath
        ]
    }

    private func dependencies(for root: URL, project: URL) -> [URL] {
        var discovered = Set([root.standardizedFileURL])
        var pending = [root.standardizedFileURL]

        while let current = pending.popLast() {
            guard let source = try? String(contentsOf: current, encoding: .utf8) else { continue }
            for reference in referencedPaths(in: source) {
                guard let dependency = resolve(reference: reference, relativeTo: current, project: project),
                      discovered.insert(dependency).inserted else { continue }
                pending.append(dependency)
            }
        }

        return discovered.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private var shellEscapeArgument: String {
        switch shellEscapeMode {
        case .disabled:
            "-no-shell-escape"
        case .restricted:
            "-shell-restricted"
        case .enabled:
            "-shell-escape"
        }
    }

    private func dependenciesFromRecorder(at recorderURL: URL, project: URL) -> [URL] {
        guard let recorder = try? String(contentsOf: recorderURL, encoding: .utf8) else {
            return []
        }

        var workingDirectory = recorderURL.deletingLastPathComponent()
        var discovered = Set<URL>()

        for line in recorder.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("PWD ") {
                let path = String(line.dropFirst(4))
                workingDirectory = URL(fileURLWithPath: path).standardizedFileURL
                continue
            }
            guard line.hasPrefix("INPUT ") else { continue }

            let path = String(line.dropFirst(6))
            let inputURL = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : workingDirectory.appendingPathComponent(path))
                .standardizedFileURL
            guard isRegularFile(inputURL), isInside(inputURL, project: project) else { continue }
            discovered.insert(inputURL)
        }

        return discovered.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private enum BibliographyTool: String {
        case biber
        case bibtex
    }

    private func bibliographyTool(for dependencies: [URL]) -> BibliographyTool? {
        var usesBibLaTeX = false
        var usesBibTeX = false

        for dependency in dependencies where ["tex", "cls", "sty"].contains(dependency.pathExtension.lowercased()) {
            guard let source = try? String(contentsOf: dependency, encoding: .utf8) else { continue }
            if source.range(of: #"\\(?:usepackage|RequirePackage)(?:\[[^\]]*\])?\s*\{\s*biblatex\s*\}"#, options: .regularExpression) != nil
                || source.range(of: #"\\addbibresource\s*\{"#, options: .regularExpression) != nil {
                usesBibLaTeX = true
            }
            if source.range(of: #"\\bibliography\s*\{"#, options: .regularExpression) != nil {
                usesBibTeX = true
            }
        }

        if usesBibLaTeX { return .biber }
        if usesBibTeX { return .bibtex }
        return nil
    }

    private func engineHint(for dependencies: [URL]) -> LatexCompilerKind? {
        var usesLua = false
        var usesSystemFonts = false

        for dependency in dependencies where ["tex", "cls", "sty"].contains(dependency.pathExtension.lowercased()) {
            guard let source = try? String(contentsOf: dependency, encoding: .utf8) else { continue }
            if source.range(of: #"\\(?:usepackage|RequirePackage)(?:\[[^\]]*\])?\s*\{\s*luatexja\s*\}"#, options: .regularExpression) != nil
                || source.range(of: #"\\directlua\b"#, options: .regularExpression) != nil {
                usesLua = true
            }
            if source.range(of: #"\\(?:usepackage|RequirePackage)(?:\[[^\]]*\])?\s*\{\s*fontspec\s*\}"#, options: .regularExpression) != nil
                || source.range(of: #"\\(?:setmainfont|setsansfont|setmonofont)\b"#, options: .regularExpression) != nil {
                usesSystemFonts = true
            }
        }

        if usesLua { return .lualatex }
        if usesSystemFonts { return .xelatex }
        return nil
    }

    private func combinedResult(_ results: [ProcessResult]) -> ProcessResult {
        let failed = results.first { $0.status != .success }
        return ProcessResult(
            status: failed?.status ?? .success,
            exitCode: failed?.exitCode ?? results.last?.exitCode,
            standardOutput: results.map(\.standardOutput).filter { !$0.isEmpty }.joined(separator: "\n"),
            standardError: results.map(\.standardError).filter { !$0.isEmpty }.joined(separator: "\n"),
            duration: results.reduce(0) { $0 + $1.duration }
        )
    }

    private func referencedPaths(in source: String) -> [String] {
        let pattern = #"\\(?:input|include|subfile|addbibresource|bibliography|bibliographystyle|includegraphics|documentclass|usepackage|RequirePackage|setmainfont|setsansfont|setmonofont|newfontfamily)(?:\[[^\]]*\])?\s*\{([^}]+)\}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: (source as NSString).length)
        return expression.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return (source as NSString).substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func resolve(reference: String, relativeTo source: URL, project: URL) -> URL? {
        return candidateURLs(reference: reference, relativeTo: source)
            .map(\.standardizedFileURL)
            .first { url in
                isRegularFile(url) && isInside(url, project: project)
            }
    }

    private func candidateURLs(reference: String, relativeTo source: URL) -> [URL] {
        let baseURL = reference.hasPrefix("/")
            ? URL(fileURLWithPath: reference)
            : source.deletingLastPathComponent().appendingPathComponent(reference)
        return [
            baseURL,
            baseURL.appendingPathExtension("tex"),
            baseURL.appendingPathExtension("bib"),
            baseURL.appendingPathExtension("bst"),
            baseURL.appendingPathExtension("cls"),
            baseURL.appendingPathExtension("sty"),
            baseURL.appendingPathExtension("png"),
            baseURL.appendingPathExtension("jpg"),
            baseURL.appendingPathExtension("jpeg"),
            baseURL.appendingPathExtension("pdf"),
            baseURL.appendingPathExtension("eps"),
            baseURL.appendingPathExtension("svg"),
            baseURL.appendingPathExtension("ttf"),
            baseURL.appendingPathExtension("otf"),
            baseURL.appendingPathExtension("woff"),
            baseURL.appendingPathExtension("woff2")
        ]
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && !isDirectory(url)
    }

    private func isInside(_ url: URL, project: URL) -> Bool {
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let projectPath = project.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == projectPath || candidatePath.hasPrefix(projectPath + "/")
    }

}
