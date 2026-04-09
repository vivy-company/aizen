import SwiftUI

extension FileContentTabView {
    func selectPreviousTab() {
        guard let currentId = viewModel.selectedFileId,
              let currentIndex = viewModel.openFiles.firstIndex(where: { $0.id == currentId }),
              currentIndex > 0 else { return }
        viewModel.selectedFileId = viewModel.openFiles[currentIndex - 1].id
    }

    func selectNextTab() {
        guard let currentId = viewModel.selectedFileId,
              let currentIndex = viewModel.openFiles.firstIndex(where: { $0.id == currentId }),
              currentIndex < viewModel.openFiles.count - 1 else { return }
        viewModel.selectedFileId = viewModel.openFiles[currentIndex + 1].id
    }

    func canCloseToLeft(of fileId: UUID) -> Bool {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return false }
        return index > 0
    }

    func canCloseToRight(of fileId: UUID) -> Bool {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return false }
        return index < viewModel.openFiles.count - 1
    }

    func closeAllToLeft(of fileId: UUID) {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return }

        for i in (0..<index).reversed() {
            viewModel.closeFile(id: viewModel.openFiles[i].id)
        }
    }

    func closeAllToRight(of fileId: UUID) {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return }

        for i in ((index + 1)..<viewModel.openFiles.count).reversed() {
            viewModel.closeFile(id: viewModel.openFiles[i].id)
        }
    }

    func closeOtherTabs(except fileId: UUID) {
        for file in viewModel.openFiles where file.id != fileId {
            viewModel.closeFile(id: file.id)
        }
    }

    var tabBar: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showTree.toggle()
                }
            } label: {
                ZStack {
                    Rectangle()
                        .fill(isHoveringToggle ? Color.primary.opacity(0.06) : .clear)
                    Image(systemName: showTree ? "sidebar.leading" : "sidebar.trailing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHoveringToggle = hovering
                }
            }
            .help(showTree ? "Hide file tree" : "Show file tree")

            Divider()

            Button(action: selectPreviousTab) {
                ZStack {
                    Rectangle()
                        .fill(isHoveringPrev ? Color.primary.opacity(0.06) : .clear)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10))
                }
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHoveringPrev = hovering
                }
            }
            .disabled(viewModel.openFiles.count <= 1)

            Button(action: selectNextTab) {
                ZStack {
                    Rectangle()
                        .fill(isHoveringNext ? Color.primary.opacity(0.06) : .clear)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                }
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHoveringNext = hovering
                }
            }
            .disabled(viewModel.openFiles.count <= 1)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(viewModel.openFiles) { file in
                        FileTab(
                            file: file,
                            isSelected: viewModel.selectedFileId == file.id,
                            onSelect: {
                                viewModel.selectedFileId = file.id
                            },
                            onClose: {
                                viewModel.closeFile(id: file.id)
                            }
                        )
                        .contextMenu {
                            Button("Close") {
                                viewModel.closeFile(id: file.id)
                            }

                            Divider()

                            Button("Close All to the Left") {
                                closeAllToLeft(of: file.id)
                            }
                            .disabled(!canCloseToLeft(of: file.id))

                            Button("Close All to the Right") {
                                closeAllToRight(of: file.id)
                            }
                            .disabled(!canCloseToRight(of: file.id))

                            Divider()

                            Button("Close Other Tabs") {
                                closeOtherTabs(except: file.id)
                            }
                            .disabled(viewModel.openFiles.count <= 1)
                        }
                    }
                }
            }
        }
        .frame(height: 36)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .top) {
            if showTopDivider {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1)
            }
        }
    }
}
