//
//  ChatTabView+CompanionShell.swift
//  aizen
//
//  Companion panel shell layout for the chat tab
//

import SwiftUI

extension ChatTabView {
    @ViewBuilder
    var chatContentWithCompanion: some View {
        GeometryReader { geometry in
            let toolbarInset = resolvedToolbarInset(from: geometry)
            HStack(spacing: 0) {
                if let panel = leftPanel {
                    CompanionPanelView(
                        panel: panel,
                        worktree: worktree,
                        repositoryManager: repositoryManager,
                        terminalSessions: terminalSessions,
                        browserSessions: browserSessions,
                        side: .left,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                leftPanelType = ""
                            }
                        },
                        isResizing: isResizingCompanion,
                        terminalSessionId: $selectedTerminalSessionId,
                        browserSessionId: $selectedBrowserSessionId
                    )
                    .padding(.top, toolbarInset)
                    .frame(width: CGFloat(leftPanelWidth))
                    .animation(nil, value: leftPanelWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    CompanionDivider(
                        panelWidth: $leftPanelWidth,
                        minWidth: minPanelWidth,
                        maxWidth: maxLeftWidth(containerWidth: geometry.size.width, rightWidth: CGFloat(rightPanelWidth)),
                        containerWidth: geometry.size.width,
                        coordinateSpace: companionCoordinateSpace,
                        side: .left,
                        isDragging: $isResizingCompanion,
                        onDragEnd: { leftPanelWidthStored = leftPanelWidth }
                    )
                }

                chatSessionsStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        if leftPanel == nil {
                            CompanionRailView(
                                side: .left,
                                availablePanels: availableForLeft,
                                onSelect: { leftPanelType = $0.rawValue }
                            )
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if rightPanel == nil {
                            CompanionRailView(
                                side: .right,
                                availablePanels: availableForRight,
                                onSelect: { rightPanelType = $0.rawValue }
                            )
                        }
                    }
                    .padding(.top, toolbarInset)

                if let panel = rightPanel {
                    CompanionDivider(
                        panelWidth: $rightPanelWidth,
                        minWidth: minPanelWidth,
                        maxWidth: maxRightWidth(containerWidth: geometry.size.width, leftWidth: CGFloat(leftPanelWidth)),
                        containerWidth: geometry.size.width,
                        coordinateSpace: companionCoordinateSpace,
                        side: .right,
                        isDragging: $isResizingCompanion,
                        onDragEnd: { rightPanelWidthStored = rightPanelWidth }
                    )

                    CompanionPanelView(
                        panel: panel,
                        worktree: worktree,
                        repositoryManager: repositoryManager,
                        terminalSessions: terminalSessions,
                        browserSessions: browserSessions,
                        side: .right,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                rightPanelType = ""
                            }
                        },
                        isResizing: isResizingCompanion,
                        terminalSessionId: $selectedTerminalSessionId,
                        browserSessionId: $selectedBrowserSessionId
                    )
                    .padding(.top, toolbarInset)
                    .frame(width: CGFloat(rightPanelWidth))
                    .animation(nil, value: rightPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: leftPanelType)
            .animation(.easeInOut(duration: 0.2), value: rightPanelType)
            .animation(nil, value: leftPanelWidth)
            .animation(nil, value: rightPanelWidth)
            .transaction { transaction in
                if isResizingCompanion {
                    transaction.disablesAnimations = true
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(name: companionCoordinateSpace)
            .onAppear {
                if !didLoadWidths {
                    leftPanelWidth = leftPanelWidthStored
                    rightPanelWidth = rightPanelWidthStored
                    clampPanelWidths(containerWidth: geometry.size.width)
                    didLoadWidths = true
                }
            }
            .task(id: geometry.size.width) {
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
            .task(id: leftPanelType) {
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
            .task(id: rightPanelType) {
                DispatchQueue.main.async {
                    clampPanelWidths(containerWidth: geometry.size.width)
                }
            }
        }
    }
}
