import BPViewerCore
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

        expect(result.html.contains("<h1 id=\"heading\">Heading</h1>"), "heading")
        expect(result.html.contains("<h1 id=\"heading-2\">Heading</h1>"), "duplicate heading id")
        expect(result.html.contains("<strong>important</strong>"), "strong text")
        expect(result.html.contains("href=\"chapter-2.md\""), "relative link")
        expect(result.html.contains("src=\"images/figure.png\""), "relative image")
        expect(result.dependencies.contains(URL(fileURLWithPath: "/tmp/project/chapter-1/images/figure.png")), "image dependency")
        expect(result.html.contains("Content-Security-Policy"), "content security policy")
        expect(!result.html.contains("<script"), "raw html removed")
        expect(result.html.contains("<math"), "math")
        expect(result.html.contains("<msup>"), "superscript")
        expect(result.html.contains("<mfrac>"), "fraction")
    }

    private static func expect(_ condition: Bool, _ name: String) {
        guard condition else {
            fatalError("Markdown contract failed: \(name)")
        }
        print("PASS \(name)")
    }
}
