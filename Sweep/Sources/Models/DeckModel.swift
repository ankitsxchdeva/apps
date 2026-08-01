import Foundation
import Observation
import Photos
import DesignSystem

/// One pickable album: a smart album or user album with at least one asset.
struct AlbumInfo: Identifiable {
    let collection: PHAssetCollection
    let title: String
    let count: Int
    let keyAsset: PHAsset?

    var id: String { collection.localIdentifier }
}

/// The whole app state: photo access, album selection, the deck, the delete
/// queue, and everything persisted between sessions.
@MainActor
@Observable
final class DeckModel {
    enum Access { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var isLoading = true
    private(set) var smartAlbums: [AlbumInfo] = []
    private(set) var userAlbums: [AlbumInfo] = []
    private(set) var selectedAlbumIDs: Set<String>
    /// Remaining assets, newest first. The top card is `deck.first`.
    private(set) var deck: [PHAsset] = []
    /// How many assets the current selection had when it was loaded.
    private(set) var totalCount = 0
    /// Left-swiped assets waiting for one batched delete.
    private(set) var queued: [PHAsset] = []
    private(set) var keptIDs: Set<String>
    private(set) var lifetimeFreedBytes: Int
    /// Bytes just freed; non-nil briefly after a successful delete.
    private(set) var freedMoment: Int?

    var reviewBeforeDelete: Bool {
        didSet { defaults.set(reviewBeforeDelete, forKey: Keys.reviewBeforeDelete) }
    }

    var imageManager: PHImageManager { cachingManager ?? PHImageManager.default() }
    private(set) var cardTargetSize = CGSize(width: 1200, height: 1600)

    private var history: [Decision] = []
    private var sizeEstimates: [String: Int] = [:]
    private var cachingManager: PHCachingImageManager?
    private var cachedWindow: [String: PHAsset] = [:]
    private let defaults = UserDefaults.standard

    private struct Decision {
        let asset: PHAsset
        let kept: Bool
    }

    private enum Keys {
        static let selectedAlbums = "sweep.selectedAlbums"
        static let keptAssets = "sweep.keptAssets"
        static let freedBytes = "sweep.freedBytes"
        static let reviewBeforeDelete = "sweep.reviewBeforeDelete"
    }

    init() {
        selectedAlbumIDs = Set(defaults.stringArray(forKey: Keys.selectedAlbums) ?? [])
        keptIDs = Set(defaults.stringArray(forKey: Keys.keptAssets) ?? [])
        lifetimeFreedBytes = defaults.integer(forKey: Keys.freedBytes)
        reviewBeforeDelete = defaults.object(forKey: Keys.reviewBeforeDelete) as? Bool ?? true
    }

    // MARK: - Access

    func start() async {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            await grant()
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if status == .authorized || status == .limited {
                await grant()
            } else {
                access = .denied
            }
        default:
            access = .denied
        }
    }

    private func grant() async {
        access = .granted
        cachingManager = PHCachingImageManager()
        await refreshAlbums()
        await reloadDeck()
        isLoading = false
    }

    // MARK: - Albums

    func refreshAlbums() async {
        let fetched = await Task.detached(priority: .userInitiated) {
            Self.fetchAlbums()
        }.value
        smartAlbums = fetched.smart
        userAlbums = fetched.user
        let valid = Set((smartAlbums + userAlbums).map(\.id))
        selectedAlbumIDs = selectedAlbumIDs.intersection(valid)
        if selectedAlbumIDs.isEmpty,
           let recents = smartAlbums.first(where: {
               $0.collection.assetCollectionSubtype == .smartAlbumUserLibrary
           }) {
            selectedAlbumIDs = [recents.id]
        }
        persistSelection()
    }

    func toggleAlbum(_ id: String) {
        if selectedAlbumIDs.contains(id) {
            selectedAlbumIDs.remove(id)
        } else {
            selectedAlbumIDs.insert(id)
        }
        persistSelection()
        Task { await reloadDeck() }
    }

    /// Chip title on the main screen.
    var selectionLabel: String {
        if selectedAlbumIDs.isEmpty { return "Choose albums" }
        if selectedAlbumIDs.count == 1,
           let id = selectedAlbumIDs.first,
           let album = (smartAlbums + userAlbums).first(where: { $0.id == id }) {
            return album.title
        }
        return "\(selectedAlbumIDs.count) albums"
    }

