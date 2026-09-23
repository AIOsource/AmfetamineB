//
//  PosterBoardViews.swift
//  Amfeta-Board
//
//  Complete PosterBoard (Bad-Poster) interface with Tendies, Live Video, CarPlay and Explore tabs.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import AVKit

// MARK: - Root PosterBoard View with Back Button

public struct PosterBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedTab: PosterBoardTab = .wallpapers

    public enum PosterBoardTab: Int, CaseIterable, Identifiable {
        case wallpapers = 0
        case liveVideo = 1
        case carPlay = 2
        case explore = 3

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .wallpapers: return "Wallpapers"
            case .liveVideo: return "Live Video"
            case .carPlay: return "CarPlay"
            case .explore: return "Explore"
            }
        }

        public var icon: String {
            switch self {
            case .wallpapers: return "photo.stack"
            case .liveVideo: return "video"
            case .carPlay: return "car"
            case .explore: return "safari"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Segmented Picker
                Picker("Section", selection: $selectedTab) {
                    ForEach(PosterBoardTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)

                // Sub-view contents
                Group {
                    switch selectedTab {
                    case .wallpapers:
                        PosterBoardWallpapersTab()
                    case .liveVideo:
                        PosterBoardVideoTab()
                    case .carPlay:
                        PosterBoardCarPlayTab()
                    case .explore:
                        PosterBoardExploreTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("PosterBoard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.bold())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.respring()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Respring")
                        }
                        .font(.subheadline.bold())
                    }
                }
            }
        }
    }
}

// MARK: - Tab 1: Wallpapers & Tendies

struct PosterBoardWallpapersTab: View {
    @AppStorage("pbHash") var pbHash: String = ""
    @ObservedObject var pbManager = PosterBoardManager.shared
    @State private var showTendiesPicker = false
    @State private var isApplying = false
    @State private var isResetting = false

