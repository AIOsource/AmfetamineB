//
//  PhoneThemerModel.swift
//  Amfeta-Board
//
//  Complete Phone Dialer Themer Model ported from Erosion (by lunginspector)
//  with direct container bad_query bypass and RSD pairing dual-write support.
//

import Combine
import Foundation
import UIKit
import SwiftUI
import AirliftFFI

enum KeypadID: String, CaseIterable, Identifiable {
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case star = "*"
    case zero = "0"
    case pound = "#"

    var id: String { rawValue }

    var keyPattern: String {
        switch self {
        case .one: return "-1-"
        case .two: return "-2-A B C"
        case .three: return "-3-D E F"
        case .four: return "-4-G H I"
        case .five: return "-5-J K L"
        case .six: return "-6-M N O"
        case .seven: return "-7-P Q R S"
        case .eight: return "-8-T U V"
        case .nine: return "-9-W X Y Z"
        case .star: return "-*-"
        case .zero: return "-0-+"
        case .pound: return "-#-"
        }
    }

    var subtext: String {
        switch self {
        case .one: return ""
        case .two: return "A B C"
        case .three: return "D E F"
        case .four: return "G H I"
        case .five: return "J K L"
        case .six: return "M N O"
        case .seven: return "P Q R S"
        case .eight: return "T U V"
        case .nine: return "W X Y Z"
        case .star: return ""
        case .zero: return "+"
        case .pound: return ""
        }
    }

    func fileNames(regCode: String) -> [String] {
        let suffixes = ["--mask.png", "--white.png", "-hi-mask.png", "-hi-white.png", "--white-bold.png", "--mask-bold.png"]
        return suffixes.map { regCode + keyPattern + $0 }
    }

    func getAccentedFileName(regCode: String) -> String {
        let appearance = UIScreen.main.traitCollection.userInterfaceStyle
        let names = fileNames(regCode: regCode)
        switch appearance {
        case .light: return names.indices.contains(0) ? names[0] : "\(regCode)\(keyPattern)--mask.png"
        case .dark: return names.indices.contains(1) ? names[1] : "\(regCode)\(keyPattern)--white.png"
        default: return names.indices.contains(0) ? names[0] : "\(regCode)\(keyPattern)--mask.png"
        }
    }
}

enum KPSize: Int, CaseIterable, Identifiable {
    case defSize, small, medium, large, custom
    var id: Int { rawValue }

    var float: CGFloat {
        switch self {
        case .small: return CGFloat(150)
        case .medium: return CGFloat(205)
        case .large: return CGFloat(225)
        default: return CGFloat(0)
        }
    }

    var label: String {
        switch self {
        case .defSize: return "Default"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .custom: return "Custom"
        }
    }
}

enum KPSizeLimits {
    static let min = CGFloat(50)
    static let max = CGFloat(2500)
}

struct KeypadItem: Identifiable, Equatable {
    let id = UUID()
    var kpID: KeypadID
    var imgData = Data()
    var ogImgData = Data()

    var uiImage: UIImage? {
        if !imgData.isEmpty {
            return UIImage(data: imgData)
        }
        return nil
    }
}

let emptyKeypadArray: [KeypadItem] = KeypadID.allCases.map {
    KeypadItem(kpID: $0)
}

enum KPMsg {
    static let resetWarn = "You will lose both what you are currently editing and what you have already set inside of the Phone app."
    static let applyComp = "For changes to take effect, open the Phone app and change the appearance until your custom keys show up. You can also tap Respring. Do NOT force kill the Phone app!"
}

final class KeypadManager: ObservableObject {
    static let shared = KeypadManager()

    @Published var mpKeypad: [KeypadItem] = emptyKeypadArray
    @Published var selectedSize: KPSize = .defSize
    @Published var custW: Int = 225
    @Published var custH: Int = 225
    @Published var isApplying: Bool = false
    @Published var statusLog: [String] = []

    // Poster slice support
    @Published var posterImage: UIImage? = nil
    @Published var posterZoom: CGFloat = 1.0
    @Published var posterOffset: CGPoint = .zero

