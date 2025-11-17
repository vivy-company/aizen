import SwiftUI
import WebKit

struct BrowserControlBar: View {
    @Binding var url: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var loadingProgress: Double

    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onNavigate: (String) -> Void

    @State private var urlInput: String = ""
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Navigation buttons
            navigationButtons

            // URL input field
            urlTextField
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(controlBarBackground)
        .overlay(
            // Loading progress bar as overlay at bottom
            VStack {
                Spacer()
                if isLoading && loadingProgress < 1.0 {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * loadingProgress, height: 2)
                            .animation(.linear(duration: 0.1), value: loadingProgress)
                    }
                    .frame(height: 2)
                }
            }
        )
    }

    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: 6) {
            navigationButton(
                action: onBack,
                icon: "chevron.left",
                disabled: !canGoBack,
                help: "browser.control.back"
            )

            navigationButton(
                action: onForward,
                icon: "chevron.right",
                disabled: !canGoForward,
                help: "browser.control.forward"
            )

            navigationButton(
                action: onReload,
                icon: isLoading ? "xmark" : "arrow.clockwise",
                disabled: false,
                help: isLoading ? "browser.control.stop" : "browser.control.reload"
            )
        }
    }

    @ViewBuilder
    private func navigationButton(action: @escaping () -> Void, icon: String, disabled: Bool, help: String.LocalizationValue) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .disabled(disabled)
        .buttonStyle(.borderless)
        .help(String(localized: help))
    }

    @ViewBuilder
    private var urlTextField: some View {
        if #available(macOS 15.0, *) {
            TextField(String(localized: "browser.control.url_placeholder"), text: $urlInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .focused($isURLFieldFocused)
                .onSubmit(handleURLSubmit)
                .onChange(of: url, perform: handleURLChange)
                .onAppear { urlInput = url }
        } else {
            TextField(String(localized: "browser.control.url_placeholder"), text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .frame(height: 32)
                .focused($isURLFieldFocused)
                .onSubmit(handleURLSubmit)
                .onChange(of: url, perform: handleURLChange)
                .onAppear { urlInput = url }
        }
    }

    @ViewBuilder
    private var controlBarBackground: some View {
        if #available(macOS 15.0, *) {
            Color.clear
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }

    private func handleURLSubmit() {
        let trimmedInput = urlInput.trimmingCharacters(in: .whitespaces)
        guard !trimmedInput.isEmpty else { return }

        let finalURL = URLNormalizer.normalize(trimmedInput)
        onNavigate(finalURL)

        // Unfocus the text field so URL updates from navigation will be visible
        isURLFieldFocused = false
    }

    private func handleURLChange(_ newValue: String) {
        // Update input field when URL changes externally
        if !isURLFieldFocused {
            urlInput = newValue
        }
    }
}
