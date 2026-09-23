import SwiftUI

struct PCHelperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync = PCHelperSync.shared
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "desktopcomputer.and.arrow.down")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue)

                        Text("Amfeta-Spoit PC Helper")
                            .font(.title2.bold())

                        Text("Automatic USB & Network Pairing Sync")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)

                    // Live Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Sync Server Status", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption.bold().uppercaseSmallCaps())
                                .foregroundStyle(.blue)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(sync.isListening ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(sync.isListening ? "Active" : "Offline")
                                    .font(.caption.bold())
                                    .foregroundStyle(sync.isListening ? .green : .orange)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(sync.isListening ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                        }

                        Text(sync.statusMessage)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.primary)

                        if vm.hasPairingFile {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Active file: \(vm.pairingFileName)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Step by step guide
                    VStack(alignment: .leading, spacing: 14) {
                        Text("HOW TO PAIR WITH PC HELPER")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        StepRow(
                            number: "1",
                            title: "Connect iPhone to PC",
                            detail: "Plug in via USB cable and tap 'Trust This Computer' on your iPhone if prompted."
                        )

                        StepRow(
                            number: "2",
                            title: "Launch PC Helper",
                            detail: "On your PC/Mac, run: python3 pc-helper/app.py in terminal."
                        )

                        StepRow(
                            number: "3",
                            title: "Click 'Exploit / Pair'",
                            detail: "In the PC Helper window, wait until status says 'Connected', then click 'Exploit / Pair'."
                        )

                        StepRow(
                            number: "4",
                            title: "Ready to Apply",
                            detail: "The PC Helper will say 'Ready' and Amfeta-Board will automatically adopt the pairing file!"
                        )
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button {
                        sync.start()
                        vm.refreshPairingFile()
                    } label: {
                        Label("Restart Listener / Refresh", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("PC Pair Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline.bold())
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

