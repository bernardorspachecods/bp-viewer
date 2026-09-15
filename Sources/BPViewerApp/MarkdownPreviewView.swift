import SwiftUI
import WebKit
import BPViewerCore

private enum MarkdownEditingJavaScript {
    static let source = #"""
    (() => {
      const handler = () => window.webkit?.messageHandlers?.bpViewerMarkdownEdit;
      const documentBody = () => document.body;
      const rawEditor = () => document.getElementById('bp-raw-editor');
      const editableRegionForEvent = (event) => event.target?.closest?.('[data-bp-editable="true"]');
      const specialRegionForEvent = (event) => event.target?.closest?.('[data-bp-special-kind]');
      const serializeInline = (node) => {
        if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
        if (node.nodeType !== Node.ELEMENT_NODE) return '';
        const content = Array.from(node.childNodes).map(serializeInline).join('');
        switch (node.tagName) {
          case 'STRONG':
          case 'B': return `**${content}**`;
          case 'EM':
          case 'I': return `*${content}*`;
          case 'DEL':
          case 'S': return `~~${content}~~`;
          case 'CODE': return `\`${node.textContent || ''}\``;
          case 'A': return `[${content}](${node.dataset.bpMarkdownHref || node.getAttribute('href') || ''})`;
          case 'BR': return '\n';
          default: return content;
        }
      };
      const serializeRegion = (element) => {
        if (element.tagName === 'TABLE') {
          const rows = Array.from(element.querySelectorAll('tr')).map((row) =>
            Array.from(row.querySelectorAll(':scope > th, :scope > td'))
              .map((cell) => serializeInline(cell).trim())
          );
          if (rows.length === 0) return '';
          const separator = rows[0].map(() => '---');
          return [rows[0], separator, ...rows.slice(1)]
            .map((row) => `| ${row.join(' | ')} |`)
            .join('\n');
        }
        if (element.tagName === 'UL' || element.tagName === 'OL') {
          return Array.from(element.children)
            .filter((child) => child.tagName === 'LI')
            .map((item) => {
              const checkbox = item.querySelector(':scope > input[data-bp-task-checkbox]');
              const content = Array.from(item.childNodes)
                .filter((child) => child !== checkbox)
                .map(serializeInline)
                .join('');
              return checkbox
                ? `[${checkbox.checked ? 'x' : ' '}] ${content}`
                : content;
            })
            .join('\n');
        }
        if (element.tagName === 'PRE') return element.textContent || '';
        return serializeInline(element);
      };
      const kindForElement = (element) => {
        switch (element.tagName) {
          case 'H1':
          case 'H2':
          case 'H3':
          case 'H4':
          case 'H5':
          case 'H6': return 'heading';
          case 'UL': return 'unorderedList';
          case 'OL': return 'orderedList';
          case 'BLOCKQUOTE': return 'blockquote';
          case 'HR': return 'thematicBreak';
          case 'PRE': return 'codeBlock';
          default: return 'paragraph';
        }
      };
      const visualEntries = () => Array.from(documentBody().children)
        .filter((element) => element.dataset.bpEditable === 'true' && element.dataset.bpBlockId)
        .map((element) => ({
          id: element.dataset.bpBlockId,
          text: serializeRegion(element),
          kind: kindForElement(element)
        }));
      const visualInsertions = () => Array.from(documentBody().children)
        .filter((element) => element.dataset.bpNewBlock === 'thematicBreak')
        .map((element) => ({
          afterID: element.dataset.bpAfterBlockId || null,
          kind: 'thematicBreak'
        }));
      const specialEdits = () => Array.from(document.querySelectorAll('[data-bp-special-replacement]'))
        .map((element) => ({
          id: element.dataset.bpSpecialId,
          kind: element.dataset.bpSpecialKind,
          replacement: element.dataset.bpSpecialReplacement
        }))
        .filter((edit) => edit.id && edit.kind && edit.replacement !== undefined);
      const send = (type, mode, text = '') => {
        handler()?.postMessage({
          type,
          mode,
          text,
          entries: mode === 'visual' ? visualEntries() : [],
          insertions: mode === 'visual' ? visualInsertions() : [],
          specialEdits: mode === 'visual' ? specialEdits() : []
        });
      };
      const placeCaret = (event) => {
        const selection = window.getSelection();
        const range = document.caretRangeFromPoint?.(event.clientX, event.clientY);
        if (!selection || !range) return;
        selection.removeAllRanges();
        selection.addRange(range);
        documentBody().focus();
      };
      const protectUnsupportedRegions = () => {
        Array.from(documentBody().children).forEach((element) => {
          if (element.id !== 'bp-raw-editor') {
            element.contentEditable = element.dataset.bpEditable === 'true' ? 'true' : 'false';
          }
        });
        document.querySelectorAll('input[data-bp-task-checkbox]').forEach((checkbox) => {
          checkbox.disabled = false;
        });
      };
      const setTaskCheckboxesEnabled = (enabled) => {
        document.querySelectorAll('input[data-bp-task-checkbox]').forEach((checkbox) => {
          checkbox.disabled = !enabled;
        });
      };
      const closeSpecialEditor = () => {
        document.querySelector('.bp-special-editor')?.remove();
        document.querySelectorAll('[data-bp-special-replacement]').forEach((element) => {
          delete element.dataset.bpSpecialReplacement;
        });
      };
      const imageMarkdown = (alt, source, title) => {
        const escapedAlt = String(alt || '').replaceAll(']', '\\]');
        const escapedSource = String(source || '').trim();
        const escapedTitle = String(title || '').replaceAll('"', '\\\"');
        return `![${escapedAlt}](${escapedSource}${escapedTitle ? ` "${escapedTitle}"` : ''})`;
      };
      const openImageEditor = (image) => {
        closeSpecialEditor();
        const panel = document.createElement('div');
        panel.className = 'bp-special-editor';
        panel.contentEditable = 'false';
        panel.innerHTML = `
          <strong>Editar imagem</strong>
          <label>Texto alternativo <input data-field="alt" type="text"></label>
          <label>Origem <input data-field="source" type="text"></label>
          <label>Título <input data-field="title" type="text"></label>
          <span><button data-action="cancel">Cancelar</button><button data-action="apply">Aplicar</button></span>
        `;
        panel.querySelector('[data-field="alt"]').value = image.alt || '';
        panel.querySelector('[data-field="source"]').value = image.dataset.bpMarkdownImageSource || '';
        panel.querySelector('[data-field="title"]').value = image.title || '';
        panel.addEventListener('click', (event) => {
          const action = event.target?.dataset?.action;
          if (action === 'cancel') {
            closeSpecialEditor();
            return;
          }
          if (action !== 'apply') return;
          const alt = panel.querySelector('[data-field="alt"]').value;
          const source = panel.querySelector('[data-field="source"]').value;
          const title = panel.querySelector('[data-field="title"]').value;
          image.alt = alt;
          image.title = title;
          image.dataset.bpMarkdownImageSource = source;
          image.dataset.bpSpecialReplacement = imageMarkdown(alt, source, title);
          panel.style.display = 'none';
          send('change', 'visual', '');
        });
        documentBody().append(panel);
        panel.querySelector('[data-field="alt"]').focus();
      };
      const openTextSpecialEditor = (element) => {
        closeSpecialEditor();
        const kind = element.dataset.bpSpecialKind;
        const labels = {
          math: 'Editar fórmula',
          html: 'Editar HTML raw',
          frontMatter: 'Editar front matter'
        };
        const panel = document.createElement('div');
        panel.className = 'bp-special-editor';
        panel.contentEditable = 'false';
        panel.innerHTML = `
          <strong>${labels[kind] || 'Editar conteúdo'}</strong>
          <textarea data-field="source" rows="8"></textarea>
          <span><button data-action="cancel">Cancelar</button><button data-action="apply">Aplicar</button></span>
        `;
        panel.querySelector('[data-field="source"]').value = element.dataset.bpSpecialSource || '';
        panel.addEventListener('click', (event) => {
          const action = event.target?.dataset?.action;
          if (action === 'cancel') {
            closeSpecialEditor();
            return;
          }
          if (action !== 'apply') return;
          element.dataset.bpSpecialReplacement = panel.querySelector('[data-field="source"]').value;
          panel.style.display = 'none';
          send('change', 'visual', '');
        });
        documentBody().append(panel);
        panel.querySelector('[data-field="source"]').focus();
      };
      const escapeHTML = (value) => String(value || '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
      const inlineMarkdownToHTML = (value) => {
        let html = escapeHTML(value);
        html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
        html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        html = html.replace(/__([^_]+)__/g, '<strong>$1</strong>');
        html = html.replace(/~~([^~]+)~~/g, '<del>$1</del>');
        html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
        html = html.replace(/_([^_]+)_/g, '<em>$1</em>');
        html = html.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (match, label, href) => {
          const safeHref = /^(javascript|vbscript|data|file|blob):/i.test(href) ? '' : href;
          return `<a href="${escapeHTML(safeHref)}" data-bp-markdown-href="${escapeHTML(href)}">${label}</a>`;
        });
        return html.replace(/\n/g, '<br>');
      };
      const tableCells = (line) => {
        let value = String(line || '').trim();
        if (value.startsWith('|')) value = value.slice(1);
        if (value.endsWith('|')) value = value.slice(0, -1);
        return value.split('|').map((cell) => cell.trim());
      };
      const applyTableMarkup = (table, value) => {
        const rows = String(value || '')
          .split('\n')
          .filter((line) => line.trim().includes('|'))
          .map(tableCells);
        if (rows.length < 2) return;
        const header = rows[0];
        const body = rows.slice(2);
        table.replaceChildren();
        const thead = document.createElement('thead');
        const headerRow = document.createElement('tr');
        header.forEach((cell) => {
          const element = document.createElement('th');
          element.innerHTML = inlineMarkdownToHTML(cell);
          headerRow.append(element);
        });
        thead.append(headerRow);
        table.append(thead);
        if (body.length > 0) {
          const tbody = document.createElement('tbody');
          body.forEach((row) => {
            const tableRow = document.createElement('tr');
            row.forEach((cell) => {
              const element = document.createElement('td');
              element.innerHTML = inlineMarkdownToHTML(cell);
              tableRow.append(element);
            });
            tbody.append(tableRow);
          });
          table.append(tbody);
        }
      };
      const applyVisualEntries = (entries) => {
        (entries || []).forEach((entry) => {
          const element = document.querySelector(`[data-bp-block-id="${CSS.escape(entry.id)}"]`);
          if (!element) return;
          if (element.tagName === 'UL' || element.tagName === 'OL') {
            element.replaceChildren(...String(entry.text || '').split('\n').map((line) => {
              const item = document.createElement('li');
              const taskMatch = line.match(/^\[([ xX])\]\s+/);
              const content = taskMatch ? line.slice(taskMatch[0].length) : line;
              item.innerHTML = inlineMarkdownToHTML(content);
              if (taskMatch) {
                const checkbox = document.createElement('input');
                checkbox.type = 'checkbox';
                checkbox.dataset.bpTaskCheckbox = 'true';
                checkbox.checked = taskMatch[1].toLowerCase() === 'x';
                item.prepend(document.createTextNode(' '));
                item.prepend(checkbox);
              }
              return item;
            }));
          } else if (element.tagName === 'TABLE') {
            applyTableMarkup(element, entry.text || '');
          } else if (element.tagName === 'PRE') {
            const code = element.querySelector('code');
            if (code) code.textContent = entry.text || '';
          } else {
            element.innerHTML = inlineMarkdownToHTML(entry.text || '');
          }
        });
      };
      const enterVisual = (event) => {
        const body = documentBody();
        body.contentEditable = 'true';
        body.classList.add('bp-document-editing');
        body.classList.remove('bp-raw-mode');
        protectUnsupportedRegions();
        setTaskCheckboxesEnabled(true);
        placeCaret(event);
        send('begin', 'visual', '');
      };
      const enterMarkdown = (text) => {
        closeSpecialEditor();
        const body = documentBody();
        body.contentEditable = 'false';
        body.classList.remove('bp-document-editing');
        body.classList.add('bp-raw-mode');
        setTaskCheckboxesEnabled(false);
        let editor = rawEditor();
        if (!editor) {
          editor = document.createElement('textarea');
          editor.id = 'bp-raw-editor';
          body.prepend(editor);
        }
        editor.value = text;
        editor.focus();
        editor.setSelectionRange(editor.value.length, editor.value.length);
      };
      const finish = () => {
        closeSpecialEditor();
        const editor = rawEditor();
        if (editor) send('end', 'markdown', editor.value);
        else send('end', 'visual', '');
        documentBody().contentEditable = 'false';
        documentBody().classList.remove('bp-document-editing', 'bp-raw-mode');
        setTaskCheckboxesEnabled(false);
        editor?.remove();
      };

      document.addEventListener('dblclick', (event) => {
        if (documentBody().classList.contains('bp-document-editing') || rawEditor()) return;
        const special = specialRegionForEvent(event);
        if (special?.dataset.bpSpecialKind === 'image') {
          event.preventDefault();
          enterVisual(event);
          openImageEditor(special);
          return;
        }
        if (special && ['math', 'html', 'frontMatter'].includes(special.dataset.bpSpecialKind)) {
          event.preventDefault();
          enterVisual(event);
          openTextSpecialEditor(special);
          return;
        }
        if (!editableRegionForEvent(event)) return;
        event.preventDefault();
        enterVisual(event);
      });

      document.addEventListener('input', (event) => {
        const editor = rawEditor();
        if (editor && event.target === editor) {
          send('change', 'markdown', editor.value);
          return;
        }
        if (!documentBody().classList.contains('bp-document-editing')) return;
        send('change', 'visual', '');
      });

      document.addEventListener('change', (event) => {
        if (!documentBody().classList.contains('bp-document-editing')) return;
        if (event.target?.matches?.('input[data-bp-task-checkbox]')) {
          send('change', 'visual', '');
        }
      });

      document.addEventListener('keydown', (event) => {
        if (event.metaKey && !event.shiftKey
            && (event.key.toLowerCase() === 'b' || event.key.toLowerCase() === 'i')
            && documentBody().classList.contains('bp-document-editing')) {
          event.preventDefault();
          document.execCommand(event.key.toLowerCase() === 'b' ? 'bold' : 'italic', false, null);
          return;
        }
        if (event.metaKey && event.key.toLowerCase() === 'z'
            && (documentBody().classList.contains('bp-document-editing') || rawEditor())) {
          event.preventDefault();
          handler()?.postMessage({
            type: event.shiftKey ? 'redo' : 'undo',
            mode: rawEditor() ? 'markdown' : 'visual',
            text: '',
            entries: []
          });
          return;
        }
        if (event.key === 'Escape') {
          if (!documentBody().classList.contains('bp-document-editing') && !rawEditor()) return;
          event.preventDefault();
          finish();
        }
      });

      window.bpViewerSetMarkdownEdit = (mode, text, entries) => {
        if (mode === 'markdown') {
          enterMarkdown(text);
          return;
        }
        const body = documentBody();
        rawEditor()?.remove();
        body.classList.remove('bp-raw-mode');
        body.classList.add('bp-document-editing');
        body.contentEditable = 'true';
        protectUnsupportedRegions();
        setTaskCheckboxesEnabled(true);
        applyVisualEntries(entries);
        body.focus();
      };

      window.bpViewerApplyMarkdownFormatting = (command) => {
        if (!documentBody().classList.contains('bp-document-editing')) return;
        const browserCommand = command === 'bold' ? 'bold' : command === 'italic' ? 'italic' : null;
        if (browserCommand) {
          document.execCommand(browserCommand, false, null);
          return;
        }

        const selection = window.getSelection();
        const region = selection?.anchorNode?.parentElement?.closest?.('[data-bp-editable="true"]');
        if (!region) return;

        if (command === 'quote') {
          const replacementTag = region.tagName === 'BLOCKQUOTE' ? 'P' : 'BLOCKQUOTE';
          const replacement = document.createElement(replacementTag);
          replacement.dataset.bpBlockId = region.dataset.bpBlockId;
          replacement.dataset.bpEditable = 'true';
          replacement.innerHTML = region.tagName === 'BLOCKQUOTE'
            ? (region.querySelector('p')?.innerHTML || region.innerHTML)
            : region.innerHTML;
          region.replaceWith(replacement);
          send('change', 'visual', '');
          return;
        }

        if (command === 'separator') {
          const separator = document.createElement('hr');
          separator.dataset.bpNewBlock = 'thematicBreak';
          separator.dataset.bpAfterBlockId = region.dataset.bpBlockId;
          region.insertAdjacentElement('afterend', separator);
          send('change', 'visual', '');
        }
      };

      window.bpViewerFinishMarkdownEdit = () => {
        if (documentBody().classList.contains('bp-document-editing') || rawEditor()) finish();
      };
    })();
    """#
}

struct MarkdownPreviewView: View {
    let html: String
    let baseURL: URL
    let documentID: String
    let previewRevision: Date?
    let outline: [MarkdownOutlineEntry]
    let editableBlocks: [MarkdownEditableBlock]
    let editingSession: MarkdownEditSession?
    let onNavigate: (URL) -> Void
    let onMarkdownEditEvent: (MarkdownWebEditEvent) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleMarkdownMode: () -> Void
    let onEndMarkdownEditing: () -> Void
    let onKeepLocalMarkdownEdit: () -> Void
    let onUseExternalMarkdownEdit: () -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    @Binding var isOutlineVisible: Bool
    let readingPosition: MarkdownReadingPosition?
    let onReadingPositionChanged: (MarkdownReadingPosition) -> Void
    let isSnapshotCaptureActive: Bool
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void
    @State private var selectedHeadingID: String?
    @State private var outlineRequestID = 0
    @State private var formattingRequestID = 0
    @State private var pendingFormattingCommand: MarkdownFormattingCommand?

    private var outlineItems: [DocumentOutlineItem] {
        outline.map {
            DocumentOutlineItem(
                id: $0.id,
                title: $0.title,
                level: max($0.level - 1, 0),
                isSelectable: true
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !outlineItems.isEmpty {
                DocumentOutlineToolbar(isVisible: isOutlineVisible) {
                    isOutlineVisible.toggle()
                }
            }

            if let editingSession {
                MarkdownEditToolbar(
                    session: editingSession,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onFormattingCommand: { command in
                        pendingFormattingCommand = command
                        formattingRequestID += 1
                    },
                    onToggleMarkdownMode: onToggleMarkdownMode,
                    onEndEditing: onEndMarkdownEditing
                )
                if let conflict = editingSession.conflict {
                    MarkdownConflictView(
                        conflict: conflict,
                        onKeepLocal: onKeepLocalMarkdownEdit,
                        onUseExternal: onUseExternalMarkdownEdit
                    )
                }
            }

            HStack(spacing: 0) {
                if isOutlineVisible {
                    DocumentOutlineSidebar(
                        entries: outlineItems,
                        selectedID: selectedHeadingID
                    ) { item in
                        selectedHeadingID = item.id
                        outlineRequestID += 1
                    }
                    Divider()
                }

                ZStack {
                    MarkdownWebView(
                        html: html,
                        baseURL: baseURL,
                        documentID: documentID,
                        previewRevision: previewRevision,
                        editingSession: editingSession,
                        editingText: editingText,
                        editingEntries: editingEntries,
                        formattingCommand: pendingFormattingCommand,
                        formattingRequestID: formattingRequestID,
                        onNavigate: onNavigate,
                        onMarkdownEditEvent: onMarkdownEditEvent,
                        zoom: zoom,
                        findQuery: findQuery,
                        findRequestID: findRequestID,
                        findBackwards: findBackwards,
                        requestedHeadingID: selectedHeadingID,
                        outlineRequestID: outlineRequestID,
                        readingPosition: readingPosition,
                        onReadingPositionChanged: onReadingPositionChanged
                    )
                    if isSnapshotCaptureActive {
                        SnapshotSelectionOverlay(
                            onCancel: onSnapshotCancel,
                            onCapture: onSnapshotCapture
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .id(documentID)
    }

    private var editingText: String? {
        guard let editingSession, editingSession.isEditing,
              editingSession.mode == .markdown else {
            return nil
        }
        return editingSession.currentSource
    }

    private var editingEntries: [MarkdownVisualEntry] {
        guard let editingSession, editingSession.isEditing, editingSession.mode == .visual else {
            return []
        }
        return editableBlocks
            .filter(\.supportsVisualEditing)
            .map { MarkdownVisualEntry(id: $0.id, text: $0.visualText, kind: $0.kind) }
    }
}

struct MarkdownWebEditEvent {
    enum Kind {
        case begin
        case change
        case end
        case undo
        case redo
    }

    let kind: Kind
    let text: String
    let mode: MarkdownEditingMode
    let visualEntries: [MarkdownVisualEntry]
    let visualInsertions: [MarkdownVisualInsertion]
    let specialEdits: [MarkdownSpecialEdit]
}

private enum MarkdownFormattingCommand: String {
    case bold
    case italic
    case quote
    case separator
}

private struct MarkdownEditToolbar: View {
    let session: MarkdownEditSession
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onFormattingCommand: (MarkdownFormattingCommand) -> Void
    let onToggleMarkdownMode: () -> Void
    let onEndEditing: () -> Void

    var body: some View {
        HStack(spacing: BPTokens.Spacing.sm) {
            Label(
                session.mode == .visual ? "Edição visual" : "Edição Markdown",
                systemImage: session.mode == .visual ? "pencil.line" : "chevron.left.forwardslash.chevron.right"
            )
            .font(BPTokens.Typography.caption.weight(.medium))

            Button(session.mode == .visual ? "Editar como Markdown" : "Voltar à edição visual") {
                onToggleMarkdownMode()
            }
            .buttonStyle(.bordered)

            Button(action: onUndo) {
                Label("Desfazer", systemImage: "arrow.uturn.backward")
            }
            .disabled(session.undoSources.isEmpty)

            Button(action: onRedo) {
                Label("Refazer", systemImage: "arrow.uturn.forward")
            }
            .disabled(session.redoSources.isEmpty)

            if session.mode == .visual {
                Button(action: { onFormattingCommand(.bold) }) {
                    Label("Negrito", systemImage: "bold")
                }

            Button(action: { onFormattingCommand(.italic) }) {
                Label("Itálico", systemImage: "italic")
            }

            Button(action: { onFormattingCommand(.quote) }) {
                Label("Citação", systemImage: "text.quote")
            }

            Button(action: { onFormattingCommand(.separator) }) {
                Label("Separador", systemImage: "line.3.horizontal")
            }
            }

            Spacer()

            Text(session.saveState.label)
                .font(BPTokens.Typography.caption)
                .foregroundStyle(session.saveState == .conflict ? BPTokens.Color.warning : BPTokens.Color.muted)

            Button("Concluir", action: onEndEditing)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
    }
}

private struct MarkdownConflictView: View {
    let conflict: MarkdownConflict
    let onKeepLocal: () -> Void
    let onUseExternal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xs) {
            Text("Este documento também foi alterado fora do bp-viewer.")
                .font(BPTokens.Typography.caption.weight(.medium))
            HStack(spacing: BPTokens.Spacing.sm) {
                conflictColumn(title: "As minhas alterações", source: conflict.localSource)
                conflictColumn(title: "Versão externa", source: conflict.externalSource)
            }
            HStack {
                Spacer()
                Button("Usar versão externa", action: onUseExternal)
                Button("Manter as minhas alterações", action: onKeepLocal)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.sm)
        .background(BPTokens.Color.warning.opacity(0.1))
    }

    private func conflictColumn(title: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: BPTokens.Spacing.xxs) {
            Text(title)
                .font(BPTokens.Typography.caption.weight(.medium))
            ScrollView {
                Text(source)
                    .font(BPTokens.Typography.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BPTokens.Spacing.xs)
            }
            .frame(maxHeight: 100)
            .background(BPTokens.Color.elevated)
            .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.sm))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let documentID: String
    let previewRevision: Date?
    let editingSession: MarkdownEditSession?
    let editingText: String?
    let editingEntries: [MarkdownVisualEntry]
    let formattingCommand: MarkdownFormattingCommand?
    let formattingRequestID: Int
    let onNavigate: (URL) -> Void
    let onMarkdownEditEvent: (MarkdownWebEditEvent) -> Void
    let zoom: Double
    let findQuery: String
    let findRequestID: Int
    let findBackwards: Bool
    let requestedHeadingID: String?
    let outlineRequestID: Int
    let readingPosition: MarkdownReadingPosition?
    let onReadingPositionChanged: (MarkdownReadingPosition) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MarkdownEditingJavaScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: "bpViewerMarkdownEdit")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.observeScroll(in: webView)
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.captureReadingPosition(in: webView)
        coordinator.removeScrollObservation()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.onMarkdownEditEvent = onMarkdownEditEvent
        context.coordinator.onReadingPositionChanged = onReadingPositionChanged
        context.coordinator.observeScroll(in: webView)
        webView.pageZoom = zoom

        if context.coordinator.findRequestID != findRequestID || context.coordinator.findQuery != findQuery {
            context.coordinator.findRequestID = findRequestID
            context.coordinator.findQuery = findQuery
            context.coordinator.findBackwards = findBackwards
            context.coordinator.find(in: webView)
        }

        let documentChanged = context.coordinator.html != html || context.coordinator.baseURL != baseURL
            || context.coordinator.previewRevision != previewRevision
        if documentChanged {
            let isSameDocument = context.coordinator.documentID == documentID
            let currentScrollY = webView.enclosingScrollView.map {
                max(Double($0.contentView.bounds.origin.y), 0)
            }
            let knownPosition = context.coordinator.lastReadingPosition ?? readingPosition
            let currentPosition = currentScrollY.map { scrollY in
                MarkdownReadingPosition(
                    scrollY: scrollY,
                    anchorID: knownPosition?.anchorID,
                    anchorOffset: knownPosition?.anchorOffset ?? 0
                )
            }
            context.coordinator.pendingReadingPosition = isSameDocument
                ? currentPosition ?? knownPosition
                : readingPosition
            context.coordinator.documentID = documentID
            context.coordinator.previewRevision = previewRevision
            context.coordinator.html = html
            context.coordinator.baseURL = baseURL
            context.coordinator.isDocumentLoaded = false
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        context.coordinator.updateEditingState(
            editingSession: editingSession,
            editingText: editingText,
            editingEntries: editingEntries,
            in: webView
        )

        if context.coordinator.outlineRequestID != outlineRequestID {
            context.coordinator.outlineRequestID = outlineRequestID
            context.coordinator.pendingHeadingID = requestedHeadingID
            if !documentChanged {
                context.coordinator.scrollToPendingHeading(in: webView)
            }
        }

        if context.coordinator.formattingRequestID != formattingRequestID,
           let formattingCommand,
           let encodedCommand = try? String(
               data: JSONEncoder().encode(formattingCommand.rawValue),
               encoding: .utf8
           ) {
            context.coordinator.formattingRequestID = formattingRequestID
            webView.evaluateJavaScript(
                "window.bpViewerApplyMarkdownFormatting && window.bpViewerApplyMarkdownFormatting(\(encodedCommand));",
                completionHandler: nil
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var html: String?
        var baseURL: URL?
        var documentID: String?
        var previewRevision: Date?
        var onNavigate: ((URL) -> Void)?
        var onMarkdownEditEvent: ((MarkdownWebEditEvent) -> Void)?
        var onReadingPositionChanged: ((MarkdownReadingPosition) -> Void)?
        var lastReadingPosition: MarkdownReadingPosition?
        var pendingReadingPosition: MarkdownReadingPosition?
        var findQuery = ""
        var findRequestID = 0
        var findBackwards = false
        var outlineRequestID = 0
        var pendingHeadingID: String?
        var isDocumentLoaded = false
        var formattingRequestID = 0
        private var editingMode: MarkdownEditingMode?
        private var editingText: String?
        private var editingEntries: [MarkdownVisualEntry] = []
        private var latestUserText: String?
        private var latestUserEntries: [MarkdownVisualEntry] = []
        private var scrollObserver: ObserverToken?
        private var captureWorkItem: DispatchWorkItem?

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver.value)
            }
        }

        func observeScroll(in webView: WKWebView) {
            guard scrollObserver == nil, let scrollView = webView.enclosingScrollView else { return }
            let contentView = scrollView.contentView
            contentView.postsBoundsChangedNotifications = true
            scrollObserver = ObserverToken(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self, weak webView] _ in
                Task { @MainActor [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.scheduleCapture(of: webView)
                }
            })
        }

        func removeScrollObservation() {
            guard let scrollObserver else { return }
            NotificationCenter.default.removeObserver(scrollObserver.value)
            self.scrollObserver = nil
        }

        func scheduleCapture(of webView: WKWebView) {
            captureWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.captureReadingPosition(in: webView)
            }
            captureWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        func captureReadingPosition(in webView: WKWebView) {
            guard isDocumentLoaded else { return }
            webView.evaluateJavaScript(
                """
                (() => {
                    const scrollY = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
                    const headings = Array.from(document.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]'));
                    const anchor = headings.find((element) => element.getBoundingClientRect().bottom >= 0) || headings.at(-1);
                    return {
                        scrollY,
                        anchorID: anchor ? anchor.id : null,
                        anchorOffset: anchor ? anchor.getBoundingClientRect().top : 0
                    };
                })()
                """,
                completionHandler: { [weak self] result, _ in
                    guard let self,
                          let payload = result as? [String: Any] else { return }
                    let scrollY = (payload["scrollY"] as? NSNumber)?.doubleValue ?? 0
                    let anchorOffset = (payload["anchorOffset"] as? NSNumber)?.doubleValue ?? 0
                    let position = MarkdownReadingPosition(
                        scrollY: max(scrollY, 0),
                        anchorID: payload["anchorID"] as? String,
                        anchorOffset: anchorOffset
                    )
                    guard self.lastReadingPosition != position else { return }
                    self.lastReadingPosition = position
                    self.onReadingPositionChanged?(position)
                }
            )
        }

        private final class ObserverToken: @unchecked Sendable {
            let value: NSObjectProtocol

            init(_ value: NSObjectProtocol) {
                self.value = value
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isDocumentLoaded = true
            if let pendingReadingPosition {
                restoreReadingPosition(pendingReadingPosition, in: webView)
                self.pendingReadingPosition = nil
            }
            scrollToPendingHeading(in: webView)
            find(in: webView)
            updateEditingState(
                editingSession: currentEditingSession,
                editingText: editingText,
                editingEntries: editingEntries,
                in: webView,
                force: true
            )
            scheduleCapture(of: webView)
        }

        private var currentEditingSession: MarkdownEditSession? {
            guard let editingMode else { return nil }
            return MarkdownEditSession(
                mode: editingMode,
                isEditing: true,
                baseSource: "",
                currentSource: ""
            )
        }

        func updateEditingState(
            editingSession: MarkdownEditSession?,
            editingText: String?,
            editingEntries: [MarkdownVisualEntry],
            in webView: WKWebView,
            force: Bool = false
        ) {
            let activeSession = editingSession?.isEditing == true ? editingSession : nil
            let nextMode = activeSession?.mode
            let modeChanged = force || editingMode != nextMode
            let textChangedOutsideWebView = editingText != nil
                && editingText != latestUserText
            let entriesChangedOutsideWebView = editingEntries != latestUserEntries

            self.editingText = editingText
            self.editingEntries = editingEntries
            guard isDocumentLoaded else {
                editingMode = nextMode
                return
            }

            if activeSession == nil {
                guard editingMode != nil else { return }
                webView.evaluateJavaScript("window.bpViewerFinishMarkdownEdit && window.bpViewerFinishMarkdownEdit();", completionHandler: nil)
                editingMode = nil
                latestUserText = nil
                latestUserEntries.removeAll()
                return
            }

            guard modeChanged || textChangedOutsideWebView || entriesChangedOutsideWebView,
                  let nextMode,
                  let encodedMode = try? String(data: JSONEncoder().encode(nextMode.rawValue), encoding: .utf8),
                  let encodedText = try? String(data: JSONEncoder().encode(editingText ?? ""), encoding: .utf8),
                  let encodedEntries = try? String(data: JSONEncoder().encode(editingEntries), encoding: .utf8) else {
                return
            }

            let script = "window.bpViewerSetMarkdownEdit && window.bpViewerSetMarkdownEdit(\(encodedMode), \(encodedText), \(encodedEntries));"
            webView.evaluateJavaScript(script, completionHandler: nil)
            self.editingMode = nextMode
            self.latestUserText = editingText
            self.latestUserEntries = editingEntries
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bpViewerMarkdownEdit",
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String,
                  let text = payload["text"] as? String else { return }

            let mode = MarkdownEditingMode(rawValue: payload["mode"] as? String ?? "visual") ?? .visual
            let visualEntries = (payload["entries"] as? [[String: Any]] ?? []).compactMap { entry -> MarkdownVisualEntry? in
                guard let id = entry["id"] as? String,
                      let text = entry["text"] as? String else { return nil }
                let kind = (entry["kind"] as? String).flatMap(MarkdownBlockKind.init(rawValue:))
                return MarkdownVisualEntry(id: id, text: text, kind: kind)
            }
            let visualInsertions = (payload["insertions"] as? [[String: Any]] ?? []).compactMap { insertion -> MarkdownVisualInsertion? in
                guard let kindValue = insertion["kind"] as? String,
                      let kind = MarkdownBlockKind(rawValue: kindValue) else { return nil }
                return MarkdownVisualInsertion(
                    afterID: insertion["afterID"] as? String,
                    kind: kind
                )
            }
            let specialEdits = (payload["specialEdits"] as? [[String: Any]] ?? []).compactMap { edit -> MarkdownSpecialEdit? in
                guard let id = edit["id"] as? String,
                      let kindValue = edit["kind"] as? String,
                      let kind = MarkdownSpecialKind(rawValue: kindValue),
                      let replacement = edit["replacement"] as? String else { return nil }
                return MarkdownSpecialEdit(id: id, kind: kind, replacement: replacement)
            }
            let kind: MarkdownWebEditEvent.Kind
            switch type {
            case "begin": kind = .begin
            case "change": kind = .change
            case "end": kind = .end
            case "undo": kind = .undo
            case "redo": kind = .redo
            default: return
            }
            if type == "begin" || type == "change" || type == "end" {
                latestUserText = text
                latestUserEntries = visualEntries
            }
            onMarkdownEditEvent?(MarkdownWebEditEvent(
                kind: kind,
                text: text,
                mode: mode,
                visualEntries: visualEntries,
                visualInsertions: visualInsertions,
                specialEdits: specialEdits
            ))
        }

        func restoreReadingPosition(_ position: MarkdownReadingPosition, in webView: WKWebView) {
            guard let encodedID = try? String(
                data: JSONEncoder().encode(position.anchorID),
                encoding: .utf8
            ),
            let scrollY = String(position.scrollY).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let anchorOffset = String(position.anchorOffset).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return
            }

            let script = """
            (() => {
                const fallback = \(scrollY);
                const anchor = \(encodedID) ? document.getElementById(\(encodedID)) : null;
                if (!anchor) {
                    window.scrollTo(0, fallback);
                    return;
                }
                const desiredTop = window.scrollY + anchor.getBoundingClientRect().top - \(anchorOffset);
                window.scrollTo(0, Math.max(0, desiredTop));
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func scrollToPendingHeading(in webView: WKWebView) {
            guard isDocumentLoaded, let pendingHeadingID,
                  let encodedID = try? String(data: JSONEncoder().encode(pendingHeadingID), encoding: .utf8) else {
                return
            }

            let script = "document.getElementById(\(encodedID))?.scrollIntoView({ block: 'start', behavior: 'smooth' });"
            webView.evaluateJavaScript(script, completionHandler: nil)
            self.pendingHeadingID = nil
        }

        func find(in webView: WKWebView) {
            guard !findQuery.isEmpty else { return }
            let configuration = WKFindConfiguration()
            configuration.backwards = findBackwards
            configuration.caseSensitive = false
            configuration.wraps = true
            webView.find(findQuery, configuration: configuration) { _ in }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let requestedURL = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let currentBaseURL = baseURL

            let resolvedURL: URL
            if requestedURL.scheme == nil,
               let currentBaseURL,
               let relativeURL = URL(string: requestedURL.absoluteString, relativeTo: currentBaseURL)?.absoluteURL {
                resolvedURL = relativeURL
            } else {
                resolvedURL = requestedURL
            }

            let isLocalFileNavigation = resolvedURL.isFileURL
                && !resolvedURL.hasDirectoryPath
                && resolvedURL != webView.url
            let isAppPreviewNavigation = resolvedURL.scheme?.lowercased() == MarkdownPreviewLink.scheme
            guard navigationAction.navigationType == .linkActivated
                    || isLocalFileNavigation
                    || isAppPreviewNavigation else {
                decisionHandler(.allow)
                return
            }

            onNavigate?(resolvedURL)
            decisionHandler(.cancel)
        }
    }
}
