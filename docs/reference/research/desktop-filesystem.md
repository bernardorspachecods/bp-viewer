# Research brief: desktop and filesystem

## Objective

Determine the minimum architecture for a macOS desktop app that browses local folders, watches for changes, and coordinates rendering adapters without editing source files.

## Main question

Which desktop shell and filesystem integration options provide the simplest, most reliable workflow for personal use of `bp-viewer`, while leaving adapter choices open?

## Research questions

- desktop app options suitable for macOS and their operational costs;
- folder access, directory selection, hierarchical navigation, and permissions;
- file watching APIs or libraries and their behavior on renames, removals, atomic writes, and rapid changes;
- debouncing, render queues, cancellation, and race condition prevention;
- discovery of dependencies related to the viewed file;
- execution and supervision of external processes;
- communication between the shell, adapter, and preview surface;
- memory use, startup, packaging, and maintenance;
- file associations, drag and drop, and opening a folder, only where relevant to the MVP;
- macOS-specific limitations and the cost of persistent permissions.

## Out of scope

- choosing the Markdown parser or LaTeX strategy;
- conducting a detailed security analysis of WebViews and PDFs;
- creating the app or a prototype;
- supporting Windows or Linux in the MVP;
- completely replacing Finder or building a general-purpose file manager.

Concrete technologies may be compared, but start with requirements rather than a framework preference.

## Minimum scenarios to evaluate

- opening a folder with subfolders and many files;
- an LLM replacing a file through an atomic write;
- several successive changes while a compilation is in progress;
- changing an included file without changing the open file;
- losing and restoring access permissions for a folder.

## Deliverable

Compare shell and local integration options; provide a conditional MVP recommendation, the contracts needed between components, and filesystem tests to run before finalizing the architecture.

Use the [shared report format](CONTEXT.md#formato-de-entrega). Refer detailed security and distribution topics to their dedicated brief to avoid duplication.
