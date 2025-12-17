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

    // Autocomplete callbacks
    var onCursorChange: ((Int, NSRect) -> Void)?
    var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?

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

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Restore cursor position if valid
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onAutocompleteNavigate = onAutocompleteNavigate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCursorChange: onCursorChange, onAutocompleteNavigate: onAutocompleteNavigate)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        var onCursorChange: ((Int, NSRect) -> Void)?
        var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?
        weak var textView: NSTextView?

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onCursorChange: ((Int, NSRect) -> Void)?,
            onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?
        ) {
            _text = text
            self.onSubmit = onSubmit
            self.onCursorChange = onCursorChange
            self.onAutocompleteNavigate = onAutocompleteNavigate
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            notifyCursorChange(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            notifyCursorChange(textView)
        }

        private func notifyCursorChange(_ textView: NSTextView) {
            let cursorPosition = textView.selectedRange().location
            let cursorRect = cursorScreenRect(for: cursorPosition, in: textView)
            onCursorChange?(cursorPosition, cursorRect)
        }

        private func cursorScreenRect(for position: Int, in textView: NSTextView) -> NSRect {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return .zero
            }

            let range = NSRange(location: position, length: 0)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Add text container inset
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height

            // Convert to window coordinates
            rect = textView.convert(rect, to: nil)

            // Convert to screen coordinates
            if let window = textView.window {
                rect = window.convertToScreen(rect)
            }

            return rect
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle autocomplete navigation first
            if let navigate = onAutocompleteNavigate {
                if commandSelector == #selector(NSTextView.moveUp(_:)) {
                    if navigate(.up) { return true }
                }
                if commandSelector == #selector(NSTextView.moveDown(_:)) {
                    if navigate(.down) { return true }
                }
                if commandSelector == #selector(NSTextView.cancelOperation(_:)) {
                    if navigate(.dismiss) { return true }
                }
            }

            if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                // Check autocomplete selection first
                if let navigate = onAutocompleteNavigate, navigate(.select) {
                    return true
                }

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
                return false
            }

            return false
        }

        // Replace text at range and position cursor after
        func replaceText(in range: NSRange, with replacement: String) {
            guard let textView = textView else { return }

            let nsString = textView.string as NSString
            let newText = nsString.replacingCharacters(in: range, with: replacement)
            textView.string = newText
            text = newText

            // Position cursor after replacement
            let newPosition = range.location + replacement.count
            textView.setSelectedRange(NSRange(location: newPosition, length: 0))
            notifyCursorChange(textView)
        }
    }
}

// MARK: - Chat Attachment Chip

struct ChatAttachmentChip: View {
    let attachment: ChatAttachment
    let onDelete: () -> Void

    @State private var showingDetail = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showingDetail = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: attachment.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(iconColor)

                    Text(attachment.displayName)
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
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundFill)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .sheet(isPresented: $showingDetail) {
            attachmentDetailView
        }
    }

    private var iconColor: Color {
        switch attachment {
        case .file:
            return .secondary
        case .reviewComments:
            return .blue
        case .buildError:
            return .red
        }
    }

    private var backgroundFill: Color {
        switch attachment {
        case .file:
            return Color(NSColor.controlBackgroundColor)
        case .reviewComments:
            return Color.blue.opacity(0.15)
        case .buildError:
            return Color.red.opacity(0.15)
        }
    }

    @ViewBuilder
    private var attachmentDetailView: some View {
        switch attachment {
        case .file(let url):
            InputAttachmentDetailView(url: url)
        case .reviewComments(let content):
            ReviewCommentsDetailView(content: content)
        case .buildError(let content):
            BuildErrorDetailView(content: content)
        }
    }
}

// MARK: - Review Comments Detail View

struct ReviewCommentsDetailView: View {
    let content: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Comments")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            ScrollView {
                MarkdownRenderedView(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Build Error Detail View

struct BuildErrorDetailView: View {
    let content: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Build Error")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            ScrollView {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 600, height: 400)
    }
}

// MARK: - Attachment Chip with Delete (legacy, for URL only)

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
