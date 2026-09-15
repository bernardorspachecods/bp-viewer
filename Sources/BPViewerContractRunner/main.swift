import BPViewerCore
import Darwin
import Foundation

@main
struct BPViewerContractRunner {
    static func main() throws {
        let result = try SwiftMarkdownAdapter().render(
            source: """
            # Heading

            # Heading

            This is **important** with [a link](chapter-2.md) and an image:

            ![Figure](images/figure.png)

            Math: $E = mc^2$

            $$\\frac{a}{b}$$

            <script>alert('unsafe')</script>
            """,
            baseURL: URL(fileURLWithPath: "/tmp/project/chapter-1")
        )

        expect(result.html.contains("<h1 id=\"heading\""), "heading")
        expect(result.blocks.first?.kind == .heading, "render result exposes editable blocks")
        expect(result.html.contains("data-bp-block-id=\"markdown-block-1\""), "rendered blocks expose stable edit IDs")
        expect(result.html.contains("<h1 id=\"heading-2\""), "duplicate heading id")
        expect(result.outline.map(\.title) == ["Heading", "Heading"], "Markdown outline titles")
        expect(result.outline.map(\.level) == [1, 1], "Markdown outline levels")
        expect(result.outline.map(\.id) == ["heading", "heading-2"], "Markdown outline IDs")
        expect(result.html.contains("<strong>important</strong>"), "strong text")
        expect(
            result.html.contains("href=\"bpviewer://open-local-file?path=/tmp/project/chapter-1/chapter-2.md\""),
            "relative link"
        )
        expect(result.html.contains("src=\"images/figure.png\""), "relative image")
        expect(result.baseURL.absoluteString.hasSuffix("/"), "directory base URL")
        expect(result.dependencies.contains(URL(fileURLWithPath: "/tmp/project/chapter-1/images/figure.png")), "image dependency")
        expect(result.html.contains("Content-Security-Policy"), "content security policy")
        expect(!result.html.contains("<script"), "raw html removed")
        expect(result.html.contains("<math"), "math")
        expect(result.html.contains("<msup>"), "superscript")
        expect(result.html.contains("<mfrac>"), "fraction")

        let thesisLinkResult = try SwiftMarkdownAdapter().render(
            source: """
            [Tema original no CSV](../../../thesis_choice/working/thesis_topics_master.csv)
            [Plano anterior do C409](../README.md)
            """,
            baseURL: URL(fileURLWithPath: "/tmp/thesis/thesis_proposal/c409/working")
        )
        expect(
            thesisLinkResult.html.contains("href=\"bpviewer://open-local-file?path=/tmp/thesis/thesis_choice/working/thesis_topics_master.csv\""),
            "cross-project relative link"
        )
        expect(
            thesisLinkResult.html.contains("href=\"bpviewer://open-local-file?path=/tmp/thesis/thesis_proposal/c409/README.md\""),
            "parent-directory relative link"
        )
        expect(
            thesisLinkResult.baseURL.appendingPathComponent("../../../thesis_choice/working/thesis_topics_master.csv")
                .standardizedFileURL.path == "/tmp/thesis/thesis_choice/working/thesis_topics_master.csv",
            "relative link path resolution"
        )
        let bridgedLinkURL = MarkdownPreviewLink.url(
            for: URL(fileURLWithPath: "/tmp/thesis/space folder/README.md")
        )
        expect(bridgedLinkURL?.scheme == "bpviewer", "local link bridge scheme")
        expect(
            bridgedLinkURL.flatMap(MarkdownPreviewLink.fileURL(from:))?.path
                == "/tmp/thesis/space folder/README.md",
            "local link bridge round trip"
        )

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-viewer-local-image-" + UUID().uuidString, isDirectory: true)
        let imageDirectory = fixtureRoot.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let pixelData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        try pixelData.write(to: imageDirectory.appendingPathComponent("pixel.png"))

        let localImageResult = try SwiftMarkdownAdapter().render(
            source: "![Pixel](images/pixel.png)",
            baseURL: fixtureRoot
        )
        expect(localImageResult.html.contains("src=\"data:image/png;base64,"), "local image is embedded")
        expect(
            localImageResult.dependencies.contains(imageDirectory.appendingPathComponent("pixel.png")),
            "embedded local image remains a dependency"
        )

        let latexProject = fixtureRoot.appendingPathComponent("developer-cv", isDirectory: true)
        let latexRoot = latexProject.appendingPathComponent("main.tex")
        let latexChapter = latexProject.appendingPathComponent("chapters/methods.tex")
        try FileManager.default.createDirectory(
            at: latexChapter.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "\\documentclass{developercv}\n\\begin{document}\nMain\\end{document}\n"
            .write(to: latexRoot, atomically: true, encoding: .utf8)
        try "\\ProvidesClass{developercv}\n\\LoadClass{article}\n"
            .write(
                to: latexProject.appendingPathComponent("developercv.cls"),
                atomically: true,
                encoding: .utf8
            )
        try "\\section{Methods}\nChapter text\n"
            .write(to: latexChapter, atomically: true, encoding: .utf8)

        let latexResolution = try LatexRootDiscovery().resolve(
            openedFile: latexChapter,
            projectRoot: fixtureRoot
        )
        expect(latexResolution.selectedRoot == latexRoot, "LaTeX root discovery")
        expect(
            latexResolution.candidates.first?.reasons.contains("documentclass") == true,
            "LaTeX root discovery evidence"
        )
        var persistedContexts = [String: String]()
        LatexTabContextPersistence.store(
            contextURL: latexChapter,
            forTabID: latexRoot.path,
            in: &persistedContexts
        )
        expect(
            LatexTabContextPersistence.restore(
                forTabID: latexRoot.path,
                tabURL: latexRoot,
                kind: .latex,
                from: persistedContexts,
                projectRoot: latexProject
            ) == latexChapter.standardizedFileURL,
            "LaTeX chapter context persistence"
        )
        let pdflatexOnly = fixtureRoot.appendingPathComponent("pdflatex")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/echo"),
            to: pdflatexOnly
        )
        defer { try? FileManager.default.removeItem(at: pdflatexOnly) }
        expect(
            LatexExecutableLocator(candidateURLs: [pdflatexOnly])
                .findCompiler(preferredKind: .xelatex) == nil,
            "specialised LaTeX engine does not fall back to pdfLaTeX"
        )
        let latexmkOnly = fixtureRoot.appendingPathComponent("latexmk")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/echo"),
            to: latexmkOnly
        )
        defer { try? FileManager.default.removeItem(at: latexmkOnly) }
        expect(
            LatexExecutableLocator(candidateURLs: [pdflatexOnly, latexmkOnly])
                .findCompiler(preferredKind: .xelatex)?.kind == .latexmk,
            "latexmk remains preferred over direct engine"
        )

