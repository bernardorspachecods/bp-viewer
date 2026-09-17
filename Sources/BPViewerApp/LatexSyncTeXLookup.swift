import Foundation
import BPViewerCore

struct LatexSourceLocation: Sendable {
    let url: URL
    let line: Int
    let column: Int
}

enum LatexSyncTeXLookup {
    static func location(
        syncTeXData: Data,
        pdfData: Data,
        pageIndex: Int,
        pointFromTopLeft: CGPoint,
        projectRoot: URL? = nil
    ) -> LatexSourceLocation? {
        guard let synctex = String(data: syncTeXData, encoding: .utf8), !synctex.isEmpty else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-viewer-synctex-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pdfData.write(to: directory.appendingPathComponent("preview.pdf"), options: .atomic)
            try synctex.write(
                to: directory.appendingPathComponent("preview.synctex"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            return nil
        }

        guard let executable = LatexExecutableLocator().findTool(named: "synctex") else { return nil }
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = [
            "edit",
            "-o",
            "\(pageIndex + 1):\(pointFromTopLeft.x):\(pointFromTopLeft.y):\(directory.appendingPathComponent("preview.pdf").path)",
            "-d", directory.path
        ]
        process.currentDirectoryURL = directory
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        do {
            try process.run()
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let result = String(data: output, encoding: .utf8) else { return nil }
            guard let location = parse(result) else { return nil }
            return normalized(location, relativeTo: projectRoot)
        } catch {
            return nil
        }
    }

    static func parse(_ output: String) -> LatexSourceLocation? {
        var inputPath: String?
        var line: Int?
        var column = 0
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let value = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("Input:") {
                inputPath = String(value.dropFirst("Input:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if value.hasPrefix("Line:") {
                line = Int(value.dropFirst("Line:".count).trimmingCharacters(in: .whitespacesAndNewlines))
            } else if value.hasPrefix("Column:") {
                column = Int(value.dropFirst("Column:".count).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }
        guard let inputPath, let line else { return nil }
        return LatexSourceLocation(
            url: URL(fileURLWithPath: inputPath),
            line: max(line, 1),
            column: max(column, 0)
        )
    }

    private static func normalized(
        _ location: LatexSourceLocation,
        relativeTo projectRoot: URL?
    ) -> LatexSourceLocation {
        guard let projectRoot,
              !location.url.path.hasPrefix("/") else {
            return location
        }

        return LatexSourceLocation(
            url: projectRoot.appendingPathComponent(location.url.path),
            line: location.line,
            column: location.column
        )
    }
}