    var body: some View {
        List {
            Section {
                Button {
                    showTendiesPicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Select Tendies / Zip")
                                .font(.headline)
                            Text("Import .tendies or .zip wallpaper packages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Import")
            }

            if !pbManager.selectedTendies.isEmpty {
                Section("Selected Packages (\(pbManager.selectedTendies.count))") {
                    ForEach(pbManager.selectedTendies, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.zipper")
                                .foregroundStyle(.blue)
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                    }
                    .onDelete { indexSet in
                        pbManager.selectedTendies.remove(atOffsets: indexSet)
                    }
                }
            }

            Section("PosterBoard Target") {
                HStack {
                    Text("Container Hash:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Auto-detect via bad_query", text: $pbHash)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                    if !pbHash.isEmpty {
                        Button {
                            pbHash = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if pbHash.isEmpty {
                    Text("Auto-detection active: PosterBoard hash will be resolved automatically using bad_query.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                Button {
                    applyTendies()
                } label: {
                    HStack {
                        Spacer()
                        if isApplying {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 6)
                        }
                        Image(systemName: "checkmark.circle.fill")
                        Text(isApplying ? "Applying & Respringing…" : "Apply Tendies")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(isApplying || (pbManager.selectedTendies.isEmpty && pbManager.videos.isEmpty))
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                Button(role: .destructive) {
                    resetCollections()
                } label: {
                    HStack {
                        Spacer()
                        if isResetting {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 6)
                        }
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                        Text(isResetting ? "Resetting…" : "Reset Poster Collections")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(isResetting)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                Button {
                    _ = pbManager.openPosterBoard()
                } label: {
                    Label("Open PosterBoard App", systemImage: "arrow.up.forward.app")
                }
            }
        }
        .sheet(isPresented: $showTendiesPicker) {
            DocumentPickerView(allowedContentTypes: [
                UTType(filenameExtension: "tendies") ?? .data,
                UTType(filenameExtension: "zip") ?? .zip,
                UTType.zip,
                UTType.data
            ]) { url in
                pbManager.selectedTendies.append(url)
            }
        }
    }

    private func applyTendies() {
        isApplying = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var hash = pbHash
                if hash.isEmpty {
                    hash = try BadQuery.findPosterBoardHash()
                    DispatchQueue.main.async { pbHash = hash }
                }
                try pbManager.applyTendies(appHash: hash)
                SymHandler.cleanup()
                try? FileManager.default.removeItem(at: pbManager.getTendiesStoreURL())

                DispatchQueue.main.async {
                    pbManager.selectedTendies.removeAll()
                    pbManager.videos.removeAll()
                    isApplying = false
                    RespringHelper.respring()
                }
            } catch {
                DispatchQueue.main.async {
                    isApplying = false
                    UIApplication.shared.alert(title: "Apply Failed", body: error.localizedDescription)
                }
            }
        }
    }

    private func resetCollections() {
        isResetting = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var hash = pbHash
                if hash.isEmpty {
                    hash = try BadQuery.findPosterBoardHash()
                    DispatchQueue.main.async { pbHash = hash }
                }
                try pbManager.resetCollections(appHash: hash)
                DispatchQueue.main.async {
                    isResetting = false
                    RespringHelper.respring()
                }
            } catch {
                DispatchQueue.main.async {
                    isResetting = false
                    UIApplication.shared.alert(title: "Reset Failed", body: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Tab 2: Live Video Wallpapers

struct PosterBoardVideoTab: View {
    @ObservedObject var pbManager = PosterBoardManager.shared
    @State private var selectedVideo: PhotosPickerItem?
    @State private var currentPage: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            if pbManager.videos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    Text("No Video Wallpapers Added")
                        .font(.headline)
                    Text("Select an MP4 video (up to 12s) to convert into an animated lock screen Live Wallpaper.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)

                    PhotosPicker(selection: $selectedVideo, matching: .videos) {
                        Label("Choose Video from Photos", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geom in
                    TabView(selection: $currentPage) {
                        ForEach(Array(pbManager.videos.enumerated()), id: \.offset) { idx, vid in
                            VStack {
                                switch vid.loadState {
                                case .loading:
                                    ProgressView()
                                case .loaded(let movie):
                                    PlayerView(videoURL: movie.url)
                                        .frame(width: geom.size.width * 0.75, height: geom.size.height * 0.7)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                case .failed:
                                    Text("Failed to load video")
                                        .foregroundStyle(.red)
                                case .unknown:
                                    EmptyView()
                                }

                                HStack {
                                    Button {
                                        pbManager.videos[idx].autoReverses.toggle()
                                    } label: {
                                        Label(vid.autoReverses ? "Auto-Reverse: On" : "Auto-Reverse: Off",
                                              systemImage: "arrow.left.arrow.right")
                                            .font(.caption.bold())
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(vid.autoReverses ? .blue : .secondary)

                                    Spacer()

                                    Button(role: .destructive) {
                                        pbManager.videos.remove(at: idx)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.horizontal, 40)
                            }
                            .tag(idx)
                        }
                    }
                    .tabViewStyle(.page)
                }

                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    Label("Add Another Video", systemImage: "plus")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: selectedVideo) { _, newItem in
            guard let newItem else { return }
            let id = pbManager.videos.count
            pbManager.videos.append(.init(loadState: .loading))
            Task {
                if let movie = try? await newItem.loadTransferable(type: Movie.self) {
                    await MainActor.run {
                        if VideoHandler.isVideoTooLong(at: movie.url) {
                            pbManager.videos.remove(at: id)
                            UIApplication.shared.alert(title: "Video Too Long", body: "Video must be 12 seconds or less.")
                        } else {
                            pbManager.videos[id].loadState = .loaded(movie)
                            currentPage = id
                        }
                    }
                } else {
                    await MainActor.run {
                        pbManager.videos[id].loadState = .failed
                    }
                }
                selectedVideo = nil
            }
        }
    }
}

// MARK: - Tab 3: CarPlay Wallpapers

struct PosterBoardCarPlayTab: View {
    @AppStorage("cpHash") var cpHash: String = ""
    @State private var wallpapers: [CarPlayWallpaper] = []
    @State private var isApplying: Bool = false

    var body: some View {
        List {
            Section("CarPlay Container") {
                HStack {
                    Text("CarPlay App Hash:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Auto-detect via bad_query", text: $cpHash)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                }
            }

            Section("CarPlay Wallpapers") {
                Text("Customize CarPlay head unit wallpaper assets and inject via bad_query.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    applyCarPlay()
                } label: {
                    HStack {
                        Spacer()
                        if isApplying { ProgressView().tint(.white).padding(.trailing, 6) }
                        Image(systemName: "car.fill")
                        Text(isApplying ? "Applying…" : "Apply CarPlay Wallpapers")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(isApplying)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }

    private func applyCarPlay() {
        isApplying = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var hash = cpHash
                if hash.isEmpty {
                    hash = try BadQuery.findCarPlayHash()
                    DispatchQueue.main.async { cpHash = hash }
                }
                try CarPlayManager.applyCarPlay(appHash: hash, wallpapers: wallpapers)
                SymHandler.cleanup()
                DispatchQueue.main.async {
                    isApplying = false
                    UIApplication.shared.alert(title: "Success", body: "CarPlay wallpapers applied successfully.")
                }
            } catch {
                DispatchQueue.main.async {
                    isApplying = false
                    UIApplication.shared.alert(title: "Apply Failed", body: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Tab 4: Explore Wallpapers

struct PosterBoardExploreTab: View {
    @ObservedObject var api = CowabungaAPI.shared
    @State private var wallpapers: [DownloadableWallpaper] = []
    @State private var isLoading = false
    @State private var searchTerm = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search wallpapers…", text: $searchTerm)
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            if isLoading && wallpapers.isEmpty {
                Spacer()
                ProgressView("Loading Wallpapers…")
                Spacer()
            } else if wallpapers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "globe")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Explore Online Wallpapers")
                        .font(.headline)
                    Button("Fetch Wallpapers") {
                        loadWallpapers()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        ForEach(filteredWallpapers) { wp in
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: api.getPreviewURLForWallpaper(wallpaper: wp)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        Color.gray.opacity(0.3)
                                    case .empty:
                                        ProgressView()
                                    @unknown default:
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                Text(wp.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)

                                Button {
                                    DownloadManager.shared.startTendiesDownload(for: api.getDownloadURLForWallpaper(wallpaper: wp))
                                } label: {
                                    Label("Download", systemImage: "arrow.down.circle")
                                        .font(.caption2.bold())
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }
                            .padding(8)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            if wallpapers.isEmpty {
                loadWallpapers()
            }
        }
    }

    private var filteredWallpapers: [DownloadableWallpaper] {
        if searchTerm.isEmpty { return wallpapers }
        return wallpapers.filter {
            $0.name.localizedCaseInsensitiveContains(searchTerm) ||
            ($0.authors ?? "").localizedCaseInsensitiveContains(searchTerm)
        }
    }

    private func loadWallpapers() {
        isLoading = true
        Task {
            do {
                let items = try await api.fetchWallpapers(type: .custom)
                await MainActor.run {
                    self.wallpapers = items
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Explore fetch error: \(error.localizedDescription)")
                }
            }
        }
    }
}