        let latexRenderResult = try LocalLatexAdapter(
            runner: SuccessfulLatexProcessRunner(),
            executableURL: URL(fileURLWithPath: "/tmp/fake-latexmk")
        ).render(rootURL: latexRoot, projectRoot: fixtureRoot)
        expect(latexRenderResult.pdfData.starts(with: Data("%PDF-1.4".utf8)), "LaTeX PDF output")
        expect(latexRenderResult.rootURL == latexRoot.standardizedFileURL, "LaTeX render root")
        expect(
            latexRenderResult.dependencies.contains(latexProject.appendingPathComponent("developercv.cls")),
            "local LaTeX class dependency"
        )
        expect(
            latexRenderResult.dependencies.contains(latexChapter),
            "recorder chapter dependency"
        )
        do {
            _ = try LocalLatexAdapter(
                runner: InvalidPDFProcessRunner(),
                executableURL: URL(fileURLWithPath: "/tmp/fake-latexmk")
            ).render(rootURL: latexRoot, projectRoot: fixtureRoot)
            expect(false, "invalid LaTeX PDF is rejected")
        } catch LatexRenderError.outputPDFInvalid {
            expect(true, "invalid LaTeX PDF is rejected")
        }
        expect(
            !FileManager.default.fileExists(
                atPath: fixtureRoot.appendingPathComponent(".bp-viewer-output").path
            ),
            "LaTeX output stays outside source project"
        )

