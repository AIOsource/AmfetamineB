import SwiftUI
import AirliftFFI

@main
struct AirCardApp: App {
    @StateObject private var vm = AppViewModel()

    init() {
        // Route Rust tracing/idevice logs into the app's vm log array.
        al_log_init({ _, msg in
            guard let msg = msg else { return }
            let line = String(cString: msg)
            DispatchQueue.main.async {
                AppViewModel.sharedLogSink?(line)
            }
        }, nil)

        // Point the sink at the vm once it's created (set in AppViewModel.init).
        // Ensure ALGetGrappaToken symbol is retained and linked into the binary
        _ = ALGetGrappaToken(0, 0, 0, nil, 0, nil, nil, 0)
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appTheme") private var appTheme: String = AppThemeChoice.pureBlack.rawValue
    @AppStorage("accentColor") private var accentColor: String = AppAccentColor.green.rawValue

    private var currentTheme: AppThemeChoice {
        AppThemeChoice(rawValue: appTheme) ?? .pureBlack
    }

    private var currentAccent: AppAccentColor {
        AppAccentColor(rawValue: accentColor) ?? .green
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .preferredColorScheme(currentTheme.colorScheme)
                .tint(currentAccent.color)
                .background(currentTheme == .pureBlack ? Color.black : Color(uiColor: .systemBackground))
                .task {
                    // Start PC Helper local listener
                    PCHelperSync.shared.start()
                    // Trigger iOS local network permission prompt immediately on launch
                    _ = await LocalNetworkAuthorization().request(timeout: 2.5)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        vm.refreshNetworkStatus()
                        vm.refreshPairingFile()
                    }
                }
        }
    }
}

@_silgen_name("ALGetGrappaToken")
func ALGetGrappaToken(
    _ inVersion: UInt32,
    _ inDeviceType: UInt32,
    _ inProtocolVersion: UInt32,
    _ outBuf: UnsafeMutablePointer<UInt8>?,
    _ maxLen: Int,
    _ outLen: UnsafeMutablePointer<Int>?,
    _ errBuf: UnsafeMutablePointer<CChar>?,
    _ errLen: Int
) -> Int32
