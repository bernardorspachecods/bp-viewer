---
bkf: document
description: Manual checks for the Markdown preview's local and remote images, common TeX mathematics, and local image updates; the fixture files are test inputs.
tags: [fixtures, markdown, validation]
---

# Markdown preview validation

This fixture covers rendering a local SVG image, common TeX notation, and a remote image.

- Start the app with `swift run BPViewer`.
- Select the repository folder as the root, then open [`01-local-and-math.md`](/Fixtures/MarkdownValidation/01-local-and-math.md).
- Confirm that the blue `LOCAL SVG` diagram appears, and that it has loaded from the relative path `images/local-diagram.svg`.
- Confirm the inline expressions render as MathML rather than literal dollar delimiters: `E = mc²`, `1/2`, and the Greek/index expression.
- Confirm both display equations render as centred/block mathematics: the quadratic formula and the summation with limits.
- Open [`02-remote-image.md`](/Fixtures/MarkdownValidation/02-remote-image.md) and, with internet available, confirm the remote placeholder image appears. If offline or the service is unavailable, record the missing image but confirm the Markdown text still renders.
- If desired, edit or replace [`local-diagram.svg`](/Fixtures/MarkdownValidation/images/local-diagram.svg) externally and confirm the open preview refreshes; this checks the local image dependency.

The history, test coverage limits, and previously observed results for this fixture are in [`markdown-fixtures.md`](/docs/reference/markdown-fixtures.md).