        let daemonSocket = fixtureRoot.appendingPathComponent("daemon.sock")
        expect(Darwin.mkfifo(daemonSocket.path, 0o600) == 0, "create runtime socket fixture")
        defer { _ = Darwin.unlink(daemonSocket.path) }
        do {
            _ = try LocalLatexAdapter(
                runner: SuccessfulLatexProcessRunner(),
                executableURL: URL(fileURLWithPath: "/tmp/fake-latexmk")
            ).render(rootURL: latexRoot, projectRoot: fixtureRoot)
            expect(true, "LaTeX ignores runtime socket")
        } catch {
            fatalError("LaTeX runtime artifact regression: \(error.localizedDescription)")
        }

        let processResult = try LiveProcessRunner().run(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["bp-viewer-process-runner"],
                workingDirectory: fixtureRoot
            )
        )
        expect(processResult.status == .success, "process runner success status")
        expect(processResult.standardOutput.contains("bp-viewer-process-runner"), "process runner captures stdout")
        let boundedProcessResult = try LiveProcessRunner().run(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/bin/echo"),
                arguments: [String(repeating: "x", count: 100)],
                workingDirectory: fixtureRoot,
                maxOutputBytes: 20
            )
        )
        expect(
            boundedProcessResult.standardOutput.contains("output truncated"),
            "process runner bounds compiler output"
        )
        let timedOutProcessResult = try LiveProcessRunner().run(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                workingDirectory: fixtureRoot,
                timeout: 0.05
            )
        )
        expect(timedOutProcessResult.status == .timedOut, "process runner reports timeout")

        if let compiler = LatexExecutableLocator().findCompiler() {
            let liveLatexResult = try LocalLatexAdapter(
                executableURL: compiler.url,
                timeout: 30
            ).render(rootURL: latexRoot, projectRoot: fixtureRoot)
            expect(liveLatexResult.pdfData.starts(with: Data("%PDF".utf8)), "\(compiler.kind.rawValue) compiles fixture")
        } else {
            print("SKIP no local LaTeX compiler found")
        }

        let manualFixtureProject = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/latex-preview-test", isDirectory: true)
        let manualFixtureRoot = manualFixtureProject.appendingPathComponent("main.tex")
        if FileManager.default.fileExists(atPath: manualFixtureRoot.path) {
            let manualFixtureResult = try LocalLatexAdapter(timeout: 60).render(
                rootURL: manualFixtureRoot,
                projectRoot: manualFixtureProject
            )
            expect(
                manualFixtureResult.pdfData.starts(with: Data("%PDF".utf8))
                    && manualFixtureResult.dependencies.contains {
                        $0.lastPathComponent == "fixture-diagram.tex"
                    }
                    && manualFixtureResult.dependencies.contains {
                        $0.lastPathComponent == "references.bib"
                    },
                "manual LaTeX fixture compiles with BibTeX"
            )
            let broadProjectRoot = manualFixtureProject
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let broadRootResult = try LocalLatexAdapter(timeout: 30).render(
                rootURL: manualFixtureRoot,
                projectRoot: broadProjectRoot
            )
            expect(
                broadRootResult.pdfData.starts(with: Data("%PDF".utf8)),
                "nested LaTeX fixture avoids broad-root traversal"
            )
        } else {
            print("SKIP manual LaTeX fixture not found")
        }

        let realCorpusProject = URL(fileURLWithPath: "/Users/bernardopacheco/developer-cv")
        let realCorpusRoot = realCorpusProject.appendingPathComponent("main.tex")
        if FileManager.default.fileExists(atPath: realCorpusRoot.path) {
            let realCorpusResult = try LocalLatexAdapter(timeout: 60).render(
                rootURL: realCorpusRoot,
                projectRoot: realCorpusProject
            )
            expect(
                realCorpusResult.pdfData.starts(with: Data("%PDF".utf8))
                    && realCorpusResult.dependencies.contains {
                        $0.lastPathComponent == "developercv.cls"
                    },
                "developer-cv corpus compiles in isolated workspace"
            )
        } else {
            print("SKIP real developer-cv corpus not found")
        }

        let secondLatexRoot = fixtureRoot.appendingPathComponent("appendix.tex")
        try "\\documentclass{article}\n\\begin{document}\nAppendix\n\\end{document}\n"
            .write(to: secondLatexRoot, atomically: true, encoding: .utf8)
        let ambiguousLatexResolution = try LatexRootDiscovery().resolve(
            openedFile: latexChapter,
            projectRoot: fixtureRoot
        )
        expect(ambiguousLatexResolution.selectedRoot == nil, "ambiguous LaTeX roots need selection")
        expect(ambiguousLatexResolution.requiresSelection, "ambiguous LaTeX selection state")

        let emptyRootProject = fixtureRoot.appendingPathComponent("empty-root", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRootProject, withIntermediateDirectories: true)
        let incompleteLatexFile = emptyRootProject.appendingPathComponent("notes.tex")
        try "\\section{Notes}\n".write(to: incompleteLatexFile, atomically: true, encoding: .utf8)
        let emptyRootResolution = try LatexRootDiscovery().resolve(
            openedFile: incompleteLatexFile,
            projectRoot: emptyRootProject
        )
        expect(emptyRootResolution.candidates.isEmpty, "no automatic LaTeX root")
        expect(emptyRootResolution.requiresSelection, "no-root LaTeX selection state")

        let bibliographyRoot = fixtureRoot.appendingPathComponent("bibliography.tex")
        try """
        \\documentclass{article}
        \\usepackage{biblatex}
        \\addbibresource{references.bib}
        \\input{\(fixtureRoot.deletingLastPathComponent().appendingPathComponent("bp-viewer-external.tex").path)}
        \\begin{document}
        Bibliography
        \\printbibliography
        \\end{document}
        """.write(to: bibliographyRoot, atomically: true, encoding: .utf8)
        try "@book{example, author={Example}, title={A title}, year={2026}}\n"
            .write(
                to: fixtureRoot.appendingPathComponent("references.bib"),
                atomically: true,
                encoding: .utf8
            )
        let externalDependency = fixtureRoot.deletingLastPathComponent()
            .appendingPathComponent("bp-viewer-external.tex")
        try "External dependency\n"
            .write(to: externalDependency, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: externalDependency) }
        let externalDependencies = LocalLatexAdapter().externalDependencies(
            rootURL: bibliographyRoot,
            projectRoot: fixtureRoot
        )
        expect(
            externalDependencies.contains { $0.url == externalDependency.standardizedFileURL },
            "external LaTeX dependency detection"
        )
        var invalidContexts = [String: String]()
        LatexTabContextPersistence.store(
            contextURL: externalDependency,
            forTabID: bibliographyRoot.path,
            in: &invalidContexts
        )
        expect(
            LatexTabContextPersistence.restore(
                forTabID: bibliographyRoot.path,
                tabURL: bibliographyRoot,
                kind: .latex,
                from: invalidContexts,
                projectRoot: fixtureRoot
            ) == nil,
            "LaTeX context outside project is rejected"
        )
        let linkedExternalRoot = fixtureRoot.appendingPathComponent("linked-external.tex")
        let linkedExternalPath = fixtureRoot.appendingPathComponent("linked.tex")
        try "\\input{linked.tex}\n".write(
            to: linkedExternalRoot,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: linkedExternalPath,
            withDestinationURL: externalDependency
        )
        defer {
            try? FileManager.default.removeItem(at: linkedExternalRoot)
            try? FileManager.default.removeItem(at: linkedExternalPath)
        }
        let linkedDependencies = LocalLatexAdapter().externalDependencies(
            rootURL: linkedExternalRoot,
            projectRoot: fixtureRoot
        )
        expect(
            linkedDependencies.contains { $0.url == externalDependency.resolvingSymlinksInPath().standardizedFileURL },
            "symlinked external LaTeX dependency requires confirmation"
        )
        let bibliographyRunner = RecordingLatexProcessRunner()
        let bibliographyResult = try LocalLatexAdapter(
            runner: bibliographyRunner,
            executableURL: URL(fileURLWithPath: "/tmp/pdflatex"),
            biberExecutableURL: URL(fileURLWithPath: "/tmp/biber")
        ).render(rootURL: bibliographyRoot, projectRoot: fixtureRoot)
        expect(
            bibliographyRunner.calls == ["pdflatex", "biber", "pdflatex", "pdflatex"],
            "BibLaTeX fallback pass sequence"
        )
        expect(
            bibliographyRunner.requests.first?.arguments.contains("-no-shell-escape") == true,
            "LaTeX shell escape disabled by default"
        )
        expect(
            ["TEXINPUTS", "BIBINPUTS", "BSTINPUTS"].allSatisfy { key in
                !(bibliographyRunner.requests.first?.environment[key]?.contains("//") ?? true)
            },
            "LaTeX search paths are non-recursive"
        )
        expect(
            bibliographyResult.externalDependencies.contains(externalDependency.standardizedFileURL),
            "approved external dependency remains observable"
        )

        let fontRoot = fixtureRoot.appendingPathComponent("system-fonts.tex")
        try """
        \\documentclass{article}
        \\usepackage{fontspec}
        \\begin{document}
        System fonts
        \\end{document}
        """.write(to: fontRoot, atomically: true, encoding: .utf8)
        let fontRunner = RecordingLatexProcessRunner()
        _ = try LocalLatexAdapter(
            runner: fontRunner,
            executableURL: URL(fileURLWithPath: "/tmp/xelatex")
        ).render(rootURL: fontRoot, projectRoot: fixtureRoot)
        expect(fontRunner.calls == ["xelatex", "xelatex", "xelatex"], "XeLaTeX engine selection and reruns")
        expect(
            fontRunner.requests.first?.arguments.contains("-no-shell-escape") == true,
            "LaTeX shell escape disabled by default"
        )

        let cacheDirectory = fixtureRoot.deletingLastPathComponent()
            .appendingPathComponent("bp-viewer-latex-cache-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let cache = LatexRenderCache(directory: cacheDirectory)
        let cacheKey = LatexCacheKey(
            projectRoot: fixtureRoot,
            rootURL: latexRoot,
            compilerIdentity: "pdflatex\u{1f}/tmp/pdflatex",
            shellEscapeMode: .disabled
        )
        let cachedPDF = Data("%PDF-1.4\n% cached PDF\n".utf8)
        let cacheResult = LatexRenderResult(
            pdfData: cachedPDF,
            rootURL: latexRoot,
            dependencies: [latexRoot, latexProject.appendingPathComponent("developercv.cls")],
            processResult: ProcessResult(status: .success, exitCode: 0, standardOutput: "", standardError: "")
        )
        try cache.store(key: cacheKey, result: cacheResult)
        expect(cache.load(key: cacheKey)?.pdfData == cachedPDF, "LaTeX cache hit")
        let changedRoot = try String(contentsOf: latexRoot, encoding: .utf8) + "% changed\n"
        try changedRoot.write(to: latexRoot, atomically: true, encoding: .utf8)
        expect(cache.load(key: cacheKey) == nil, "LaTeX cache invalidates changed dependency")
        try "\\documentclass{developercv}\n\\begin{document}\nMain\\end{document}\n"
            .write(to: latexRoot, atomically: true, encoding: .utf8)
        try cache.store(key: cacheKey, result: cacheResult)
        let changedModeKey = LatexCacheKey(
            projectRoot: fixtureRoot,
            rootURL: latexRoot,
            compilerIdentity: "pdflatex\u{1f}/tmp/pdflatex",
            shellEscapeMode: .restricted
        )
        expect(cache.load(key: changedModeKey) == nil, "LaTeX cache invalidates configuration change")
        let failedCacheResult = LatexRenderResult(
            pdfData: Data("%PDF-1.4\n% failed output\n".utf8),
            rootURL: latexRoot,
            dependencies: cacheResult.dependencies,
            processResult: ProcessResult(status: .failed, exitCode: 1, standardOutput: "", standardError: "error")
        )
        try cache.store(key: cacheKey, result: failedCacheResult)
        expect(cache.load(key: cacheKey)?.pdfData == cachedPDF, "failed LaTeX render does not replace cache")
    }

    private static func expect(_ condition: Bool, _ name: String) {
        guard condition else {
            fatalError("Contract failed: \(name)")
        }
        print("PASS \(name)")
    }
}

