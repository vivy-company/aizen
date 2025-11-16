//
//  FileContentTabView.swift
//  aizen
//
//  Tab view for managing multiple open files
//

import SwiftUI

struct FileContentTabView: View {
    @ObservedObject var viewModel: FileBrowserViewModel

    private func selectPreviousTab() {
        guard let currentId = viewModel.selectedFileId,
              let currentIndex = viewModel.openFiles.firstIndex(where: { $0.id == currentId }),
              currentIndex > 0 else { return }
        viewModel.selectedFileId = viewModel.openFiles[currentIndex - 1].id
    }

    private func selectNextTab() {
        guard let currentId = viewModel.selectedFileId,
              let currentIndex = viewModel.openFiles.firstIndex(where: { $0.id == currentId }),
              currentIndex < viewModel.openFiles.count - 1 else { return }
        viewModel.selectedFileId = viewModel.openFiles[currentIndex + 1].id
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.openFiles.isEmpty {
                emptyState
            } else {
                // Tab bar
                HStack(spacing: 0) {
                    // Navigation arrows
                    Button(action: selectPreviousTab) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 24, height: 36)
                    .disabled(viewModel.openFiles.count <= 1)

                    Button(action: selectNextTab) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 24, height: 36)
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
                            }
                        }
                    }
                }
                .frame(height: 36)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 1),
                    alignment: .top
                )

                Divider()

                // Content
                if let selectedFile = viewModel.openFiles.first(where: { $0.id == viewModel.selectedFileId }) {
                    FileContentView(
                        file: selectedFile,
                        onContentChange: { newContent in
                            viewModel.updateFileContent(id: selectedFile.id, content: newContent)
                        },
                        onSave: {
                            try? viewModel.saveFile(id: selectedFile.id)
                        },
                        onRevert: {
                            Task {
                                await viewModel.openFile(path: selectedFile.path)
                            }
                        }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No files open")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("Select a file from the tree to open")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileTab: View {
    let file: OpenFileInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isCloseHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // File icon
            FileIconView(path: file.path, size: 12)
                .id(file.path)

            Text(file.name)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)

            if file.hasUnsavedChanges {
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 6, height: 6)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isCloseHovering ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .onHover { hovering in
                isCloseHovering = hovering
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .frame(minWidth: 120, maxWidth: 200)
        .background(isSelected ? Color(NSColor.textBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.3))
        .border(width: 1, edges: [.trailing], color: Color(NSColor.separatorColor))
        .overlay(
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2),
            alignment: .top
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Border Extension

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }

            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }

            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }

            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}

// MARK: - Tab Shape (Trapezoid)

struct TabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 6
        let bottomInset: CGFloat = 4

        // Start bottom left
        path.move(to: CGPoint(x: rect.minX + bottomInset, y: rect.maxY))

        // Top left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        // Top right corner
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        // Bottom right
        path.addLine(to: CGPoint(x: rect.maxX - bottomInset, y: rect.maxY))

        // Close path
        path.closeSubpath()

        return path
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        self.init()

        let topLeft = rect.origin
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        if corners.contains(.topLeft) {
            move(to: CGPoint(x: topLeft.x + cornerRadii.width, y: topLeft.y))
        } else {
            move(to: topLeft)
        }

        if corners.contains(.topRight) {
            line(to: CGPoint(x: topRight.x - cornerRadii.width, y: topRight.y))
            curve(to: CGPoint(x: topRight.x, y: topRight.y + cornerRadii.height),
                  controlPoint1: topRight,
                  controlPoint2: topRight)
        } else {
            line(to: topRight)
        }

        if corners.contains(.bottomRight) {
            line(to: CGPoint(x: bottomRight.x, y: bottomRight.y - cornerRadii.height))
            curve(to: CGPoint(x: bottomRight.x - cornerRadii.width, y: bottomRight.y),
                  controlPoint1: bottomRight,
                  controlPoint2: bottomRight)
        } else {
            line(to: bottomRight)
        }

        if corners.contains(.bottomLeft) {
            line(to: CGPoint(x: bottomLeft.x + cornerRadii.width, y: bottomLeft.y))
            curve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - cornerRadii.height),
                  controlPoint1: bottomLeft,
                  controlPoint2: bottomLeft)
        } else {
            line(to: bottomLeft)
        }

        if corners.contains(.topLeft) {
            line(to: CGPoint(x: topLeft.x, y: topLeft.y + cornerRadii.height))
            curve(to: CGPoint(x: topLeft.x + cornerRadii.width, y: topLeft.y),
                  controlPoint1: topLeft,
                  controlPoint2: topLeft)
        } else {
            close()
        }
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}

struct UIRectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
