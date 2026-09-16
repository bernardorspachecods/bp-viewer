import Testing
import Foundation
@testable import BPViewerCore

@Test("renders core Markdown and keeps resource URLs relative")
func rendersCoreMarkdownAndKeepsResourceURLsRelative() throws {
        let source = """
        # Heading

        This is **important** with [a link](chapter-2.md) and an image:

        ![Figure](images/figure.png)
        """

        let result = try SwiftMarkdownAdapter().render(
            source: source,
            baseURL: URL(fileURLWithPath: "/tmp/project/chapter-1")
        )

    #expect(result.html.contains("<h1 id=\"heading\""))
    #expect(result.html.contains("<strong>important</strong>"))
    #expect(result.html.contains("href=\"bpviewer://open-local-file?path=/tmp/project/chapter-1/chapter-2.md\""))
    #expect(result.html.contains("src=\"images/figure.png\""))
}

@Test("does not pass raw HTML through to the preview")
func doesNotPassRawHTMLThroughToThePreview() throws {
        let source = """
        # Safe title

        <script>alert('unsafe')</script>
        <span>raw HTML</span>
        """

        let result = try SwiftMarkdownAdapter().render(
            source: source,
            baseURL: URL(fileURLWithPath: "/tmp/project")
        )

    #expect(result.html.contains("<h1 id=\"safe-title\""))
    #expect(!result.html.contains("<script"))
    #expect(!result.html.contains("<span>raw HTML</span>"))
}

@Test("renders common TeX math as local MathML")
func rendersCommonTeXMathAsLocalMathML() throws {
    let result = try SwiftMarkdownAdapter().render(
        source: "Einstein: $E = mc^2$\n\n$$\\frac{a}{b}$$",
        baseURL: URL(fileURLWithPath: "/tmp/project")
    )

    #expect(result.html.contains("<math"))
    #expect(result.html.contains("<msup>"))
    #expect(result.html.contains("<mfrac>"))
}

@Test("exposes a navigable outline with stable heading IDs")
func exposesNavigableMarkdownOutline() throws {
    let source = """
    # Introduction

    ## Methods

    ```markdown
    # Not a heading
    ```

    ## Methods
    """

    let result = try SwiftMarkdownAdapter().render(
        source: source,
        baseURL: URL(fileURLWithPath: "/tmp/project")
    )

    #expect(result.outline.map(\.title) == ["Introduction", "Methods", "Methods"])
    #expect(result.outline.map(\.level) == [1, 2, 2])
    #expect(result.outline.map(\.id) == ["introduction", "methods", "methods-2"])
    #expect(result.outline.allSatisfy { result.html.contains("id=\"\($0.id)\"") })
}

@Test("produces the normalized absolute path used by copy-path actions")
func producesNormalizedAbsolutePathForCopyActions() {
    let url = URL(fileURLWithPath: "/tmp/project/chapters/../working.md")

    #expect(FilePathCopy.string(for: url) == "/tmp/project/working.md")
}

@Test("recognizes Word documents as supported preview files")
func recognizesWordDocuments() {
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/report.docx")) == .docx)
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/REPORT.DOCX")) == .docx)
    #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/project/report.doc")) == .other)
}

@Test("Markdown editing exposes source and split modes")
func exposesMarkdownEditingModes() {
    #expect(MarkdownEditingMode.allCases == [.markdown, .split])
    #expect(MarkdownEditingMode(rawValue: "visual") == nil)
}
