//
//  BadQuerySwift.swift
//  Amfeta-Board
//
//  Swift wrapper around forcequitOS/bad_query sandbox escape
//  (container_query path traversal via MobileGestalt SystemGroup).
//  Supports iOS 26.0 – 26.6.1 / 27.0b4+.
//

import Foundation
import UIKit

public enum BadQueryError: LocalizedError {
    case invalidPath
    case missingPath
    case resolveFailed
    case createFailed
    case outsideSandbox
    case kernelRejected
    case asprintfFailed
    case unknown(Int64)
    case listFailed
    case containerNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Path must be absolute."
        case .missingPath:
            return "Target path does not exist."
        case .resolveFailed:
            return "Failed to resolve containermanager symbols."
        case .createFailed:
            return "Failed to create container query."
        case .outsideSandbox:
            return "Path is outside containermanager sandbox."
        case .kernelRejected:
            return "Kernel refused to issue a sandbox extension."
        case .asprintfFailed:
            return "Failed to build path traversal string."
        case .unknown(let code):
            return "bad_query failed with code \(code)."
        case .listFailed:
            return "Failed to enumerate containers (fsgetpath)."
        case .containerNotFound(let bundleId):
            return "Could not find container for \(bundleId)."
        }
    }
    
    public static func from(code: Int64) -> BadQueryError {
        switch code {
        case -255: return .invalidPath
        case -254: return .missingPath
        case -1: return .resolveFailed
        case -2: return .createFailed
        case -3: return .outsideSandbox
        case -4: return .kernelRejected
        case -5: return .asprintfFailed
        default: return .unknown(code)
        }
    }
}

/// RAII-style sandbox extension handle.
public final class BadQueryHandle {
    private(set) var handle: Int64
    public let path: String
    
    public init(handle: Int64, path: String) {
        self.handle = handle
        self.path = path
    }
    
    deinit {
        release()
    }
    
    public func release() {
        guard handle >= 0 else { return }
        bad_query_release(handle)
        handle = -1
    }
}

public let bq = BadQuery()

public class BadQuery {
    public static let shared = BadQuery()
    
    public static let posterBoardBundleId = "com.apple.PosterBoard"
    public static let carPlayWallpaperBundleId = "com.apple.CarPlayWallpaper"
    
    // MARK: - Availability Probe
    
    public static var isAvailable: Bool {
        let probe = "/var/mobile"
        var cPath = probe.utf8CString.map { Int8($0) }
        let result = bad_query(&cPath, true, nil, false, nil)
        if result >= 0 {
            bad_query_release(result)
            return true
        }
        if result == -3 || result == -4 || result == -254 {
            return true
        }
        return result != -1 && result != -2
    }
    
    // MARK: - Consume / Release
    
    @discardableResult
    public static func consume(
        path: String,
        create: Bool = false,
        groupIdentifier: String? = nil,
        isGroup: Bool = false
    ) throws -> BadQueryHandle {
        guard path.hasPrefix("/") else { throw BadQueryError.invalidPath }
        
        var cPath = path.utf8CString.map { Int8($0) }
        let handle: Int64
        if let group = groupIdentifier {
            var cGroup = group.utf8CString.map { Int8($0) }
            handle = bad_query(&cPath, create, &cGroup, isGroup, nil)
        } else {
            handle = bad_query(&cPath, create, nil, isGroup, nil)
        }
        
        guard handle >= 0 else {
            if !create && handle == -254 {
                return try consume(path: path, create: true, groupIdentifier: groupIdentifier, isGroup: isGroup)
            }
            throw BadQueryError.from(code: handle)
        }
        return BadQueryHandle(handle: handle, path: path)
    }
    
    // MARK: - Listing
    
