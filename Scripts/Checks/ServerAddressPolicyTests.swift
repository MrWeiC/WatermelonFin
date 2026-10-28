//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@main
struct ServerAddressPolicyTests {
    static func main() throws {
        let cases = [
            ("192.168.1.20", "http://192.168.1.20:8096"),
            (" 100.70.1.2 ", "http://100.70.1.2:8096"),
            ("media.tail123.ts.net", "http://media.tail123.ts.net:8096"),
            ("media:8920/jellyfin/", "http://media:8920/jellyfin"),
            ("https://media.example.com", "https://media.example.com"),
            ("http://media.example.com", "http://media.example.com"),
            ("https://media.example.com:8443/jellyfin", "https://media.example.com:8443/jellyfin"),
            ("[fd7a:115c:a1e0::1]", "http://[fd7a:115c:a1e0::1]:8096"),
            ("[fd7a:115c:a1e0::1]:9000", "http://[fd7a:115c:a1e0::1]:9000"),
        ]
        for (input, expected) in cases {
            let actual = try ServerAddressInput.url(from: input).absoluteString
            precondition(actual == expected, "\(input): \(actual) != \(expected)")
        }
        for input in [
            "",
            "bad host",
            "ftp://server",
            "http://user:password@server",
            "fd7a:115c:a1e0::1",
            "host:0",
            "host:65536",
            "http://host/?token=secret",
            "http://host/#fragment",
        ] {
            do {
                _ = try ServerAddressInput.url(from: input)
                fatalError("Accepted invalid input: \(input)")
            } catch {}
        }
        precondition(ServerIdentityPolicy.matches(expected: "server-A", reported: "server-A"))
        precondition(!ServerIdentityPolicy.matches(expected: "server-A", reported: "server-B"))
        precondition(!ServerIdentityPolicy.matches(expected: "server-A", reported: nil))
        precondition(!ServerIdentityPolicy.matches(expected: "", reported: ""))
        print("Server address and identity policy checks passed")
    }
}
