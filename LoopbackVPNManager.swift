//
//  LoopbackVPNManager.swift
//  Amfeta-Board
//
//  LocalDevVPN Redirect & Controller.
//  Triggers localdevvpn://enable?scheme=amfetaboard and localdevvpn://disable?scheme=amfetaboard.
//

import Foundation
import UIKit

final class LoopbackVPNManager: ObservableObject {
    static let shared = LoopbackVPNManager()

    @Published var isEnabled: Bool = false
    @Published var statusMessage: String = "Disconnected"

    private init() {}

    func connect() {
        let enableURLs = [
            "localdevvpn://enable?scheme=amfetaboard",
            "localdevvpn://enable?scheme=amfetaspoit",
            "localdevvpn://connect",
            "localdevvpn://"
        ]

        for str in enableURLs {
            if let url = URL(string: str), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }

        if openApp(withBundleID: "com.theos.localdevvpn") ||
           openApp(withBundleID: "com.macless.localdevvpn") ||
           openApp(withBundleID: "com.apple.localdevvpn") {
            return
        }

        if let appStoreURL = URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044") {
            UIApplication.shared.open(appStoreURL)
        }
    }

    func disconnect() {
        let disableURLs = [
            "localdevvpn://disable?scheme=amfetaboard",
            "localdevvpn://disconnect",
            "localdevvpn://disable"
        ]
        for str in disableURLs {
            if let url = URL(string: str), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
}