    // MARK: - Deck

    func reloadDeck() async {
        guard access == .granted else { return }
        let ids = Array(selectedAlbumIDs)
        let excluded = keptIDs.union(queued.map(\.localIdentifier))
        let assets = await Task.detached(priority: .userInitiated) {
            Self.fetchDeck(albumIDs: ids, excluding: excluded)
        }.value
        deck = assets
        totalCount = assets.count
        history.removeAll()
        prefetch()
    }

    /// Commits the top card. Keep persists the id; let go queues the asset.
    func commit(keep: Bool) {
        guard let asset = deck.first else { return }
        deck.removeFirst()
        history.append(Decision(asset: asset, kept: keep))
        if keep {
            keptIDs.insert(asset.localIdentifier)
            persistKept()
        } else {
            queued.append(asset)
            estimateSize(of: asset)
        }
        prefetch()
    }

    var canUndo: Bool { !history.isEmpty }

    func undo() {
        guard let last = history.popLast() else { return }
        let id = last.asset.localIdentifier
        if last.kept {
            keptIDs.remove(id)
            persistKept()
        } else {
            queued.removeAll { $0.localIdentifier == id }
        }
        deck.insert(last.asset, at: 0)
        totalCount = max(totalCount, deck.count)
        prefetch()
    }

    /// Puts a queued asset back on top of the deck.
    func restore(_ asset: PHAsset) {
        let id = asset.localIdentifier
        queued.removeAll { $0.localIdentifier == id }
        history.removeAll { $0.asset.localIdentifier == id }
        deck.insert(asset, at: 0)
        totalCount = max(totalCount, deck.count)
        prefetch()
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(totalCount - deck.count) / Double(totalCount)
    }

    var progressLabel: String {
        guard totalCount > 0 else { return "" }
        let position = min(totalCount - deck.count + 1, totalCount)
        return "\(position) of \(totalCount)"
    }

    // MARK: - Delete queue

    var queuedBytesEstimate: Int {
        queued.reduce(0) {
            $0 + (sizeEstimates[$1.localIdentifier] ?? Self.fallbackEstimate(for: $1))
        }
    }

    var queueLabel: String {
        "\(queued.count) queued · ~\(formatBytes(queuedBytesEstimate))"
    }

    var deleteButtonLabel: String {
        let videos = queued.filter { $0.mediaType == .video }.count
        let photos = queued.count - videos
        let photoPart = "\(photos) photo\(photos == 1 ? "" : "s")"
        let videoPart = "\(videos) video\(videos == 1 ? "" : "s")"
        if videos == 0 { return "Delete \(photoPart)" }
        if photos == 0 { return "Delete \(videoPart)" }
        return "Delete \(photoPart) and \(videoPart)"
    }

