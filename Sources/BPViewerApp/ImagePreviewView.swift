import AppKit
import SwiftUI

struct ImagePreviewView: View {
    let data: Data
    let zoom: Double
    let previewRevision: Date?
    let isSnapshotCaptureActive: Bool
    let onSnapshot: (() -> Void)?
    let onSnapshotCancel: () -> Void
    let onSnapshotCapture: (NSImage) -> Void
    let onZoomChanged: (Double) -> Void

    @State private var image: NSImage?
    @State private var magnifiedZoom: Double?

    var body: some View {
        VStack(spacing: 0) {
            imageToolbar
            Divider()

            ZStack {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        imageCanvas(in: geometry.size)
                    }
                    .background(BPTokens.Color.canvas)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                magnifiedZoom = clampedZoom(zoom * Double(value))
                            }
                            .onEnded { value in
                                onZoomChanged(clampedZoom(zoom * Double(value)))
                                magnifiedZoom = nil
                            }
                    )
                }

                if isSnapshotCaptureActive {
                    SnapshotSelectionOverlay(
                        onCancel: onSnapshotCancel,
                        onCapture: onSnapshotCapture
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(BPTokens.Color.canvas)
        .onAppear(perform: loadImage)
        .onChange(of: data) { _, _ in loadImage() }
        .onChange(of: zoom) { _, _ in magnifiedZoom = nil }
        .id(previewRevision)
    }

    private var imageToolbar: some View {
        HStack {
            Label("Image", systemImage: "photo")
                .font(BPTokens.Typography.caption.weight(.medium))
            Spacer()
            if let onSnapshot {
                Button(action: onSnapshot) {
                    Image(systemName: "camera.viewfinder")
                        .font(BPTokens.Typography.body)
                        .foregroundStyle(BPTokens.Color.muted)
                        .iconButtonHitArea()
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .contentShape(Rectangle())
                .help("Create Preview Snapshot")
            }
        }
        .padding(.horizontal, BPTokens.Spacing.md)
        .padding(.vertical, BPTokens.Spacing.xs)
        .background(BPTokens.Color.surface)
    }

    @ViewBuilder
    private func imageCanvas(in viewport: CGSize) -> some View {
        if let image {
            let imageSize = image.size
            let availableWidth = max(viewport.width - 64, 1)
            let availableHeight = max(viewport.height - 64, 1)
            let fitScale = min(
                availableWidth / max(imageSize.width, 1),
                availableHeight / max(imageSize.height, 1),
                1
            )
            let scale = fitScale * clampedZoom(magnifiedZoom ?? zoom)
            let renderedSize = CGSize(
                width: max(imageSize.width * scale, 1),
                height: max(imageSize.height * scale, 1)
            )

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: renderedSize.width, height: renderedSize.height)
                .padding(BPTokens.Spacing.lg)
                .background(BPTokens.Color.elevated)
                .clipShape(RoundedRectangle(cornerRadius: BPTokens.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: BPTokens.Radius.md)
                        .stroke(BPTokens.Color.separator, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                .padding(BPTokens.Spacing.lg)
                .frame(
                    minWidth: viewport.width,
                    minHeight: viewport.height,
                    alignment: .center
                )
        } else {
            EmptyStateView(
                systemImage: "photo",
                title: "Unable to Read Image",
                message: "The file could not be decoded as a supported image."
            )
            .frame(minWidth: viewport.width, minHeight: viewport.height)
        }
    }

    private func clampedZoom(_ value: Double) -> Double {
        min(max(value, 0.7), 2.0)
    }

    private func loadImage() {
        image = NSImage(data: data)
    }
}
