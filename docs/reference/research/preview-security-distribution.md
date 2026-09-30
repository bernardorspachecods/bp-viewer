# Research brief: preview, security, and distribution

## Objective

Determine how to display HTML and LaTeX output locally and reduce operational risk and friction when running the app on macOS.

## Main question

Which combination of preview surfaces, isolation, permissions, and packaging allows local content to be viewed with sufficient security and a simple experience for personal use?

## Research questions

- WebViews and equivalent surfaces for local HTML;
- PDF viewing and its relevant reading capabilities;
- content isolation, JavaScript execution, navigation, links, and local file access;
- sanitization and defense in depth for Markdown and HTML generated or changed externally;
- risks of opening images, links, PDFs, bibliographies, and other local artifacts;
- running compilers and helper processes with appropriate limits, working directories, and permissions;
- macOS sandboxing, entitlements, file permissions, and persistent access;
- signing, notarization, distribution, and updates for a personal app;
- licensing and packaging implications for preview dependencies;
- error messages and recovery when content or a dependency is unsafe or cannot be opened.

## Out of scope

- creating a complete threat model for public distribution;
- choosing the Markdown parser or LaTeX compiler;
- implementing authentication, cloud services, or collaboration;
- optimizing for operating systems other than macOS;
- assuming personal use eliminates all risks of running local content.

Distinguish theoretical risks, plausible risks in the MVP workflow, and requirements for distribution beyond the user's computer.

## Minimum scenarios to evaluate

- a Markdown file contains embedded HTML or JavaScript;
- a document references images and files outside the open folder;
- a PDF or link points to unexpected content;
- a compiler receives a project with problematic commands or packages;
- the app is opened for the first time on macOS with restricted permissions.

## Deliverable

Compare preview options and isolation measures, and provide a conditional recommendation for the personal MVP, distribution requirements, and a list of risks to explicitly accept, mitigate, or defer.

Use the [shared report format](CONTEXT.md#report-format). Do not call an option “secure” without defining the threat model and evidence supporting the claim.