    private var mpContainerPath: String {
        let saved = UserDefaults.standard.string(forKey: "mpContainerPath") ?? ""
        if !saved.isEmpty && FileManager.default.fileExists(atPath: saved) {
            return saved
        }
        let discovered = BadQuery.shared.getContainerPath(forMatch: "com.apple.mobilephone")
        if !discovered.isEmpty {
            UserDefaults.standard.set(discovered, forKey: "mpContainerPath")
            return discovered
        }
        return saved
    }

    init() {
        if mpKeypad.isEmpty {
            mpKeypad = emptyKeypadArray
        }
    }

    func ensureContainerAccess() {
        let path = mpContainerPath
        if !path.isEmpty {
            let fm = FileManager.default
            if !fm.isReadableFile(atPath: path) {
                _ = BadQuery.shared.grantAccess(atPath: path)
            }
            let cacheDir = URL(fileURLWithPath: path).appendingPathComponent("Library/Caches/TelephonyUI-10")
            try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    func getFileRegCode() -> String {
        let path = mpContainerPath
        guard !path.isEmpty else { return "other" }
        let tpURL = URL(fileURLWithPath: path).appendingPathComponent("Library/Caches/TelephonyUI-10")
        if let tpURLs = try? FileManager.default.contentsOfDirectory(at: tpURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for file in tpURLs {
                let split = file.lastPathComponent.split(separator: "-")
                if split.count >= 2 {
                    return String(split[0])
                }
            }
        }
        return "other"
    }

    func updateKeypadItem(forID id: KeypadID, withData data: Data, ogData: Data? = nil) {
        if let index = mpKeypad.firstIndex(where: { $0.kpID == id }) {
            mpKeypad[index].imgData = data
            if let data = ogData {
                mpKeypad[index].ogImgData = data
            }
        }
    }

    func resizeAndRet(withData data: Data, newSize: CGFloat = CGFloat(0), customSize: CGSize? = nil, shallCircle: Bool = false, isDefault: Bool = false) -> Data {
        guard let image = UIImage(data: data) else { return data }
        var width = isDefault ? image.size.width : customSize?.width ?? newSize
        var height = isDefault ? image.size.height : customSize?.height ?? newSize
        if width <= 0 { width = 225 }
        if height <= 0 { height = 225 }
        width = min(max(width, KPSizeLimits.min), KPSizeLimits.max)
        height = min(max(height, KPSizeLimits.min), KPSizeLimits.max)
        let resized = image.resized(to: CGSize(width: width, height: height), shouldCircle: shallCircle)
        return resized.pngData() ?? data
    }

    func getCurrentKeypads(size: KPSize = .defSize, custW: Int = 0, custH: Int = 0, saveOgData: Bool = false) {
        let path = mpContainerPath
        guard !path.isEmpty else { return }
        ensureContainerAccess()
        let reg = getFileRegCode()
        let filesURL = URL(fileURLWithPath: path).appendingPathComponent("Library/Caches/TelephonyUI-10")

        for kpId in KeypadID.allCases {
            let fileName = kpId.getAccentedFileName(regCode: reg)
            let url = filesURL.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                let imgData = {
                    switch size {
                    case .defSize: return resizeAndRet(withData: data, isDefault: true)
                    case .custom: return resizeAndRet(withData: data, customSize: CGSize(width: custW, height: custH))
                    default: return resizeAndRet(withData: data, newSize: size.float)
                    }
                }()
                if saveOgData {
                    updateKeypadItem(forID: kpId, withData: imgData, ogData: imgData)
                } else {
                    updateKeypadItem(forID: kpId, withData: imgData)
                }
            }
        }
    }

    func changeSizeOfKeypads(size: KPSize = .defSize, custW: Int = 0, custH: Int = 0) {
        selectedSize = size
        for kpItem in mpKeypad {
            let data = kpItem.ogImgData.isEmpty ? kpItem.imgData : kpItem.ogImgData
            guard !data.isEmpty else { continue }
            let imgData = {
                switch size {
                case .defSize: return resizeAndRet(withData: data, isDefault: true)
                case .custom: return resizeAndRet(withData: data, customSize: CGSize(width: custW, height: custH))
                default: return resizeAndRet(withData: data, newSize: size.float)
                }
            }()
            updateKeypadItem(forID: kpItem.kpID, withData: imgData)
        }
    }

    func maskKeysIntoCircle(size: KPSize = .defSize, custW: Int = 0, custH: Int = 0) {
        for kpItem in mpKeypad {
            let data = kpItem.ogImgData.isEmpty ? kpItem.imgData : kpItem.ogImgData
            guard !data.isEmpty else { continue }
            let imgData = {
                switch size {
                case .defSize: return resizeAndRet(withData: data, shallCircle: true, isDefault: true)
                case .custom: return resizeAndRet(withData: data, customSize: CGSize(width: custW, height: custH), shallCircle: true)
                default: return resizeAndRet(withData: data, newSize: size.float, shallCircle: true)
                }
            }()
            updateKeypadItem(forID: kpItem.kpID, withData: imgData)
        }
    }

    func clearKeypads() {
        for idx in mpKeypad.indices {
            mpKeypad[idx].ogImgData = Data()
            mpKeypad[idx].imgData = Data()
        }
        posterImage = nil
    }

    func applyPosterSlice() {
        guard let poster = posterImage else { return }
        let sliced = ImageEngine.slicePoster(
            image: poster,
            zoom: posterZoom,
            offset: posterOffset,
            maskToCircles: true
        )
        for (digitStr, img) in sliced {
            if let kpID = KeypadID(rawValue: digitStr), let data = img.pngData() {
                updateKeypadItem(forID: kpID, withData: data, ogData: data)
            }
        }
    }

    // Direct write + RSD write
    func applyKeypadItems(hasPairing: Bool = false, pairingPath: String = "") -> Bool {
        ensureContainerAccess()
        let reg = getFileRegCode()
        let fm = FileManager.default
        let container = mpContainerPath
        var directWritten = 0
        var directFailed = 0

        // 1. Direct filesystem write to MobilePhone app container
        if !container.isEmpty {
            _ = BadQuery.shared.grantAccess(atPath: container)
            let cacheURL = URL(fileURLWithPath: container).appendingPathComponent("Library/Caches/TelephonyUI-10")
            try? fm.createDirectory(at: cacheURL, withIntermediateDirectories: true)

            for item in mpKeypad {
                guard !item.imgData.isEmpty else { continue }
                let files = item.kpID.fileNames(regCode: reg)
                for fileName in files {
                    let finalURL = cacheURL.appendingPathComponent(fileName)
                    do {
                        try item.imgData.write(to: finalURL, options: .atomic)
                        directWritten += 1
                    } catch {
                        print("[kp] failed to write image data to container: \(error.localizedDescription)")
                        directFailed += 1
                    }
                }
            }
        }

        // 2. Dual-write via RSD pairing if active
        if hasPairing && !pairingPath.isEmpty && fm.fileExists(atPath: pairingPath) {
            let stageDir = fm.temporaryDirectory.appendingPathComponent("kp_stage_\(UUID().uuidString)")
            try? fm.createDirectory(at: stageDir, withIntermediateDirectories: true)

            let versions = ["TelephonyUI-10", "TelephonyUI-9", "TelephonyUI-8"]
            for item in mpKeypad {
                guard !item.imgData.isEmpty else { continue }
                for ver in versions {
                    let verDir = stageDir.appendingPathComponent(ver)
                    try? fm.createDirectory(at: verDir, withIntermediateDirectories: true)
                    for fileName in item.kpID.fileNames(regCode: reg) {
                        let fileURL = verDir.appendingPathComponent(fileName)
                        try? item.imgData.write(to: fileURL)
                    }
                    for fileName in item.kpID.fileNames(regCode: "other") {
                        let fileURL = verDir.appendingPathComponent(fileName)
                        try? item.imgData.write(to: fileURL)
                    }
                }
            }

            let targetCache = "/var/mobile/Library/Caches"
            _ = pairingPath.withCString { pairC in
                stageDir.path.withCString { srcC in
                    targetCache.withCString { tgtC in
                        al_exploit_write_dir(pairC, srcC, tgtC, nil, nil, nil)
                    }
                }
            }
            try? fm.removeItem(at: stageDir)
        }

        RespringHelper.flushPreferenceCaches()
        return directWritten > 0 || (hasPairing && directFailed == 0)
    }

    func resetKeypadItems(hasPairing: Bool = false, pairingPath: String = "") -> Bool {
        let container = mpContainerPath
        let fm = FileManager.default
        var directCleaned = false

        if !container.isEmpty {
            _ = BadQuery.shared.grantAccess(atPath: container)
            let cacheURL = URL(fileURLWithPath: container).appendingPathComponent("Library/Caches/TelephonyUI-10")
            if let files = try? fm.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: []) {
                for fileURL in files {
                    try? fm.removeItem(at: fileURL)
                }
                directCleaned = true
            }
        }

        if hasPairing && !pairingPath.isEmpty && fm.fileExists(atPath: pairingPath) {
            let emptyDir = fm.temporaryDirectory.appendingPathComponent("kp_empty_\(UUID().uuidString)")
            try? fm.createDirectory(at: emptyDir.appendingPathComponent("TelephonyUI-10"), withIntermediateDirectories: true)
            let targetCache = "/var/mobile/Library/Caches"
            _ = pairingPath.withCString { pairC in
                emptyDir.path.withCString { srcC in
                    targetCache.withCString { tgtC in
                        al_exploit_write_dir(pairC, srcC, tgtC, nil, nil, nil)
                    }
                }
            }
            try? fm.removeItem(at: emptyDir)
        }

        clearKeypads()
        RespringHelper.flushPreferenceCaches()
        return directCleaned || hasPairing
    }

