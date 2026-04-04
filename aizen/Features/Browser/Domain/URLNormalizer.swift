import Foundation

struct URLNormalizer {
    /// Normalizes user input to a valid URL or search query
    /// - Parameter input: User input from address bar
    /// - Returns: Valid URL string (domain with https://) or Google search URL
    static func normalize(_ input: String) -> String {
        // Trim whitespace
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prevent empty input
        guard !trimmed.isEmpty else {
            return "about:blank"
        }

        // Sanitize input - remove dangerous characters
        let sanitized = trimmed.replacingOccurrences(of: "\n", with: "")
                              .replacingOccurrences(of: "\r", with: "")

        // Check if input already has a valid scheme
        if let url = URL(string: sanitized),
           let scheme = url.scheme,
           (scheme == "http" || scheme == "https" || scheme == "file" || scheme == "about") {
            return url.absoluteString
        }

        // Check if input looks like a domain (contains a dot and no spaces)
        let containsDot = sanitized.contains(".")
        let containsSpaces = sanitized.contains(" ")

        if containsDot && !containsSpaces {
            // Looks like a domain, try adding https://
            let urlWithScheme = "https://" + sanitized

            // Validate the URL has a valid host
            if let url = URL(string: urlWithScheme),
               let host = url.host,
               !host.isEmpty {
                return url.absoluteString
            }
        }

        // Otherwise, treat as search query
        let encodedQuery = sanitized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sanitized
        return "https://www.google.com/search?q=\(encodedQuery)"
    }
}