    public static func list(path: String, maxInode: Int64 = 2_000_000) throws -> [String] {
        var cPath = path.utf8CString.map { Int8($0) }
        guard let raw = bad_query_list(&cPath, maxInode) else {
            throw BadQueryError.listFailed
        }
        defer { free(raw) }
        let str = String(cString: raw)
        return str
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Container Discovery
    
    private static let metadataFileName = ".com.apple.mobile_container_manager.metadata.plist"
    
    public static func readBundleId(fromContainerPath containerPath: String) -> String? {
        let metaPath = (containerPath as NSString).appendingPathComponent(metadataFileName)
        guard let token = try? consume(path: metaPath, create: true) else { return nil }
        defer { token.release() }
        
        guard let dict = NSDictionary(contentsOfFile: metaPath) as? [String: Any] else {
            let alt = (containerPath as NSString).appendingPathComponent("com.apple.mobile_container_manager.metadata.plist")
            if let altToken = try? consume(path: alt, create: true) {
                defer { altToken.release() }
                if let d = NSDictionary(contentsOfFile: alt) as? [String: Any] {
                    return d["MCMMetadataIdentifier"] as? String
                }
            }
            return nil
        }
        return dict["MCMMetadataIdentifier"] as? String
    }
    
    public static func findAppHash(bundleId targetBundleId: String, searchRoots: [String]? = nil) throws -> String {
        let roots = searchRoots ?? [
            "/var/mobile/Containers/Data/Application",
            "/var/mobile/Containers/Data/InternalDaemon",
            "/var/mobile/Containers/Data/PluginKitPlugin"
        ]
        
        for root in roots {
            let children: [String]
            do {
                children = try list(path: root)
            } catch {
                continue
            }
            
            for child in children {
                let uuid = (child as NSString).lastPathComponent
                let containerPath = "\(root)/\(uuid)"
                if let id = readBundleId(fromContainerPath: containerPath), id == targetBundleId {
                    return uuid
                }
            }
        }
        
        throw BadQueryError.containerNotFound(targetBundleId)
    }
    
    public static func findPosterBoardHash() throws -> String {
        try findAppHash(bundleId: posterBoardBundleId)
    }
    
    public static func findCarPlayHash() throws -> String {
        try findAppHash(bundleId: carPlayWallpaperBundleId)
    }
    
    // MARK: - Path Helpers
    
    public static func applicationContainerPath(appHash: String) -> String {
        "/var/mobile/Containers/Data/Application/\(appHash)"
    }
    
    public static func descriptorsPath(appHash: String, ext: String) -> String {
        let ver = SymHandler.getExtensionVersion()
        return applicationContainerPath(appHash: appHash)
            + "/Library/Application Support/PRBPosterExtensionDataStore/\(ver)/Extensions/\(ext)/descriptors"
    }
    
    public static func carPlayCachePath(appHash: String) -> String {
        applicationContainerPath(appHash: appHash)
            + "/Library/Caches/MappedImageCache/com.apple.CarPlayApp.wallpaper-images"
    }
    
    public static func copyItem(at source: URL, intoDestinationDirectory destDir: String, named name: String? = nil) throws {
        let destName = name ?? source.lastPathComponent
        let destURL = URL(fileURLWithPath: destDir).appendingPathComponent(destName)
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: source, to: destURL)
    }
    
    public static func ensureDirectory(at path: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) { return }
        
        let components = path.split(separator: "/").map(String.init)
        var built = ""
        var lastExisting = ""
        for part in components {
            built += "/" + part
            if fm.fileExists(atPath: built) {
                lastExisting = built
            }
        }
        
        if lastExisting.isEmpty {
            let handle = try consume(path: path, create: true)
            defer { handle.release() }
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            return
        }
        
        let handle = try consume(path: lastExisting, create: true)
        defer { handle.release() }
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    
    // MARK: - Shared Instance Helpers (used by PhoneThemer & Utilities)
    
    public func grantAccess(atPath directory: String, toFileName fileName: String = "") -> (Bool, Int64, String) {
        var dirCs = directory.utf8CString.map { Int8($0) }
        let res: Int64
        
        if !fileName.isEmpty {
            var fileNameCs = fileName.utf8CString.map { Int8($0) }
            res = bad_query(&dirCs, false, nil, false, &fileNameCs)
        } else {
            res = bad_query(&dirCs, false, nil, false, nil)
        }
        
        var errorString: String?
        switch res {
        case -1: errorString = "failed to resolve one or more functions"
        case -2: errorString = "failed to create sandbox query"
        case -3: errorString = "outside of containermanager's sandbox"
        case -4: errorString = "kernel rejected sandbox query"
        default: errorString = nil
        }
        
        let path = fileName.isEmpty ? directory : "\(directory)/\(fileName)"
        let fm = FileManager.default
        let isActuallyReadable = fm.isReadableFile(atPath: path)
        let isActuallyWritable = fm.isWritableFile(atPath: path)
        if !isActuallyWritable || !isActuallyReadable {
            errorString = "the file doesn't actually seem readable/writable to this app's sandbox"
        }
        
        if let errorString {
            return (false, res, errorString)
        } else {
            return (true, res, "succeeded")
        }
    }
    
    public func getPathsOfDir(atPath path: String, maxInode: Int64 = 100000) -> [String] {
        var array: [String] = []
        path.withCString { p in
            guard let res = bad_query_list(UnsafeMutablePointer(mutating: p), maxInode) else {
                return
            }
            defer { free(res) }
            
            let string = String(cString: res)
            array = string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        return array
    }
    
    public func getContainerPath(forMatch match: String) -> String {
        let appContainersPath = "/var/mobile/Containers/Data/Application"
        let containers = getPathsOfDir(atPath: appContainersPath)
        for path in containers {
            let url = URL(fileURLWithPath: path)
            if let appName = folderLabel(url: url) {
                if appName == match {
                    return url.path
                }
            }
        }
        return ""
    }
    
    public func folderLabel(url: URL) -> String? {
        let candidates = [
            url.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"),
            url.appendingPathComponent("com.apple.mobile_container_manager.metadata.plist")
        ]
        
        for u in candidates {
            if let data = try? Data(contentsOf: u), let id = metadataID(from: data) {
                return id
            }
        }
        
        for u in candidates {
            if let id = readMetaKey(at: u, key: "MCMMetadataIdentifier") {
                return id
            }
        }
        
        return nil
    }
    
    private func metadataID(from data: Data) -> String? {
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        return plist?["MCMMetadataIdentifier"] as? String
    }
    
    private func readMetaKey(at url: URL, key: String) -> String? {
        var path_c = url.path.utf8CString.map { Int8($0) }
        let handle = bad_query(&path_c, true, nil, false, nil)
        guard handle >= 0 else { return nil }
        defer { bad_query_release(handle) }
        
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        
        return plist[key] as? String
    }
}