private struct SuccessfulLatexProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) throws -> ProcessResult {
        guard let rootArgument = request.arguments.last else {
            fatalError("LaTeX contract failed: root argument missing")
        }
        let rootURL = URL(fileURLWithPath: rootArgument)
        expect(
            FileManager.default.fileExists(atPath: rootURL.path),
            "LaTeX source remains available"
        )
        expect(
            request.workingDirectory.standardizedFileURL != rootURL.deletingLastPathComponent().standardizedFileURL
                && request.environment["TEXINPUTS"]?.contains(rootURL.deletingLastPathComponent().path) == true,
            "LaTeX compiler uses isolated cwd and recursive project inputs"
        )
        guard let outputArgument = request.arguments.first(where: { $0.hasPrefix("-outdir=") }) else {
            fatalError("LaTeX contract failed: output directory argument missing")
        }
        let outputDirectory = URL(fileURLWithPath: String(outputArgument.dropFirst("-outdir=".count)))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let rootName = request.arguments.last.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "main"
        try Data("%PDF-1.4\\n% fake PDF\\n".utf8)
            .write(to: outputDirectory.appendingPathComponent(rootName + ".pdf"))
        let recorder = """
        PWD \(request.workingDirectory.path)
        INPUT \(rootURL.path)
        INPUT \(rootURL.deletingLastPathComponent().appendingPathComponent("chapters/methods.tex").path)
        INPUT \(rootURL.deletingLastPathComponent().appendingPathComponent("developercv.cls").path)
        INPUT \(outputDirectory.path)/\(rootName).aux
        """
        try recorder.write(
            to: outputDirectory.appendingPathComponent(rootName + ".fls"),
            atomically: true,
            encoding: .utf8
        )
        return ProcessResult(status: .success, exitCode: 0, standardOutput: "", standardError: "")
    }

    private func expect(_ condition: Bool, _ name: String) {
        guard condition else {
            fatalError("LaTeX contract failed: \(name)")
        }
    }
}

