# Research brief: Markdown → HTML

## Objective

Determine which approaches are technically viable for converting local Markdown files to HTML rendered inside `bp-viewer`, while preserving automatic updates and a reading experience suited to a thesis.

## Main question

Which Markdown parser and Markdown-to-HTML pipeline offer the best balance of fidelity, extensibility, academic content support, offline operation, security, and complexity for the macOS MVP?

## Research questions

- relevant Markdown variants and compatibility with real documents;
- parser architecture and extension through plugins or transformations;
- mathematics, code blocks, tables, quotations, notes, and references;
- images, relative links, anchors, and cross-file references;
- CSS, themes, and control over generated HTML;
- sanitization and handling of potentially unsafe local content;
- updates after external changes and the cost of rerendering;
- dependencies, offline operation, licensing, and maintenance;
- differences between client-side rendering and prerendering in the local process;
- cases where Markdown cannot meet academic requirements without additional tools.

## Out of scope

- choosing the desktop framework;
- designing the full interface;
- implementing the adapter;
- deciding editing features;
- conducting a generic comparison of every existing parser.

WebView or desktop dependencies may be noted when materially relevant, but refer detailed analysis to the corresponding briefs.

## Minimum scenarios to evaluate

- a Markdown chapter with mathematics and relative images;
- a document with subfolders and links to other files;
- a frequent change made by an external process;
- HTML or Markdown containing content that must not be able to execute arbitrary scripts.

## Deliverable

Compare the identified approaches and provide a conditional MVP recommendation, requirements that could change it, and a short list of local tests needed to validate the choice.

Use the [shared report format](CONTEXT.md#report-format) and do not present a preference as a fact.
