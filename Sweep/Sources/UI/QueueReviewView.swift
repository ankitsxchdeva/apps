import SwiftUI
import Photos
import DesignSystem

/// Sheet reviewing everything queued for deletion. Tapping a thumbnail puts
/// it back in the deck; the pill commits one batched delete.
struct QueueReviewView: View {
    let model: DeckModel

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: DSSpace.xs)]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.m) {
            DSHeader("Queued to delete", subtitle: "Tap a photo to put it back in the deck.")
            ScrollView {
                LazyVGrid(columns: columns, spacing: DSSpace.xs) {
                    ForEach(model.queued, id: \.localIdentifier) { asset in
                        QueuedThumbnail(asset: asset, manager: model.imageManager) {
                            Haptics.tap()
                            model.restore(asset)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            VStack(spacing: DSSpace.s) {
                Button(model.deleteButtonLabel) {
                    Haptics.firm()
                    Task {
                        if await model.deleteQueued() {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(PillButtonStyle(.destructive))
                Text("Frees about \(model.formatBytes(model.queuedBytesEstimate)). iOS asks you to confirm.")
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsInkSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpace.l)
        .dsScreen()
        .onChange(of: model.queued.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }
}

private struct QueuedThumbnail: View {
    let asset: PHAsset
    let manager: PHImageManager
    let restore: () -> Void

    var body: some View {
        Button(action: restore) {
            AssetImageView(
                asset: asset,
                manager: manager,
                targetSize: CGSize(width: 300, height: 300)
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: DSRadius.control, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .padding(DSSpace.xs + 2)
            }
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    VideoDurationBadge(duration: asset.duration)
                        .padding(DSSpace.xs + 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
