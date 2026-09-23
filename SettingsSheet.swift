//
//  SettingsSheet.swift
//  Amfeta-Board
//
//  Settings sheet containing PC Pairing, Reset All Files, and Developer / Debug Interface.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showPCHelperSheet = false
    @State private var showFilePicker = false
    @State private var showResetAllConfirm = false
    @State private var showDeletePairingConfirm = false
    @State private var resetSuccessMessage: String? = nil

    @AppStorage("appTheme") private var appTheme: String = AppThemeChoice.pureBlack.rawValue
    @AppStorage("accentColor") private var accentColor: String = AppAccentColor.green.rawValue

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: PC Exploit
                Section("PC Exploit") {
                    HStack(spacing: 12) {
                        Image(systemName: vm.hasPairingFile ? "checkmark.seal.fill" : "desktopcomputer.and.arrow.down")
                            .font(.title2)
                            .foregroundStyle(vm.hasPairingFile ? .green : .blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.hasPairingFile ? "Paired & Ready" : "Not Paired with PC")
                                .font(.subheadline.bold())
                            Text(vm.hasPairingFile
                                 ? "\(vm.pairingFileName) (\(vm.pairingFileSizeString))"
                                 : "Run PC Helper on your computer to sync pairing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    Button {
                        showPCHelperSheet = true
                    } label: {
                        Label(vm.hasPairingFile ? "Open PC Exploit / Re-Pair" : "Start PC Exploit", systemImage: "bolt.horizontal.fill")
                            .font(.subheadline.bold())
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import .plist Pairing File", systemImage: "folder.badge.plus")
                            .font(.subheadline)
                    }

                    if vm.hasPairingFile {
                        Button(role: .destructive) {
                            showDeletePairingConfirm = true
                        } label: {
                            Label("Remove Pairing File", systemImage: "trash")
                                .font(.subheadline)
                        }
                    }
                }

                // Section 2: Appearance & Theme
                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        ForEach(AppThemeChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice.rawValue)
                        }
                    }

                    Picker("Accent Color", selection: $accentColor) {
                        ForEach(AppAccentColor.allCases) { choice in
                            Text(choice.rawValue).tag(choice.rawValue)
                        }
                    }
                }

                // Section 3: Reset & Clean
                Section("Reset & Cleanup") {
                    Button(role: .destructive) {
                        showResetAllConfirm = true
                    } label: {
                        Label("Reset All Files & Data", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.subheadline.bold())
                    }
                }

                // Section 4: Developer & Debug Mode
                Section("Developer & Debug Mode") {
                    NavigationLink {
                        DeveloperDebugView(vm: vm)
                    } label: {
                        Label("Developer Diagnostics & Logs", systemImage: "terminal.fill")
                            .font(.subheadline.bold())
                    }
                }

                // App Info & Links
                Section("About & Repository") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("v0.1.4 (AmfetamineB)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("System Version")
                        Spacer()
                        Text(UIDevice.current.systemVersion)
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/AIOsource/AmfetamineB")!) {
                        HStack {
                            Label("GitHub Repository", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://t.me/N1kotinow")!) {
                        HStack {
                            Label("Telegram: @N1kotinow", systemImage: "paperplane")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                }
            }
            .sheet(isPresented: $showPCHelperSheet) {
                PCHelperSheet()
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(allowedContentTypes: [
                    UTType(filenameExtension: "plist") ?? .propertyList,
                    UTType(filenameExtension: "mobiledevicepairing") ?? .data,
                    UTType(filenameExtension: "mobilepair") ?? .data,
                    UTType.propertyList,
                    UTType.xmlPropertyList
                ]) { pickedURL in
                    let success = vm.importPairingFile(from: pickedURL, originalName: pickedURL.lastPathComponent)
                    if !success {
                        vm.errorMessage = "Failed to read or save pairing file"
                    }
                }
            }
            .confirmationDialog("Delete pairing file?", isPresented: $showDeletePairingConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    vm.deletePairingFile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The active pairing file will be removed from the app.")
            }
            .confirmationDialog("Reset All Files & Data?", isPresented: $showResetAllConfirm, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) {
                    resetAllAppData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your pairing file, reset custom card and dialer skins, and clear temporary caches.")
            }
            .alert("Notice", isPresented: Binding(
                get: { resetSuccessMessage != nil },
                set: { if !$0 { resetSuccessMessage = nil } }
            )) {
                Button("OK") { resetSuccessMessage = nil }
            } message: {
                Text(resetSuccessMessage ?? "")
            }
        }
    }

    private func resetAllAppData() {
        vm.deletePairingFile()
        vm.resetAllCards()
        KeypadManager.shared.clearKeypads()

        // Clear Documents tmp files
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            if let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
                for f in files {
                    if f.pathExtension == "tmp" || f.lastPathComponent.contains("temp") {
                        try? fm.removeItem(at: f)
                    }
                }
            }
        }

        resetSuccessMessage = "All files, pairing data, and custom skins have been reset."
        vm.log.append("[+] All app files and data reset successfully.")
    }
}

// MARK: - Developer & Debug View
struct DeveloperDebugView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        Form {
            Section("Network & VPN Diagnostics") {
                HStack {
                    Text("VPN Status")
                    Spacer()
                    Text(vm.vpnUp ? "Connected (10.7.0.1)" : "Disconnected")
                        .foregroundStyle(vm.vpnUp ? .green : .red)
                        .bold()
                }
                HStack {
                    Text("Local Network Auth")
                    Spacer()
                    Text("Allowed")
                        .foregroundStyle(.green)
                }
                Button(vm.vpnUp ? "Disconnect LocalDev VPN" : "Connect LocalDev VPN") {
                    if vm.vpnUp {
                        disconnectLoopbackVPN()
                    } else {
                        connectLoopbackVPN()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        vm.refreshNetworkStatus()
                    }
                }
                .bold()
            }

            Section("Device & Exploit Info") {
                HStack {
                    Text("Device Model")
                    Spacer()
                    Text(UIDevice.current.model)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("System Version")
                    Spacer()
                    Text(UIDevice.current.systemVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Pairing File Loaded")
                    Spacer()
                    Text(vm.hasPairingFile ? "Yes (\(vm.pairingFileName))" : "No")
                        .foregroundStyle(vm.hasPairingFile ? .green : .orange)
                }
            }

            Section("Diagnostic Log (\(vm.log.count) lines)") {
                CompactLogView(
                    title: "Live Console",
                    lines: vm.log,
                    onClear: { vm.log.removeAll() }
                )
            }
        }
        .navigationTitle("Developer Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

