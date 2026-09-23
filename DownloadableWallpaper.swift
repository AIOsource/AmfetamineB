//
//  DownloadableWallpaper.swift
//  AmfetamineB
//

import Foundation

struct DownloadableWallpaper: Identifiable, Codable, Hashable {
    var rawId: Int?
    var name: String
    var description: String?
    var url: String
    var preview: String
    var authors: String?
    var contest: String?
    var type: WallpaperType?

    var id: String {
        "\(name)_\(url)"
    }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case name, description, url, preview, authors, contest, type
    }

    enum WallpaperType: String, Codable, CaseIterable {
        case custom, apple, template
    }

    func previewIsGif() -> Bool {
        return preview.hasSuffix(".gif")
    }
}
