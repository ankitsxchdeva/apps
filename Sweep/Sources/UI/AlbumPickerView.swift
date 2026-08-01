import SwiftUI
import Photos
import DesignSystem

/// Sheet listing smart albums, then user albums. Multi-select feeds the deck;
/// changes apply immediately.
struct AlbumPickerView: View {
    let model: DeckModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.m) {
            DSHeader("Albums", subtitle: "Pick what feeds the deck.")
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpace.l) {
                    if !model.smartAlbums.isEmpty {
                        section("Smart albums", albums: model.smartAlbums)
                    }
                    if !model.userAlbums.isEmpty {
                        section("My albums", albums: model.userAlbums)
                    }
                    if model.smartAlbums.isEmpty && model.userAlbums.isEmpty {
                        EmptyStateView(
                            systemImage: "rectangle.stack",
                            title: "No albums with photos",
                            message: "Add photos to your library and they'll show up here."
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, DSSpace.xl)
                    }
                }
                .padding(.bottom, DSSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .padding([.top, .horizontal], DSSpace.l)
        .dsScreen()
    }

    private func section(_ title: String, albums: [AlbumInfo]) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s) {
            Text(title)
                .font(.dsCaption)
                .foregroundStyle(Color.dsInkSecondary)
            ForEach(albums) { album in
                AlbumRow(
                    album: album,
                    selected: model.selectedAlbumIDs.contains(album.id),
                    manager: model.imageManager
                ) {
                    Haptics.tap()
                    model.toggleAlbum(album.id)
                }
            }
        }
    }
}

private struct AlbumRow: View {
    let album: AlbumInfo
    let selected: Bool
    let manager: PHImageManager
    let toggle: () -> Void

    @Environment(\.dsTheme) private var theme

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: DSSpace.m) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsInk)
                    Text("\(album.count)")
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsInkSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? theme.accent : Color.dsSeparator)
            }
            .padding(DSSpace.s)
            .background(
                Color.dsSurface,
                in: .rect(cornerRadius: DSRadius.control, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        Group {
            if let keyAsset = album.keyAsset {
                AssetImageView(
                    asset: keyAsset,
                    manager: manager,
                    targetSize: CGSize(width: 168, height: 168)
                )
            } else {
                Color.dsSeparator
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: DSRadius.control - 4, style: .continuous))
    }
}
