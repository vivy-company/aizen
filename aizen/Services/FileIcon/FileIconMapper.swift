//
//  FileIconMapper.swift
//  aizen
//
//  Maps file extensions and filenames to file type icon names.
//

import Foundation

struct FileIconMapper {
    // MARK: - Extension to Icon Mapping

    private static let extensionMapping: [String: String] = [
        // Web
        "html": "file_html5",
        "htm": "file_html5",
        "css": "file_css3",
        "scss": "file_sass",
        "sass": "file_sass",
        "less": "file_less",
        "js": "file_javascript",
        "jsx": "file_javascript-react",
        "mjs": "file_javascript",
        "cjs": "file_javascript",
        "ts": "file_typescript",
        "tsx": "file_typescript-react",
        "json": "file_json",
        "yaml": "file_yaml",
        "yml": "file_yaml",

        // JavaScript Frameworks
        "vue": "file_vue",

        // Apple
        "swift": "file_swift",

        // Systems Programming
        "rs": "file_rust",
        "c": "file_c",
        "h": "file_c",
        "cpp": "file_cplusplus",
        "cc": "file_cplusplus",
        "cxx": "file_cplusplus",
        "hpp": "file_cpp-header",
        "hxx": "file_cpp-header",
        "cs": "file_csharp",

        // JVM Languages
        "java": "file_java",
        "kt": "file_kotlin",
        "kts": "file_kotlin",
        "scala": "file_scala",
        "clj": "file_clojure",
        "cljs": "file_clojure",

        // Scripting
        "py": "file_python",
        "pyc": "file_python-compiled",
        "pyw": "file_python",
        "pyx": "file_python",
        "rb": "file_ruby",
        "erb": "file_ruby",
        "php": "file_php",
        "sh": "file_bash",
        "bash": "file_bash",
        "zsh": "file_bash",
        "fish": "file_bash",
        "lua": "file_lua",
        "pl": "file_perl",
        "pm": "file_perl",

        // Functional
        "hs": "file_haskell",
        "lhs": "file_haskell",
        "ex": "file_elixir",
        "exs": "file_elixir",

        // Data Science
        "r": "file_r",
        "jl": "file_julia",
        "m": "file_matlab",

        // Go
        "go": "file_go",

        // Dart
        "dart": "file_dart",

        // Documentation
        "md": "file_markdown",
        "markdown": "file_markdown",
        "mdx": "file_markdown-mdx",
    ]

    // MARK: - Filename to Icon Mapping

    private static let filenameMapping: [String: String] = [
        // Docker
        "Dockerfile": "file_docker",
        "docker-compose.yml": "file_docker",
        "docker-compose.yaml": "file_docker",
        ".dockerignore": "file_docker",

        // Git
        ".gitignore": "file_git",
        ".gitattributes": "file_git",
        ".gitmodules": "file_git",

        // GitHub
        ".github": "file_github",

        // Node.js
        "package.json": "file_npm",
        "package-lock.json": "file_npm",
        ".npmrc": "file_npm",

        // React/Babel
        ".babelrc": "file_babel",
        "babel.config.js": "file_babel",

        // Angular
        "angular.json": "file_angular",
        ".angular-cli.json": "file_angular",
    ]

    // MARK: - Public API

    /// Resolves the icon name for a given file path
    /// - Parameter filePath: The file path to resolve
    /// - Returns: The icon name (e.g., "file_swift") or nil if no mapping exists
    static func iconName(for filePath: String) -> String? {
        let fileName = (filePath as NSString).lastPathComponent

        // Priority 1: Exact filename match
        if let icon = filenameMapping[fileName] {
            return icon
        }

        // Priority 2: Extension match
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        if !fileExtension.isEmpty, let icon = extensionMapping[fileExtension] {
            return icon
        }

        return nil
    }

    /// Returns all supported file extensions
    static var supportedExtensions: Set<String> {
        Set(extensionMapping.keys)
    }

    /// Returns all supported filenames
    static var supportedFilenames: Set<String> {
        Set(filenameMapping.keys)
    }
}
