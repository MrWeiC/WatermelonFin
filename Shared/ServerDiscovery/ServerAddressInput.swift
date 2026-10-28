import Foundation

/// Bare hosts use Jellyfin's default port; explicit URLs retain HTTP/HTTPS defaults.
enum ServerAddressInput {
    enum InvalidAddress: Error { case invalid }

    static func url(from input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else {
            throw InvalidAddress.invalid
        }
        let explicitScheme = value.contains("://")
        // IPv6 literals must be bracketed, avoiding ambiguity with a custom port.
        let authority = value.split(separator: "/", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard explicitScheme || authority.filter({ $0 == ":" }).count < 2 || authority.hasPrefix("[") else {
            throw InvalidAddress.invalid
        }
        guard var parts = URLComponents(string: explicitScheme ? value : "http://" + value),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil
        else { throw InvalidAddress.invalid }
        if !explicitScheme, parts.port == nil { parts.port = 8096 }
        if let port = parts.port, !(1...65535).contains(port) { throw InvalidAddress.invalid }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let url = parts.url else { throw InvalidAddress.invalid }
        return url
    }
}

/// Never associate an endpoint with a saved account using its name or IP alone.
enum ServerIdentityPolicy {
    static func matches(expected: String, reported: String?) -> Bool {
        !expected.isEmpty && reported == expected
    }
}
