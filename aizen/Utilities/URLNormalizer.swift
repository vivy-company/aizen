import Foundation

struct URLNormalizer {
    /// Normalizes user input to a valid URL or search query
    /// - Parameter input: User input from address bar
    /// - Returns: Valid URL string (domain with https://) or Google search URL
    static func normalize(_ input: String) -> String {
        // Check if input already has a valid scheme
        if let url = URL(string: input),
           let scheme = url.scheme,
           (scheme == "http" || scheme == "https") {
            return url.absoluteString
        }

        // Check if input looks like a domain (contains a dot and no spaces)
        let containsDot = input.contains(".")
        let containsSpaces = input.contains(" ")

        if containsDot && !containsSpaces {
            // Looks like a domain, try adding https://
            let urlWithScheme = "https://" + input

            // Validate the URL has a valid host
            if let url = URL(string: urlWithScheme), url.host != nil {
                return url.absoluteString
            }
        }

        // Otherwise, treat as search query
        let encodedQuery = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        return "https://www.google.com/search?q=\(encodedQuery)"
    }
}