    // Import theme from .zip or .passthm
    func importTheme(fromURL fileURL: URL) -> Bool {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("theme_\(UUID().uuidString)")
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let rc = fileURL.path.withCString { arcC in
            tempDir.path.withCString { dstC in
                al_passthm_extract(arcC, dstC)
            }
        }
        guard rc == 0 else {
            print("[kp] failed to extract theme archive")
            return false
        }

        let allFiles = (fm.subpaths(atPath: tempDir.path) ?? [])
        var replaceCount = 0

        for file in allFiles {
            guard !file.hasPrefix("."), !file.contains("__MACOSX") else { continue }
            let lower = file.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") else { continue }

            let fullPath = tempDir.appendingPathComponent(file).path
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)), !data.isEmpty else { continue }

            let filename = (file as NSString).lastPathComponent
            let split = filename.split(separator: "-").map { String($0) }
            let fileForAppr = UIScreen.main.traitCollection.userInterfaceStyle == .dark ? "white" : "mask"

            var apprName = ""
            if split.indices.contains(3) {
                let appearance = split[3].split(separator: ".")[0]
                if appearance == fileForAppr { apprName = split[3] }
            }
            if split.indices.contains(2) && apprName.isEmpty {
                let appearance = split[2].split(separator: ".")[0]
                if appearance == fileForAppr { apprName = split[2] }
            }

