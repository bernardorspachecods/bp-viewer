# PROVISIONAL — Markdown fixtures for images and formulas

Status: `validated_by_manual_test`

> This is a historical validation record, not a source of current behavior.

## Objective

Create one or two realistic Markdown fixtures so the primary agent can manually
validate local/remote images and common formula rendering in `bp-viewer` before
the LaTeX phase.

## Scope

- Markdown fixtures only;
- a local image asset and references using realistic relative paths;
- inline and display formulas covering common TeX constructs;
- a remote image case;
- concise instructions for opening and checking the fixtures in the app.

## Work performed

- Read `docs/current-state.md` and `docs/technical/architecture.md`.
- Inspected `Sources/BPViewerCore/MarkdownAdapter.swift` and
  `Sources/BPViewerCore/MathMLRenderer.swift`.
- Created two Markdown fixtures and one local SVG asset. No production files
  were changed.

## Files

- `Fixtures/MarkdownValidation/01-local-and-math.md`
- `Fixtures/MarkdownValidation/02-remote-image.md`
- `Fixtures/MarkdownValidation/images/local-diagram.svg`

## Manual validation

1. Start the app with `swift run BPViewer`.
2. Select the repository folder as the root, then open
   `Fixtures/MarkdownValidation/01-local-and-math.md`.
3. Confirm that the blue `LOCAL SVG` diagram appears, and that it has loaded
   from the relative path `images/local-diagram.svg`.
4. Confirm the inline expressions render as MathML rather than literal dollar
   delimiters: `E = mc²`, `1/2`, and the Greek/index expression.
5. Confirm both display equations render as centred/block mathematics: the
   quadratic formula and the summation with limits.
6. Open `02-remote-image.md` and, with internet available, confirm the remote
   placeholder image appears. If offline or the service is unavailable, record
   the missing image but confirm the Markdown text still renders.
7. If desired, edit or replace `images/local-diagram.svg` externally and
   confirm the open preview refreshes; this checks the local image dependency.

## Coverage and limitations

- The local image is a relative SVG and should be included in the adapter's
  local dependency list. The remote URL should render in the WebView but is not
  a local watcher dependency.
- The formulas intentionally cover only the common renderer surface currently
  implemented: `frac`, `sqrt`, subscript, superscript, Greek symbols and basic
  operators.
- This does not validate arbitrary LaTeX macros, environments, alignment,
  labels/references, custom commands or the future LaTeX/PDF adapter.
- The remote fixture depends on an external placeholder service and may fail
  independently of the app. A failure should be recorded separately from a
  local image or math failure.

## Primary validation outcome

The first manual preview showed the WebKit broken-image placeholder for the
local SVG, while the formulas and remote image rendered correctly. Normalizing
the directory base URL with a trailing slash did not fix the problem: the
remaining issue is that `WKWebView.loadHTMLString` does not reliably read local
relative resources from an in-memory document.

The adapter now embeds existing local images as `data:` URLs while retaining
their filesystem paths as dependencies for the watcher.

Bernardo confirmed visually that `local-diagram.svg` now renders correctly in
the app. The formulas in the same fixture also render correctly.

## Evidence

- `git diff --check`: passed.
- The fixtures were opened in the app and the local SVG and common formulas
  were confirmed visually; the remote-image result remains dependent on the
  network.
