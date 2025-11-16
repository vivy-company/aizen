//
//  ChatInputView.swift
//  aizen
//
//  Chat input components and helpers
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom Text Editor

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 0

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    onSubmit()
                    return true
                }
            }
            // Allow Shift+Tab to be handled by the app (for mode cycling)
            if commandSelector == #selector(NSTextView.insertTab(_:)) && NSEvent.modifierFlags.contains(.shift) {
                // Don't handle it here, let the system handle it
                return false
            }
            return false
        }
    }
}

// MARK: - Attachment Chip with Delete

struct AttachmentChipWithDelete: View {
    let url: URL
    let onDelete: () -> Void

    @State private var showingDetail = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showingDetail = true
            } label: {
                HStack(spacing: 6) {
                    attachmentIcon
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(fileName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .sheet(isPresented: $showingDetail) {
            InputAttachmentDetailView(url: url)
        }
    }

    @ViewBuilder
    private var attachmentIcon: some View {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff":
            Image(systemName: "photo.fill")
        case "mp3", "wav", "aiff", "m4a":
            Image(systemName: "waveform")
        case "mp4", "mov", "avi":
            Image(systemName: "play.rectangle.fill")
        case "zip", "tar", "gz":
            Image(systemName: "doc.zipper")
        default:
            FileIconView(path: url.path, size: 10)
        }
    }

    private var fileName: String {
        url.lastPathComponent
    }
}

// MARK: - Input Attachment Detail View

struct InputAttachmentDetailView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss

    @State private var fileContent: String?
    @State private var image: NSImage?
    @State private var fileSize: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                    Text(fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                Group {
                    if let image = image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    } else if let content = fileContent {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(spacing: 12) {
                            FileIconView(path: url.path, size: 48)

                            Text("chat.preview.unavailable", bundle: .main)
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                }
                .padding()
            }
        }
        .frame(width: 700, height: 500)
        .onAppear {
            loadFileContent()
        }
    }

    private func loadFileContent() {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        if let loadedImage = NSImage(contentsOf: url) {
            image = loadedImage
            return
        }

        if let content = try? String(contentsOf: url, encoding: .utf8) {
            fileContent = String(content.prefix(10000))
            if content.count > 10000 {
                fileContent! += "\n\n... (content truncated)"
            }
        }
    }
}
