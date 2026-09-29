# Markdown link test

Use this page to confirm that the app distinguishes web links from local files
that are not previewed by BP Viewer.

## Links externos

- [Abrir example.com](https://example.com)
- [Open Apple documentation](https://developer.apple.com/documentation/webkit)

Both should open in the macOS default browser.

## Unsupported local files

- [Open text file](plain-text.txt)
- [Open CSV](data.csv)

These should open in the macOS default app without creating a preview tab in
BP Viewer.

## Checklist

- [x] The external link opens in the browser.
- [x] The second external link opens in the browser.
- [x] The `.txt` file opens in the default app.
- [x] The `.csv` file opens in the default app.
- [x] The app remains open and usable after each click.
