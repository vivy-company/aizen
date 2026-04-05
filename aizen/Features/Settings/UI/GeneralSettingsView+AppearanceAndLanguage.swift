//
//  GeneralSettingsView+AppearanceAndLanguage.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import CoreData
import SwiftUI
import os.log

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearanceModifier: ViewModifier {
    @AppStorage("appearanceMode") var appearanceMode: String = AppearanceMode.system.rawValue

    private var colorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceMode) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
            .id("appearance-\(appearanceMode)")
    }
}

struct AppearancePickerView: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                AppearanceOptionView(
                    mode: mode,
                    isSelected: selection == mode.rawValue
                )
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    selection = mode.rawValue
                }
            }
        }
    }
}

struct AppearanceOptionView: View {
    let mode: AppearanceMode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                AppearancePreviewCard(mode: mode)
                    .frame(width: 100, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }

            Text(mode.label)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
    }
}

struct AppearancePreviewCard: View {
    let mode: AppearanceMode

    var body: some View {
        switch mode {
        case .system:
            HStack(spacing: 0) {
                miniWindowPreview(isDark: false)
                miniWindowPreview(isDark: true)
            }
        case .light:
            miniWindowPreview(isDark: false)
        case .dark:
            miniWindowPreview(isDark: true)
        }
    }

    private func miniWindowPreview(isDark: Bool) -> some View {
        let bgColor = isDark ? Color(white: 0.15) : Color(white: 0.95)
        let windowBg = isDark ? Color(white: 0.22) : Color.white
        let sidebarBg = isDark ? Color(white: 0.18) : Color(white: 0.92)
        let accentBar = isDark ? Color.pink.opacity(0.8) : Color.pink
        let dotColors: [Color] = [.red, .yellow, .green]

        return ZStack {
            bgColor

            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(dotColors[i])
                            .frame(width: 5, height: 5)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(windowBg)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(sidebarBg)
                        .frame(width: 16)

                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentBar)
                            .frame(height: 8)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)

                        Spacer()
                    }
                    .background(windowBg)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

extension GeneralSettingsView {
    var languageSelectionBinding: Binding<AppLanguage> {
        Binding(
            get: { selectedLanguage },
            set: { newValue in
                selectedLanguage = newValue
                guard hasLoadedLanguage else { return }
                applyLanguage(newValue)
            }
        )
    }

    @ViewBuilder
    var appearanceSection: some View {
        Section("Appearance") {
            AppearancePickerView(selection: $appearanceMode)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: languageSelectionBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
    }

    func loadCurrentLanguage() {
        if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = languages.first {
            if first.hasPrefix("zh") {
                selectedLanguage = .chinese
            } else if first.hasPrefix("en") {
                selectedLanguage = .english
            } else {
                selectedLanguage = .system
            }
        } else {
            selectedLanguage = .system
        }
        DispatchQueue.main.async {
            hasLoadedLanguage = true
        }
    }

    func applyLanguage(_ language: AppLanguage) {
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .chinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        showingRestartAlert = true
    }

    func restartApp() {
        let bundleURL = Bundle.main.bundleURL

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", bundleURL.path]
            try? task.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
