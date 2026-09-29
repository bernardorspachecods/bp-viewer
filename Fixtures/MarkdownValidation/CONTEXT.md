# `MarkdownValidation` context

This fixture covers rendering a local SVG image, common TeX notation, and a remote image.

- Open `01-local-and-math.md` in the app to validate `images/local-diagram.svg`, inline formulas, and display formulas.
- Open `02-remote-image.md` with an internet connection to validate the remote resource. Offline, a missing image is an environmental result.
- Change `images/local-diagram.svg` to verify updates triggered by a local dependency.

The historical record and limitations of this fixture are documented in [`docs/reference/markdown-fixtures.md`](../../docs/reference/markdown-fixtures.md).
