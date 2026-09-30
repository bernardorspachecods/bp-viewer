# Research brief: LaTeX → preview

## Objective

Determine how `bp-viewer` should process local LaTeX documents and provide a useful preview, taking real thesis documents and changes made by external tools into account.

## Main question

Which LaTeX processing and presentation strategies are viable on macOS for the MVP, including their costs, dependencies, limitations, and output quality?

## Research questions

- visually relevant output strategies, including PDF, HTML, or hybrid approaches;
- materially viable engines, compilers, wrappers, and local build tools;
- reliance on MacTeX, TeX Live, MiKTeX, or alternatives, without assuming any is required;
- multi-file documents, `\input`, `\include`, images, bibliographies, and cross-references;
- dependency detection and recompilation after external changes;
- incremental compilation, wait times, and concurrent compilations;
- locating temporary artifacts without cluttering the user's project;
- extracting and displaying compilation errors and warnings;
- incompatible LaTeX packages, cases that require interaction, and execution limits;
- permissions, external processes, licensing, and macOS distribution;
- output fidelity for a thesis and accessibility or search implications in the preview.

## Out of scope

- choosing the desktop framework or final viewer;
- implementing a compiler or build system;
- assuming HTML is necessarily better than PDF, or vice versa;
- researching full-featured LaTeX editors;
- deciding writing or collaboration features.

Clearly identify which parts depend on the viewer and surrounding architecture, and refer detailed analysis to the corresponding briefs.

## Minimum scenarios to evaluate

- a `main.tex` file that includes several chapters;
- a bibliography and cross-references that require multiple passes;
- a missing image or package;
- successive changes to the main file and an included file;
- a compilation that fails or becomes stuck.

## Deliverable

Compare the identified strategies and provide a conditional MVP recommendation, local prerequisites, key risks, and a test plan using representative LaTeX documents.

Use the [shared report format](CONTEXT.md#report-format) and distinguish documented capabilities from suitability inferred for `bp-viewer`.
