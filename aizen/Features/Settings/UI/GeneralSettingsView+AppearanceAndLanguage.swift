import AppKit
import CoreData
import SwiftUI
import os.log

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
