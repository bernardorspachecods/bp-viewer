import Foundation

public struct CSVDocument: Hashable, Sendable {
    public let rows: [[String]]
    public let delimiter: Character

    public init(rows: [[String]], delimiter: Character) {
        self.rows = rows
        self.delimiter = delimiter
    }

    public var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    public func replacingCell(atRow row: Int, column: Int, with value: String) -> CSVDocument? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else {
            return nil
        }
        var updatedRows = rows
        updatedRows[row][column] = value
        return CSVDocument(rows: updatedRows, delimiter: delimiter)
    }
}

public enum CSVPreviewError: LocalizedError, Hashable, Sendable {
    case unterminatedQuotedField

    public var errorDescription: String? {
        switch self {
        case .unterminatedQuotedField:
            "The CSV file contains an unterminated quoted field."
        }
    }
}

public struct CSVPreviewAdapter: Sendable {
    public init() {}

    public func parse(source: String) throws -> CSVDocument {
        let delimiter = detectDelimiter(in: source)
        let characters = Array(source)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var hasRecordContent = false
        var index = 0

        func finishRow() {
            row.append(field)
            rows.append(row)
            row.removeAll(keepingCapacity: true)
            field.removeAll(keepingCapacity: true)
            hasRecordContent = false
        }

        while index < characters.count {
            let character = characters[index]

            if isQuoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                    } else {
                        isQuoted = false
                        index += 1
                    }
                } else {
                    field.append(character)
                    index += 1
                }
                continue
            }

            if character == "\"", field.isEmpty {
                isQuoted = true
                hasRecordContent = true
                index += 1
            } else if character == delimiter {
                row.append(field)
                field.removeAll(keepingCapacity: true)
                hasRecordContent = true
                index += 1
            } else if character == "\r" || character == "\n" || character == "\r\n" {
                finishRow()
                index += 1
            } else {
                field.append(character)
                hasRecordContent = true
                index += 1
            }
        }

        guard !isQuoted else { throw CSVPreviewError.unterminatedQuotedField }

        if hasRecordContent || !row.isEmpty || !field.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return CSVDocument(rows: rows, delimiter: delimiter)
    }

    public func serialize(document: CSVDocument) -> String {
        document.rows.map { row in
            row.map { field in
                serializeField(field, delimiter: document.delimiter)
            }.joined(separator: String(document.delimiter))
        }.joined(separator: "\n")
    }

    public func html(document: CSVDocument, isDark: Bool) -> String {
        guard !document.rows.isEmpty else {
            return """
            <!doctype html>
            <html><head><meta charset="utf-8"><style>
            :root { color-scheme: \(isDark ? "dark" : "light"); }
            html, body { margin: 0; min-height: 100%; background: transparent; color: \(isDark ? "#f2f2f7" : "#1c1c1e"); }
            body { padding: 48px; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
            </style></head><body><p>No rows in this CSV file.</p></body></html>
            """
        }

        let palette = isDark
            ? (foreground: "#f2f2f7", border: "#48484a", header: "#2c2c2e", selection: "#0a84ff")
            : (foreground: "#1c1c1e", border: "#d1d1d6", header: "#e9e9eb", selection: "#007aff")
        let columnCount = document.columnCount
        let columnHeaderCells = (0..<columnCount).map { index in
            "<div class=\"coordinate-header column-label\" role=\"columnheader\" data-column-header=\"\(spreadsheetColumnLabel(for: index))\" style=\"grid-column: \(index + 2); grid-row: 1;\">\(spreadsheetColumnLabel(for: index))</div>"
        }.joined()
        let body = document.rows.enumerated().map { offset, row in
            let cells = (0..<columnCount).map { index in
                let tabIndex = offset == 0 && index == 0 ? 0 : -1
                return "<div class=\"cell\" role=\"gridcell\" data-cell data-row-index=\"\(offset)\" data-column-index=\"\(index)\" tabindex=\"\(tabIndex)\" aria-selected=\"false\" style=\"grid-column: \(index + 2); grid-row: \(offset + 2);\">\(escapeHTML(row[safe: index] ?? ""))</div>"
            }.joined()
            let rowLabel = "<div class=\"coordinate-header row-label\" role=\"rowheader\" data-row-header=\"\(offset + 1)\" style=\"grid-column: 1; grid-row: \(offset + 2);\">\(offset + 1)</div>"
            return rowLabel + cells
        }.joined()

        return """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              :root { color-scheme: \(isDark ? "dark" : "light"); }
              html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; color: \(palette.foreground); }
              body { padding: 28px 32px 48px; box-sizing: border-box; font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
              .table-wrap { width: 100%; height: 100%; overflow: auto; }
              .sheet { display: grid; grid-template-columns: 42px repeat(\(columnCount), minmax(72px, max-content)); grid-auto-rows: minmax(26px, max-content); align-items: stretch; min-width: 100%; width: max-content; background: transparent; }
              .sheet > div { box-sizing: border-box; }
              .coordinate-header { background-color: \(palette.header) !important; border: 1px solid \(palette.border); color: \(palette.foreground); padding: 4px 8px; min-height: 26px; box-sizing: border-box; font-weight: 600; text-align: center; }
              .column-label { position: sticky; top: 0; z-index: 3; }
              .corner { position: sticky; top: 0; left: 0; z-index: 4; min-width: 42px; }
              .row-label { position: sticky; left: 0; z-index: 2; min-width: 42px; width: 42px; }
              .cell { color: \(palette.foreground); border-right: 1px solid \(palette.border); border-bottom: 1px solid \(palette.border); padding: 9px 12px; min-width: 72px; max-width: 420px; white-space: pre-wrap; overflow-wrap: anywhere; text-align: left; vertical-align: top; outline: none; }
              .cell.editing { background: \(isDark ? "#1c1c1e" : "#ffffff"); }
              .cell.selected { box-shadow: inset 0 0 0 2px \(palette.selection); }
              .cell:focus { outline: none; }
            </style>
          </head>
          <body>
            <div class="table-wrap">
              <div class="sheet" data-bp-csv role="grid" aria-label="CSV spreadsheet" aria-rowcount="\(document.rows.count)" aria-colcount="\(columnCount)">
                <div class="coordinate-header corner" aria-hidden="true" style="grid-column: 1; grid-row: 1;"></div>
                \(columnHeaderCells)
                \(body)
              </div>
            </div>
            <script>
              (() => {
                const table = document.querySelector('[data-bp-csv]');
                if (!table) return;

                const cells = Array.from(table.querySelectorAll('[data-cell]'));
                const columnHeaders = Array.from(table.querySelectorAll('[data-column-header]'));
                const rowHeaders = Array.from(table.querySelectorAll('[data-row-header]'));
                const rowCount = rowHeaders.length;
                const columnCount = columnHeaders.length;
                const viewport = table.closest('.table-wrap');
                let hasActiveSelection = false;
                let editingCell = null;
                let editingValue = '';

                function revealCell(cell) {
                  if (!viewport || !cell) return;
                  const viewportRect = viewport.getBoundingClientRect();
                  const cellRect = cell.getBoundingClientRect();
                  const gutterWidth = rowHeaders[0]?.getBoundingClientRect().width ?? 42;
                  const headerHeight = columnHeaders[0]?.getBoundingClientRect().height ?? 26;
                  const visibleLeft = viewportRect.left + gutterWidth;
                  const visibleTop = viewportRect.top + headerHeight;

                  if (cellRect.left < visibleLeft) {
                    viewport.scrollLeft -= visibleLeft - cellRect.left;
                  } else if (cellRect.right > viewportRect.right) {
                    viewport.scrollLeft += cellRect.right - viewportRect.right;
                  }
                  if (cellRect.top < visibleTop) {
                    viewport.scrollTop -= visibleTop - cellRect.top;
                  } else if (cellRect.bottom > viewportRect.bottom) {
                    viewport.scrollTop += cellRect.bottom - viewportRect.bottom;
                  }
                }

                function markSelection(cell, shouldFocus) {
                  if (!cell) return;
                  hasActiveSelection = true;
                  const row = Number(cell.dataset.rowIndex);
                  cells.forEach(candidate => {
                    const selected = candidate === cell;
                    candidate.classList.toggle('selected', selected);
                    candidate.setAttribute('aria-selected', String(selected));
                    candidate.tabIndex = selected ? 0 : -1;
                  });
                  if (shouldFocus) {
                    cell.focus({ preventScroll: true });
                    revealCell(cell);
                  }
                }

                function cellAt(row, column) {
                  return table.querySelector(`[data-row-index="${row}"][data-column-index="${column}"]`);
                }

                function selectCellText(cell) {
                  const selection = window.getSelection();
                  const range = document.createRange();
                  range.selectNodeContents(cell);
                  selection.removeAllRanges();
                  selection.addRange(range);
                }

                function beginCellEditing(cell) {
                  if (editingCell && editingCell !== cell) commitCellEditing();
                  markSelection(cell, true);
                  editingCell = cell;
                  editingValue = cell.textContent || '';
                  cell.contentEditable = 'true';
                  cell.classList.add('editing');
                  cell.focus({ preventScroll: true });
                  selectCellText(cell);
                }

                function finishCellEditing(cell) {
                  cell.contentEditable = 'false';
                  cell.classList.remove('editing');
                }

                function commitCellEditing() {
                  if (!editingCell) return;
                  const cell = editingCell;
                  const value = cell.textContent || '';
                  finishCellEditing(cell);
                  editingCell = null;
                  if (value !== editingValue) {
                    window.webkit.messageHandlers.csvEdit.postMessage({
                      type: 'cellChanged',
                      row: Number(cell.dataset.rowIndex),
                      column: Number(cell.dataset.columnIndex),
                      value
                    });
                  }
                }

                document.addEventListener('keydown', event => {
                  if (event.key !== 'Escape' || editingCell) return;
                  event.preventDefault();
                  event.stopPropagation();
                  window.webkit.messageHandlers.csvEdit.postMessage({ type: 'save' });
                });

                function moveTo(row, column) {
                  const nextRow = Math.max(0, Math.min(rowCount - 1, row));
                  const nextColumn = Math.max(0, Math.min(columnCount - 1, column));
                  markSelection(cellAt(nextRow, nextColumn), true);
                }

                cells.forEach(cell => {
                  cell.addEventListener('click', () => markSelection(cell, true));
                  cell.addEventListener('dblclick', event => {
                    event.preventDefault();
                    beginCellEditing(cell);
                  });
                  cell.addEventListener('focus', () => {
                    if (hasActiveSelection) markSelection(cell, false);
                  });
                  cell.addEventListener('blur', () => {
                    if (editingCell === cell) commitCellEditing();
                  });
                  cell.addEventListener('keydown', event => {
                    if (editingCell !== cell) {
                      if (event.key === 'Enter') {
                        event.preventDefault();
                        event.stopPropagation();
                        beginCellEditing(cell);
                      }
                      return;
                    }
                    if (event.key === 'Enter') {
                      event.preventDefault();
                      event.stopPropagation();
                      commitCellEditing();
            } else if (event.key === 'Escape') {
              event.preventDefault();
              event.stopPropagation();
              commitCellEditing();
            }
                  });
                });

                table.addEventListener('keydown', event => {
                  if (editingCell) return;
                  const cell = event.target.closest('[data-cell]');
                  if (!cell || event.metaKey || event.ctrlKey || event.altKey) return;
                  let row = Number(cell.dataset.rowIndex);
                  let column = Number(cell.dataset.columnIndex);
                  let handled = true;

                  if (event.key === 'ArrowRight') column += 1;
                  else if (event.key === 'ArrowLeft') column -= 1;
                  else if (event.key === 'ArrowDown') row += 1;
                  else if (event.key === 'ArrowUp') row -= 1;
                  else if (event.key === 'Tab') {
                    column += event.shiftKey ? -1 : 1;
                    if (column >= columnCount) {
                      column = 0;
                      row += 1;
                    } else if (column < 0) {
                      column = columnCount - 1;
                      row -= 1;
                    }
                  } else if (event.key === 'Enter') {
                    row += event.shiftKey ? -1 : 1;
                  } else if (event.key === 'Home') column = 0;
                  else if (event.key === 'End') column = columnCount - 1;
                  else handled = false;

                  if (!handled) return;
                  event.preventDefault();
                  moveTo(row, column);
                });
              })();
            </script>
          </body>
        </html>
        """
    }

    private func spreadsheetColumnLabel(for index: Int) -> String {
        var value = index + 1
        var label = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            label.insert(Character(UnicodeScalar(65 + remainder)!), at: label.startIndex)
            value = (value - 1) / 26
        }
        return label
    }

    private func detectDelimiter(in source: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        let firstLine = source.split(whereSeparator: {
            $0 == "\n" || $0 == "\r" || $0 == "\r\n"
        }).first.map(String.init) ?? source
        let counts = candidates.map { delimiter in
            (delimiter, firstLine.reduce(into: 0) { count, character in
                if character == delimiter { count += 1 }
            })
        }
        return counts.max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? ","
    }

    private func serializeField(_ field: String, delimiter: Character) -> String {
        let requiresQuotes = field.contains(delimiter)
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard requiresQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
