//
//  PhoneThemerView.swift
//  Amfeta-Board
//
//  Complete Phone Dialer Themer View ported from Erosion (by lunginspector)
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct PhoneThemerView: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var kpMgr = KeypadManager.shared

    @State private var selectedTabMode: Int = 0 // 0 = Individual Keys, 1 = Poster Slice
    @State private var showSizeAlert: Bool = false
    @State private var custW: Int = 225
    @State private var custH: Int = 225
    @State private var showFileImporter: Bool = false
    @State private var showResetConfirm: Bool = false
    @State private var showApplySuccess: Bool = false
    @State private var showApplyError: Bool = false

    @State private var selectedKeyID: KeypadID? = nil
    @State private var isSinglePhotoPickerPresented: Bool = false
    @State private var singlePhotoItem: PhotosPickerItem? = nil

    @State private var isPosterPickerPresented: Bool = false
    @State private var posterPhotoItem: PhotosPickerItem? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VPNWarningBanner(vm: vm)

                    topControlsView

                    if selectedTabMode == 0 {
                        gridSectionView
                    } else {
                        posterSliceCard
                            .padding(.horizontal)
                    }

                    actionButtonsView
                }
                .padding(.vertical)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            kpMgr.maskKeysIntoCircle(size: kpMgr.selectedSize, custW: custW, custH: custH)
                        } label: {
                            Label("Mask Keys to Circle", systemImage: "circle")
                        }

                        Button {
                            kpMgr.getCurrentKeypads(size: .defSize, saveOgData: true)
                        } label: {
                            Label("Get Current Keys", systemImage: "externaldrive")
                        }

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import Theme Archive", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            openApp(withBundleID: "com.apple.mobilephone")
                        } label: {
                            Label("Open Phone App", systemImage: "arrow.up.right.square")
                        }

                        Divider()

                        Button {
                            kpMgr.clearKeypads()
                        } label: {
                            Label("Clear Keys", systemImage: "xmark")
                        }

                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Label("Reset Keys", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    menuToolbarView
                }
            }
            .onAppear {
                kpMgr.ensureContainerAccess()
                kpMgr.getCurrentKeypads(size: kpMgr.selectedSize, saveOgData: true)
            }
            .onChange(of: kpMgr.selectedSize) { _, newSize in
                if newSize != .custom {
                    kpMgr.changeSizeOfKeypads(size: newSize)
                } else {
                    showSizeAlert = true
                }
            }
            .alert("Custom Keypad Dimension", isPresented: $showSizeAlert) {
                TextField("Width (50-2500)", value: $custW, format: .number)
                    .keyboardType(.numberPad)
                TextField("Height (50-2500)", value: $custH, format: .number)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) {
                    kpMgr.selectedSize = .defSize
                }
                Button("Set") {
                    kpMgr.changeSizeOfKeypads(size: .custom, custW: custW, custH: custH)
                }
            }
            .photosPicker(isPresented: $isSinglePhotoPickerPresented, selection: $singlePhotoItem, matching: .images)
            .onChange(of: singlePhotoItem) { _, newItem in
                Task {
                    if let item = newItem, let kpID = selectedKeyID {
                        if let img = await item.loadUIImage(maxDimension: 1024), let data = img.pngData() {
                            await MainActor.run {
                                let processedData = kpMgr.resizeAndRet(withData: data, newSize: kpMgr.selectedSize.float, isDefault: kpMgr.selectedSize == .defSize)
                                kpMgr.updateKeypadItem(forID: kpID, withData: processedData, ogData: data)
                                singlePhotoItem = nil
                            }
                        }
                    }
                }
                handleSinglePhoto(newItem)
            }
            .photosPicker(isPresented: $isPosterPickerPresented, selection: $posterPhotoItem, matching: .images)
            .onChange(of: posterPhotoItem) { _, newItem in
                Task {
                    if let item = newItem {
                        if let img = await item.loadUIImage(maxDimension: 2048) {
                            await MainActor.run {
                                kpMgr.posterImage = img
                                posterPhotoItem = nil
                            }
                        }
                    }
                }
                handlePosterPhoto(newItem)
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item, .zip, UTType(filenameExtension: "passthm") ?? .data]) { result in
                handleImport(result)
            }
            .confirmationDialog("Reset Phone Dialer Keys?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset All Keys", role: .destructive) {
                    resetKeypads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(KPMsg.resetWarn)
            }
            .alert("Successfully Applied Keys", isPresented: $showApplySuccess) {
                Button("Open Phone") {
                    openApp(withBundleID: "com.apple.mobilephone")
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(KPMsg.applyComp)
            }
            .alert("Failed to Apply Keys", isPresented: $showApplyError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not write keypad images to Phone app container. Ensure permissions and try again.")
            }
        }
    }

    // MARK: - Poster Slice Card
    // MARK: - Subviews

    private var topControlsView: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $selectedTabMode) {
                Text("Keypad Grid").tag(0)
                Text("Poster Slice").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedTabMode == 0 {
                HStack {
                    Text("Key Size")
                        .font(.subheadline.bold())
                    Spacer()
                    Picker("Size", selection: $kpMgr.selectedSize) {
                        ForEach(KPSize.allCases) { sz in
                            Text(sz.label + (sz == .custom ? " (\(custW)x\(custH))" : "")).tag(sz)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }

    private var gridSectionView: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach($kpMgr.mpKeypad) { $item in
                KeypadCell(
                    item: $item,
                    size: kpMgr.selectedSize,
                    onTap: {
                        selectedKeyID = item.kpID
                        isSinglePhotoPickerPresented = true
                    },
                    onClear: {
                        kpMgr.updateKeypadItem(forID: item.kpID, withData: Data(), ogData: Data())
                    }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var actionButtonsView: some View {
        VStack(spacing: 10) {
            Button {
                applyKeypads()
            } label: {
                HStack {
                    if kpMgr.isApplying {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(kpMgr.isApplying ? "Applying..." : "Apply Dialer Theme")
                        .bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(kpMgr.isApplying)

            HStack(spacing: 12) {
                Button {
                    openApp(withBundleID: "com.apple.mobilephone")
                } label: {
                    Label("Open Phone", systemImage: "arrow.up.right.square")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset Keys", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var menuToolbarView: some View {
        Menu {
            Button {
                kpMgr.maskKeysIntoCircle(size: kpMgr.selectedSize, custW: custW, custH: custH)
            } label: {
                Label("Mask Keys to Circle", systemImage: "circle")
            }

            Button {
                kpMgr.getCurrentKeypads(size: .defSize, saveOgData: true)
            } label: {
                Label("Get Current Keys", systemImage: "externaldrive")
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Import Theme Archive", systemImage: "square.and.arrow.down")
            }

            Button {
                openApp(withBundleID: "com.apple.mobilephone")
            } label: {
                Label("Open Phone App", systemImage: "arrow.up.right.square")
            }

            Divider()

            Button {
                kpMgr.clearKeypads()
            } label: {
                Label("Clear Keys", systemImage: "xmark")
            }

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset Keys", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    private var posterSliceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select a wallpaper to automatically slice across all 12 dialer keys:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                isPosterPickerPresented = true
            } label: {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text(kpMgr.posterImage != nil ? "Change Wallpaper Image" : "Choose Wallpaper Image")
                        .bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let poster = kpMgr.posterImage {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Button {
                    kpMgr.applyPosterSlice()
                    selectedTabMode = 0
                } label: {
                    Label("Slice Wallpaper to 12 Keys", systemImage: "square.grid.3x3.fill")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions
    // MARK: - Actions & Handlers

    private func handleSinglePhoto(_ item: PhotosPickerItem?) {
        guard let item = item, let kpID = selectedKeyID else { return }
        Task {
            if let img = await item.loadUIImage(maxDimension: 1024), let data = img.pngData() {
                await MainActor.run {
                    let processedData = kpMgr.resizeAndRet(withData: data, newSize: kpMgr.selectedSize.float, isDefault: kpMgr.selectedSize == .defSize)
                    kpMgr.updateKeypadItem(forID: kpID, withData: processedData, ogData: data)
                    singlePhotoItem = nil
                }
            }
        }
    }

    private func handlePosterPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let img = await item.loadUIImage(maxDimension: 2048) {
                await MainActor.run {
                    kpMgr.posterImage = img
                    posterPhotoItem = nil
                }
            }
        }
    }

    private func applyKeypads() {
        kpMgr.isApplying = true
        let pairingPath = PairingController.pairingFilePath()
        let hasPairing = vm.hasPairingFile && vm.vpnUp

        DispatchQueue.global(qos: .userInitiated).async {
            let ok = kpMgr.applyKeypadItems(hasPairing: hasPairing, pairingPath: pairingPath)
            DispatchQueue.main.async {
                kpMgr.isApplying = false
                if ok {
                    showApplySuccess = true
                } else {
                    showApplyError = true
                }
            }
        }
    }

    private func resetKeypads() {
        let pairingPath = PairingController.pairingFilePath()
        let hasPairing = vm.hasPairingFile && vm.vpnUp

        DispatchQueue.global(qos: .userInitiated).async {
            _ = kpMgr.resetKeypadItems(hasPairing: hasPairing, pairingPath: pairingPath)
            DispatchQueue.main.async {
                kpMgr.getCurrentKeypads(size: kpMgr.selectedSize, saveOgData: true)
                showApplySuccess = true
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            let ok = kpMgr.importTheme(fromURL: url)
            if ok {
                showApplySuccess = true
            } else {
                showApplyError = true
            }
        case .failure:
            showApplyError = true
        }
    }
}

// MARK: - Keypad Cell View
private struct KeypadCell: View {
    @Binding var item: KeypadItem
    let size: KPSize
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let img = item.uiImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(Color(uiColor: .secondarySystemFill))
                        .frame(width: 76, height: 76)

                    VStack(spacing: 0) {
                        Text(item.kpID.rawValue)
                            .font(.system(size: 28, weight: .medium, design: .default))
                            .foregroundStyle(.primary)

                        if !item.kpID.subtext.isEmpty {
                            Text(item.kpID.subtext)
                                .font(.system(size: 9, weight: .bold, design: .default))
                                .foregroundStyle(.secondary)
                                .tracking(1.2)
                        }
                    }
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onTap) {
                Label("Choose Photo", systemImage: "photo")
            }
            if !item.imgData.isEmpty {
                Button(role: .destructive, action: onClear) {
                    Label("Remove Custom Image", systemImage: "trash")
                }
            }
        }
    }
}
