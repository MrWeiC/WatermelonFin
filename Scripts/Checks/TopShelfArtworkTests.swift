//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@main
struct TopShelfArtworkTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = Data([0x89, 0x50, 0x4E, 0x47])
        let url = try TopShelfArtworkStore.write(image, to: root)
        precondition(url.isFileURL)
        precondition(url.query == nil)
        let restoredImage = try Data(contentsOf: url)
        precondition(restoredImage == image)
        print("Top Shelf artwork checks passed")
    }
}
