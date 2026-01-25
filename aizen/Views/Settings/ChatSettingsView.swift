//
//  ChatSettingsView.swift
//  aizen
//
//  Settings for chat appearance and markdown rendering
//

import SwiftUI

// MARK: - Tool Call Expansion Mode

enum ToolCallExpansionMode: String, CaseIterable, Identifiable {
    case expanded = "expanded"      // All expanded by default
    case collapsed = "collapsed"    // All collapsed by default
    case smart = "smart"           // Expand current iteration, collapse past
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .expanded: return "Expanded"
        case .collapsed: return "Collapsed"
        case .smart: return "Smart"
        }
    }
    
    var description: String {
        switch self {
        case .expanded: return "All tool calls expanded"
        case .collapsed: return "All tool calls collapsed"
        case .smart: return "Current expanded, past collapsed"
        }
    }
}

// MARK: - Code Block Expansion Mode

enum CodeBlockExpansionMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case expanded = "expanded"
    case collapsed = "collapsed"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .expanded: return "Expanded"
        case .collapsed: return "Collapsed"
        }
    }
    
    var description: String {
        switch self {
        case .auto: return "Small blocks expanded, large collapsed"
        case .expanded: return "All code blocks expanded"
        case .collapsed: return "All code blocks collapsed"
        }
    }
}

// MARK: - Chat Settings Keys

enum ChatSettings {
    static let fontFamilyKey = "chatFontFamily"
    static let fontSizeKey = "chatFontSize"
    static let blockSpacingKey = "chatBlockSpacing"
    static let toolCallExpansionModeKey = "chatToolCallExpansionMode"
    static let codeBlockExpansionModeKey = "chatCodeBlockExpansionMode"
    static let enableAnimationsKey = "chatEnableAnimations"

    static let defaultFontFamily: String = "System Font"
    static let defaultFontSize: Double = 14.0
    static let defaultBlockSpacing: Double = 8.0
    static let defaultToolCallExpansionMode: String = ToolCallExpansionMode.smart.rawValue
    static let defaultCodeBlockExpansionMode: String = CodeBlockExpansionMode.auto.rawValue
    static let defaultEnableAnimations: Bool = true

    static let fontSizeRange: ClosedRange<Double> = 12...20
    static let blockSpacingRange: ClosedRange<Double> = 4...16
}

// MARK: - Chat Settings View

struct ChatSettingsView: View {
    @AppStorage(ChatSettings.fontFamilyKey) private var fontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing
    @AppStorage(ChatSettings.toolCallExpansionModeKey) private var toolCallExpansionMode = ChatSettings.defaultToolCallExpansionMode
    @AppStorage(ChatSettings.codeBlockExpansionModeKey) private var codeBlockExpansionMode = ChatSettings.defaultCodeBlockExpansionMode
    @AppStorage(ChatSettings.enableAnimationsKey) private var enableAnimations = ChatSettings.defaultEnableAnimations

    @State private var availableFonts: [String] = []
    
    private var selectedToolExpansionMode: Binding<ToolCallExpansionMode> {
        Binding(
            get: { ToolCallExpansionMode(rawValue: toolCallExpansionMode) ?? .smart },
            set: { toolCallExpansionMode = $0.rawValue }
        )
    }
    
    private var selectedCodeExpansionMode: Binding<CodeBlockExpansionMode> {
        Binding(
            get: { CodeBlockExpansionMode(rawValue: codeBlockExpansionMode) ?? .auto },
            set: { codeBlockExpansionMode = $0.rawValue }
        )
    }

    private func loadSystemFonts() -> [String] {
        let fontManager = NSFontManager.shared
        var fonts = fontManager.availableFontFamilies.sorted()
        fonts.insert("System Font", at: 0)
        return fonts
    }

    private var previewFont: Font {
        if fontFamily == "System Font" {
            return .system(size: chatFontSize)
        } else {
            return .custom(fontFamily, size: chatFontSize)
        }
    }

    private var previewHeadingFont: Font {
        if fontFamily == "System Font" {
            return .system(size: chatFontSize * 1.3, weight: .bold)
        } else {
            return .custom(fontFamily, size: chatFontSize * 1.3).weight(.bold)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $fontFamily) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .disabled(availableFonts.isEmpty)

                HStack {
                    Text("Size: \(Int(chatFontSize)) pt")
                        .frame(width: 90, alignment: .leading)

                    Slider(value: $chatFontSize, in: ChatSettings.fontSizeRange, step: 1)

                    Stepper("", value: $chatFontSize, in: ChatSettings.fontSizeRange, step: 1)
                        .labelsHidden()
                }

                HStack {
                    Text("Spacing: \(Int(blockSpacing)) pt")
                        .frame(width: 100, alignment: .leading)

                    Slider(value: $blockSpacing, in: ChatSettings.blockSpacingRange, step: 2)

                    Stepper("", value: $blockSpacing, in: ChatSettings.blockSpacingRange, step: 2)
                        .labelsHidden()
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Tool Calls", selection: selectedToolExpansionMode) {
                    ForEach(ToolCallExpansionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(selectedToolExpansionMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Code Blocks", selection: selectedCodeExpansionMode) {
                    ForEach(CodeBlockExpansionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(selectedCodeExpansionMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Content Display")
            }
            
            Section {
                Toggle("Enable Animations", isOn: $enableAnimations)
                
                Text("Smooth transitions for expanding/collapsing content")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Behavior")
            }

            Section {
                VStack(alignment: .leading, spacing: blockSpacing) {
                    Text("Heading")
                        .font(previewHeadingFont)

                    Text("First paragraph with some text content that demonstrates the font size.")
                        .font(previewFont)

                    Text("Second paragraph following the first one. Notice the spacing between blocks.")
                        .font(previewFont)

                    HStack(spacing: 4) {
                        Text("•")
                        Text("List item with bullet point")
                    }
                    .font(previewFont)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } header: {
                Text("Preview")
            }

            Section {
                Button("Reset to Defaults") {
                    fontFamily = ChatSettings.defaultFontFamily
                    chatFontSize = ChatSettings.defaultFontSize
                    blockSpacing = ChatSettings.defaultBlockSpacing
                    toolCallExpansionMode = ChatSettings.defaultToolCallExpansionMode
                    codeBlockExpansionMode = ChatSettings.defaultCodeBlockExpansionMode
                    enableAnimations = ChatSettings.defaultEnableAnimations
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if availableFonts.isEmpty {
                availableFonts = loadSystemFonts()
            }
        }
    }
}

#Preview {
    ChatSettingsView()
        .frame(width: 500, height: 500)
}
