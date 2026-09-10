import Testing
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

    #expect(result.html.contains("<h1 id=\"heading\">Heading</h1>"))
    #expect(result.html.contains("<strong>important</strong>"))
    #expect(result.html.contains("href=\"chapter-2.md\""))
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

    #expect(result.html.contains("<h1 id=\"safe-title\">Safe title</h1>"))
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
