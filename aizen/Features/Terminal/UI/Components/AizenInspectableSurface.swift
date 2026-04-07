import GhosttyKit
import SwiftUI

struct AizenInspectableSurface: View {
    @ObservedObject var surfaceView: AizenTerminalSurfaceView
    let adapter: AizenTerminalSurfaceAdapter
    let effectiveThemeName: String
    let isSplit: Bool
    let isFocused: Bool
    let showsProgress: Bool

    @FocusState private var surfaceFocus: Bool
    @State private var isHoveringURLLeft = false

    private var isFocusedSurface: Bool {
        surfaceFocus || isFocused
    }

    private var backgroundColor: Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName))
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                AizenTerminalSurfaceHost(
                    surfaceView: surfaceView,
                    adapter: adapter,
                    size: geo.size
                )
                .focused($surfaceFocus)

                if let surfaceSize = surfaceView.surfaceSize {
                    AizenSurfaceResizeOverlay(
                        geoSize: geo.size,
                        size: surfaceSize,
                        focusInstant: surfaceView.focusInstant
                    )
                }
            }

            if showsProgress,
               let progressReport = surfaceView.progressReport,
               progressReport.state != .remove {
                VStack(spacing: 0) {
                    AizenSurfaceProgressBar(report: progressReport)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if let url = surfaceView.hoverUrl {
                let padding: CGFloat = 5
                let cornerRadius: CGFloat = 9
                ZStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading) {
                            Spacer()

                            Text(verbatim: url)
                                .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                .background(
                                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius))
                                        .fill(.background)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .opacity(isHoveringURLLeft ? 1 : 0)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Spacer()

                            Text(verbatim: url)
                                .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                .background(
                                    UnevenRoundedRectangle(cornerRadii: .init(topTrailing: cornerRadius))
                                        .fill(.background)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .opacity(isHoveringURLLeft ? 0 : 1)
                                .onHover { hovering in
                                    isHoveringURLLeft = hovering
                                }
                        }
                        Spacer()
                    }
                }
            }

            if let searchState = surfaceView.searchState {
                AizenSurfaceSearchOverlay(
                    surfaceView: surfaceView,
                    searchState: searchState,
                    onClose: {
                        Ghostty.moveFocus(to: surfaceView)
                        surfaceView.searchState = nil
                    }
                )
            }

            AizenBellBorderOverlay(bell: surfaceView.bell)
            AizenHighlightOverlay(highlighted: surfaceView.highlighted)

            if !surfaceView.healthy {
                Rectangle().fill(backgroundColor)
                AizenSurfaceMessageView(
                    title: "Renderer Failed",
                    message: "The terminal renderer exhausted GPU resources or failed to recover."
                )
            } else if surfaceView.error != nil {
                Rectangle().fill(backgroundColor)
                AizenSurfaceMessageView(
                    title: "Terminal Failed",
                    message: "The terminal failed to initialize. Check logs for the underlying error."
                )
            }

            if isSplit && !isFocusedSurface {
                Rectangle()
                    .fill(backgroundColor)
                    .allowsHitTesting(false)
                    .opacity(0.28)
            }
        }
    }
}
