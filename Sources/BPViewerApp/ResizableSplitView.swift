import SwiftUI

enum ResizableSplitSizing {
    static let dividerWidth = 5.0

    static func clampedLeadingWidth(
        totalWidth: Double,
        proposedWidth: Double,
        minimumLeadingWidth: Double,
        minimumTrailingWidth: Double,
        dividerWidth: Double = dividerWidth
    ) -> Double {
        let availableWidth = max(0, totalWidth - dividerWidth)
        let minimum = max(0, minimumLeadingWidth)
        let maximum = max(minimum, availableWidth - max(0, minimumTrailingWidth))
        return min(max(proposedWidth, minimum), maximum)
    }
}

struct ResizableSplitView<Leading: View, Trailing: View>: View {
    let minimumLeadingWidth: Double
    let minimumTrailingWidth: Double
    let leading: Leading
    let trailing: Trailing
    @State private var storedLeadingWidth: Double?
    @State private var liveLeadingWidth: Double?

    init(
        minimumLeadingWidth: Double = 280,
        minimumTrailingWidth: Double = 280,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.minimumLeadingWidth = minimumLeadingWidth
        self.minimumTrailingWidth = minimumTrailingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = Double(proxy.size.width)
            let defaultWidth = totalWidth / 2
            let maximumWidth = max(
                minimumLeadingWidth,
                totalWidth - ResizableSplitSizing.dividerWidth - minimumTrailingWidth
            )
            let proposedWidth = liveLeadingWidth ?? storedLeadingWidth ?? defaultWidth
            let displayedWidth = ResizableSplitSizing.clampedLeadingWidth(
                totalWidth: totalWidth,
                proposedWidth: proposedWidth,
                minimumLeadingWidth: minimumLeadingWidth,
                minimumTrailingWidth: minimumTrailingWidth
            )

            HStack(spacing: 0) {
                leading
                    .frame(width: displayedWidth)

                SidebarResizeHandle(
                    width: displayedWidth,
                    minimumWidth: minimumLeadingWidth,
                    maximumWidth: maximumWidth,
                    helpText: "Resize Split View",
                    onChanged: { width in
                        liveLeadingWidth = width
                    },
                    onEnded: { width in
                        storedLeadingWidth = width
                        liveLeadingWidth = nil
                    }
                )

                trailing
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