private struct InvalidPDFProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) throws -> ProcessResult {
        guard let outputArgument = request.arguments.first(where: { $0.hasPrefix("-outdir=") }) else {
            fatalError("LaTeX invalid PDF contract failed: output directory argument missing")
        }
        let outputDirectory = URL(fileURLWithPath: String(outputArgument.dropFirst("-outdir=".count)))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let rootName = request.arguments.last.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "main"
        try Data("not a pdf".utf8).write(to: outputDirectory.appendingPathComponent(rootName + ".pdf"))
        return ProcessResult(status: .success, exitCode: 0, standardOutput: "", standardError: "")
    }
}

private final class RecordingLatexProcessRunner: @unchecked Sendable, ProcessRunning {
    private(set) var calls: [String] = []
    private(set) var requests: [ProcessRequest] = []

    func run(_ request: ProcessRequest) throws -> ProcessResult {
        let executableName = request.executable.lastPathComponent
        calls.append(executableName)
        requests.append(request)
        guard ["pdflatex", "xelatex", "lualatex"].contains(executableName) else {
            return ProcessResult(status: .success, exitCode: 0, standardOutput: "", standardError: "")
        }

        guard let outputArgument = request.arguments.first(where: { $0.hasPrefix("-output-directory=") }) else {
            fatalError("LaTeX bibliography contract failed: output directory argument missing")
        }
        let outputDirectory = URL(fileURLWithPath: String(outputArgument.dropFirst("-output-directory=".count)))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let rootName = request.arguments.last.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "main"
        try Data("%PDF-1.4\\n% fake PDF\\n".utf8)
            .write(to: outputDirectory.appendingPathComponent(rootName + ".pdf"))
        return ProcessResult(status: .success, exitCode: 0, standardOutput: "", standardError: "")
    }
}
