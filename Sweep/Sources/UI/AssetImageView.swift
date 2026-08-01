import SwiftUI
import Photos
import DesignSystem

/// Fills its frame with a PHAsset image, loading through the shared manager
/// so deck prefetching pays off. Shows a quiet placeholder while loading.
struct AssetImageView: View {
    let asset: PHAsset
    let manager: PHImageManager
    let targetSize: CGSize

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Color.dsSeparator
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
            .onChange(of: asset.localIdentifier) {
                image = nil
                load()
            }
    }

    private func load() {
        requestID = manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: DeckModel.requestOptions()
        ) { result, info in
            guard let result else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if image == nil || !degraded {
                image = result
            }
        }
    }

    private func cancel() {
        if let requestID {
            manager.cancelImageRequest(requestID)
        }
        requestID = nil
    }
}

/// Small capsule showing a video's length, laid over thumbnails and cards.
struct VideoDurationBadge: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: DSSpace.xs) {
            Image(systemName: "video.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(Self.label(for: duration))
                .font(.dsCaption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DSSpace.s + 2)
        .padding(.vertical, DSSpace.xs + 1)
        .background(.black.opacity(0.55), in: Capsule())
    }

    static func label(for duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