    /// One batched delete; iOS shows its own confirmation dialog.
    @discardableResult
    func deleteQueued() async -> Bool {
        guard !queued.isEmpty else { return false }
        let assets = queued
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
        } catch {
            // The user canceled the system dialog; keep the queue.
            return false
        }
        let freed = assets.reduce(0) {
            $0 + (sizeEstimates[$1.localIdentifier] ?? Self.fallbackEstimate(for: $1))
        }
        lifetimeFreedBytes += freed
        defaults.set(lifetimeFreedBytes, forKey: Keys.freedBytes)
        queued.removeAll()
        history.removeAll { !$0.kept }
        freedMoment = freed
        Haptics.success()
        return true
    }

    func clearFreedMoment() {
        freedMoment = nil
    }

    func resetKeptPhotos() {
        keptIDs = []
        persistKept()
        Task { await reloadDeck() }
    }

    // MARK: - Formatting

    func formatBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 MB" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Image caching

    func setCardSize(_ size: CGSize, scale: CGFloat) {
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        guard target != cardTargetSize, target.width > 0 else { return }
        cardTargetSize = target
        cachingManager?.stopCachingImagesForAllAssets()
        cachedWindow = [:]
        prefetch()
    }

    /// Keeps the next few cards warm so swiping never shows a blank card.
    private func prefetch() {
        guard let cachingManager else { return }
        let window = Array(deck.prefix(5))
        let windowIDs = Set(window.map(\.localIdentifier))
        let removed = cachedWindow.values.filter { !windowIDs.contains($0.localIdentifier) }
        let added = window.filter { cachedWindow[$0.localIdentifier] == nil }
        if !removed.isEmpty {
            cachingManager.stopCachingImages(
                for: removed, targetSize: cardTargetSize,
                contentMode: .aspectFill, options: Self.requestOptions()
            )
        }
        if !added.isEmpty {
            cachingManager.startCachingImages(
                for: added, targetSize: cardTargetSize,
                contentMode: .aspectFill, options: Self.requestOptions()
            )
        }
        cachedWindow = Dictionary(uniqueKeysWithValues: window.map { ($0.localIdentifier, $0) })
    }

    nonisolated static func requestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    // MARK: - Size estimation

    private func estimateSize(of asset: PHAsset) {
        let id = asset.localIdentifier
        guard sizeEstimates[id] == nil else { return }
        Task.detached(priority: .utility) { [weak self] in
            let resources = PHAssetResource.assetResources(for: asset)
            guard let bytes = resources.compactMap({ $0.value(forKey: "fileSize") as? Int }).max()
            else { return }
            await MainActor.run { [weak self] in
                self?.sizeEstimates[id] = bytes
            }
        }
    }

    private nonisolated static func fallbackEstimate(for asset: PHAsset) -> Int {
        asset.mediaType == .video
            ? 1_000_000 + Int(asset.duration * 1_500_000)
            : 2_000_000
    }

    // MARK: - Persistence

    private func persistSelection() {
        defaults.set(Array(selectedAlbumIDs), forKey: Keys.selectedAlbums)
    }

    private func persistKept() {
        defaults.set(Array(keptIDs), forKey: Keys.keptAssets)
    }

    // MARK: - Library fetches (off the main thread)

    private nonisolated static func fetchAlbums() -> (smart: [AlbumInfo], user: [AlbumInfo]) {
        let smartSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumUserLibrary,
            .smartAlbumFavorites,
            .smartAlbumScreenshots,
            .smartAlbumSelfPortraits,
            .smartAlbumVideos,
        ]
        var smart: [AlbumInfo] = []
        for subtype in smartSubtypes {
            PHAssetCollection
                .fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                .enumerateObjects { collection, _, _ in
                    if let info = info(for: collection) { smart.append(info) }
                }
        }
        var user: [AlbumInfo] = []
        PHAssetCollection
            .fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { collection, _, _ in
                if let info = info(for: collection) { user.append(info) }
            }
        return (smart, user)
    }

    private nonisolated static func info(for collection: PHAssetCollection) -> AlbumInfo? {
        let newestFirst = PHFetchOptions()
        newestFirst.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: collection, options: newestFirst)
        guard assets.count > 0 else { return nil }
        return AlbumInfo(
            collection: collection,
            title: collection.localizedTitle ?? "Album",
            count: assets.count,
            keyAsset: assets.firstObject
        )
    }

    private nonisolated static func fetchDeck(
        albumIDs: [String],
        excluding: Set<String>
    ) -> [PHAsset] {
        guard !albumIDs.isEmpty else { return [] }
        let newestFirst = PHFetchOptions()
        newestFirst.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var seen = Set<String>()
        var assets: [PHAsset] = []
        PHAssetCollection
            .fetchAssetCollections(withLocalIdentifiers: albumIDs, options: nil)
            .enumerateObjects { collection, _, _ in
                PHAsset.fetchAssets(in: collection, options: newestFirst)
                    .enumerateObjects { asset, _, _ in
                        let id = asset.localIdentifier
                        guard !excluding.contains(id), seen.insert(id).inserted else { return }
                        assets.append(asset)
                    }
            }
        assets.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        return assets
    }

    // MARK: - Screenshot scaffolding (DEBUG only)

    #if DEBUG
    /// Queues the first few deck assets so screenshot runs can reach the
    /// queue sheet and the system delete dialog without touch automation.
    func debugQueueFirstAssets(_ count: Int = 2) async {
        while isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for _ in 0..<min(count, deck.count) {
            commit(keep: false)
        }
    }
    #endif
}
