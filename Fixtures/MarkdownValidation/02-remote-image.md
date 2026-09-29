# Markdown validation: remote image

This fixture verifies that the preview retains and attempts to load a remote
image when an internet connection is available.

![Remote test image](https://placehold.co/640x160/png?text=bp-viewer+remote "Remote image")

## Expected result

With an internet connection, the remote image should appear. Without one, the
browser may show a missing image; this should not prevent the rest of the
Markdown from being displayed.

This URL is not a local dependency monitored by the app's watcher.
