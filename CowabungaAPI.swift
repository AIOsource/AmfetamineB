//
//  CowabungaAPI.swift
//  Pocket Poster
//
//  Created by lemin on 7/15/25.
//

import UIKit

enum FilterType: String, CaseIterable {
    case random = "Random"
    case newest = "Newest"
    case oldest = "Oldest"
}

class CowabungaAPI: ObservableObject {
    
    static let shared = CowabungaAPI()
    
    var serverURL = "https://raw.githubusercontent.com/SerStars/nugget-wallpapers/main/"
    var session = URLSession.shared
    
    func fetchWallpapers(type: DownloadableWallpaper.WallpaperType) async throws -> [DownloadableWallpaper] {
        guard let url = URL(string: serverURL + "wallpapers-\(type.rawValue).json") else {
            throw APIError.connectionFailed
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.connectionFailed
        }
        var wallpapers = try JSONDecoder().decode([DownloadableWallpaper].self, from: data)
        for i in wallpapers.indices {
            wallpapers[i].type = type
        }
        return wallpapers
    }
    
    func filterWallpapers(wallpapers: [DownloadableWallpaper], filterType: FilterType) -> [DownloadableWallpaper] {
        var filtered = wallpapers
        if filterType == FilterType.newest {
            filtered = filtered.reversed()
        } else if filterType == FilterType.random {
            filtered = filtered.shuffled()
        }
        return filtered
    }
    
    func getDownloadURLForWallpaper(wallpaper: DownloadableWallpaper) -> URL {
        if wallpaper.url.hasPrefix("https://") {
            return URL(string: wallpaper.url) ?? URL(string: serverURL + wallpaper.url)!
        } else {
            return URL(string: serverURL + wallpaper.url)!
        }
    }
    
    func getPreviewURLForWallpaper(wallpaper: DownloadableWallpaper) -> URL {
        return URL(string: serverURL + wallpaper.preview)!
    }
    
    init() {}
}
