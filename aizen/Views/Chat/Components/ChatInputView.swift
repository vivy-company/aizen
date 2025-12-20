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
    @Binding var measuredHeight: CGFloat
    let onSubmit: () -> Void

    // Autocomplete callbacks - passes (text, cursorPosition, cursorRect)
    var onCursorChange: ((String, Int, NSRect) -> Void)?
    var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?

    // Image paste callback - (imageData, mimeType)
    var onImagePaste: ((Data, String) -> Void)?

    // Cursor position control - when set, moves cursor to this position after text update
    @Binding var pendingCursorPosition: Int?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView: NSTextView
        if let existing = scrollView.documentView as? NSTextView {
            textView = existing
        } else {
            textView = NSTextView()
            scrollView.documentView = textView
        }

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
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.updateMeasuredHeight()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.scrollView = nsView

        if textView.string != text {
            textView.string = text

            // Apply mention highlighting
            context.coordinator.applyHighlighting(to: textView)

            // If we have a pending cursor position, use it
            if let cursorPos = pendingCursorPosition {
                let safePos = min(cursorPos, text.count)
                textView.setSelectedRange(NSRange(location: safePos, length: 0))
                // Clear the pending position after applying
                DispatchQueue.main.async {
                    self.pendingCursorPosition = nil
                }
            }
        }
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onAutocompleteNavigate = onAutocompleteNavigate
        context.coordinator.onImagePaste = onImagePaste
        context.coordinator.updateMeasuredHeight()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            onSubmit: onSubmit,
            onCursorChange: onCursorChange,
            onAutocompleteNavigate: onAutocompleteNavigate,
            onImagePaste: onImagePaste
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var measuredHeight: CGFloat
        let onSubmit: () -> Void
        var onCursorChange: ((String, Int, NSRect) -> Void)?
        var onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?
        var onImagePaste: ((Data, String) -> Void)?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var eventMonitor: Any?

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            onSubmit: @escaping () -> Void,
            onCursorChange: ((String, Int, NSRect) -> Void)?,
            onAutocompleteNavigate: ((AutocompleteNavigationAction) -> Bool)?,
            onImagePaste: ((Data, String) -> Void)?
        ) {
            _text = text
            _measuredHeight = measuredHeight
            self.onSubmit = onSubmit
            self.onCursorChange = onCursorChange
            self.onAutocompleteNavigate = onAutocompleteNavigate
            self.onImagePaste = onImagePaste
            super.init()
            setupEventMonitor()
        }

        deinit {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func setupEventMonitor() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                // Check for Cmd+V
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                    // Check if our text view is first responder
                    if let textView = self.textView,
                       textView.window?.firstResponder === textView {
                        // Try to handle image paste
                        if self.handleImagePaste() {
                            return nil // Consume the event
                        }
                    }
                }
                return event
            }
        }

        private func handleImagePaste() -> Bool {
            guard let onImagePaste = onImagePaste else { return false }

            let pasteboard = NSPasteboard.general

            // Check for PNG data first (most common for screenshots)
            if let data = pasteboard.data(forType: .png) {
                onImagePaste(data, "image/png")
                return true
            }

            // Check for TIFF data (common for copied images)
            if let data = pasteboard.data(forType: .tiff) {
                // Convert TIFF to PNG for better compatibility
                if let image = NSImage(data: data),
                   let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    onImagePaste(pngData, "image/png")
                    return true
                }
            }

            // Check for file URL that might be an image
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let url = urls.first {
                let ext = url.pathExtension.lowercased()
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"]
                if imageExtensions.contains(ext) {
                    if let data = try? Data(contentsOf: url) {
                        let mimeType = mimeTypeForExtension(ext)
                        onImagePaste(data, mimeType)
                        return true
                    }
                }
            }

            return false
        }

        private func mimeTypeForExtension(_ ext: String) -> String {
            switch ext.lowercased() {
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            case "heic", "heif": return "image/heic"
            case "tiff", "tif": return "image/tiff"
            case "bmp": return "image/bmp"
            default: return "image/png"
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            highlightMentions(in: textView)
            notifyCursorChange(textView)
            updateMeasuredHeight()
        }

        func applyHighlighting(to textView: NSTextView) {
            highlightMentions(in: textView)
        }

        private func highlightMentions(in textView: NSTextView) {
            let text = textView.string
            let fullRange = NSRange(location: 0, length: text.utf16.count)

            // Store current selection
            let selectedRange = textView.selectedRange()

            // Create attributed string with default styling
            let attributedString = NSMutableAttributedString(string: text)
            attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
            attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

            // Find and highlight @mentions (pattern: @followed by non-whitespace until space)
            let pattern = "@[^\\s]+"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: fullRange)
                for match in matches {
                    attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
                }
            }

            // Only update if there are actual mentions to highlight
            if textView.textStorage?.string != attributedString.string ||
               !attributedString.isEqual(to: textView.attributedString()) {
                textView.textStorage?.setAttributedString(attributedString)
                // Restore selection
                if selectedRange.location <= text.count {
                    textView.setSelectedRange(selectedRange)
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            notifyCursorChange(textView)
        }

        func updateMeasuredHeight() {
            guard let textView = textView,
                  let scrollView = scrollView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else {
                return
            }

            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)

            let usedRect = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset.height * 2
            let newHeight = usedRect.height + inset

            if abs(newHeight - measuredHeight) > 0.5 {
                DispatchQueue.main.async { [weak self] in
                    self?.measuredHeight = newHeight
                }
            }
        }

        private func notifyCursorChange(_ textView: NSTextView) {
            let currentText = textView.string
            let cursorPosition = textView.selectedRange().location
            let cursorRect = cursorScreenRect(for: cursorPosition, in: textView)
            onCursorChange?(currentText, cursorPosition, cursorRect)
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
                    // Show thumbnail for pasted images
                    if case .image(let data, _) = attachment,
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: attachment.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(iconColor)
                    }

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
        case .image:
            return .purple
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
        case .image:
            return Color.purple.opacity(0.15)
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
        case .image(let data, _):
            ImageAttachmentDetailView(data: data)
        case .reviewComments(let content):
            ReviewCommentsDetailView(content: content)
        case .buildError(let content):
            BuildErrorDetailView(content: content)
        }
    }
}

// MARK: - Image Attachment Detail View

struct ImageAttachmentDetailView: View {
    let data: Data
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pasted Image")
                        .font(.headline)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
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
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Unable to display image")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .frame(width: 700, height: 500)
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
