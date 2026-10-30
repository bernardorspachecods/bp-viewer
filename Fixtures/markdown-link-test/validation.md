---
bkf: document
description: Describes the manual link navigation fixture and its web, text, and CSV targets, which should open outside a BP Viewer preview tab.
tags: [fixtures, links, validation]
---

# Link navigation validation

[`link-test.md`](/Fixtures/markdown-link-test/link-test.md) checks that the preview distinguishes web links from local files that BP Viewer does not preview. Its two external links, to example.com and Apple documentation, should open in the macOS default browser. Its links to [`plain-text.txt`](/Fixtures/markdown-link-test/plain-text.txt) and [`data.csv`](/Fixtures/markdown-link-test/data.csv) should open in the macOS default app without creating a BP Viewer preview tab; the app should remain open and usable after each click.