            if split.indices.contains(1) {
                let keyNum = split[1]
                if let id = KeypadID.allCases.first(where: {
                    $0.fileNames(regCode: "other").contains { $0.contains(keyNum) && (apprName.isEmpty || $0.contains(apprName)) }
                }) {
                    updateKeypadItem(forID: id, withData: data, ogData: data)
                    replaceCount += 1
                    continue
                }
            }

            // Fallback: match digit from filename
            if let digit = PasscodeThemeReader.extractDigit(from: filename),
               let id = KeypadID(rawValue: digit) {
                updateKeypadItem(forID: id, withData: data, ogData: data)
                replaceCount += 1
            }
        }

        print("[kp] successfully imported theme: \(fileURL.lastPathComponent), keys matched: \(replaceCount)")
        return replaceCount > 0
    }
}

extension UIImage {
    func resized(to size: CGSize, scale: CGFloat = 1.0, shouldCircle: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext

            if shouldCircle {
                ctx.addEllipse(in: CGRect(origin: .zero, size: size))
                ctx.clip()

                let fillScale = max(size.width / self.size.width, size.height / self.size.height)
                let drawSize = CGSize(width: self.size.width * fillScale, height: self.size.height * fillScale)
                let origin = CGPoint(
                    x: (size.width - drawSize.width) / 2,
                    y: (size.height - drawSize.height) / 2
                )
                draw(in: CGRect(origin: origin, size: drawSize))
            } else {
                draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }
}

