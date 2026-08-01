import SwiftUI
import Photos
import DesignSystem

/// The card stack: drag the top card left to let go, right to keep.
/// The next card peeks from behind and rises as the top one leaves.
struct SwipeDeckView: View {
    let model: DeckModel

    @State private var drag: CGSize = .zero
    @State private var isFlinging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private static let maxRotation: Double = 12

    var body: some View {
        GeometryReader { geo in
            // The top card leaves a strip at the bottom for the next card to peek into.
            let cardSize = CGSize(width: geo.size.width, height: geo.size.height - DSSpace.s)
            ZStack(alignment: .top) {
                if model.deck.count > 1 {
                    let progress = pullProgress(in: cardSize)
                    card(model.deck[1], size: cardSize)
                        .scaleEffect(0.94 + 0.06 * progress, anchor: .bottom)
                        .offset(y: DSSpace.s * (1 - progress))
                }
                if let top = model.deck.first {
                    card(top, size: cardSize)
                        .overlay { washOverlay(size: cardSize) }
                        .offset(drag)
                        .rotationEffect(.degrees(rotation(in: cardSize)))
                        .gesture(dragGesture(size: cardSize))
                        .id(top.localIdentifier)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .onAppear { model.setCardSize(cardSize, scale: displayScale) }
            .onChange(of: cardSize) { _, newSize in
                model.setCardSize(newSize, scale: displayScale)
            }
        }
    }

    // MARK: - Pieces

    private func card(_ asset: PHAsset, size: CGSize) -> some View {
        AssetImageView(asset: asset, manager: model.imageManager, targetSize: model.cardTargetSize)
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: DSRadius.card, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    VideoDurationBadge(duration: asset.duration)
                        .padding(DSSpace.m)
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    @ViewBuilder
    private func washOverlay(size: CGSize) -> some View {
        if drag.width != 0 {
            let keep = drag.width > 0
            let progress = pullProgress(in: size)
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .fill((keep ? Color.dsKeep : Color.dsLetGo).opacity(0.45 * progress))
                .overlay {
                    VStack(spacing: DSSpace.s) {
                        Image(systemName: keep ? "checkmark" : "trash")
                            .font(.system(size: 40, weight: .bold))
                        Text(keep ? "Keep" : "Let go")
                            .font(.dsDisplay)
                    }
                    .foregroundStyle(.white)
                    .opacity(progress)
                }
                .allowsHitTesting(false)
        }
    }

    // MARK: - Gesture

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isFlinging else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isFlinging else { return }
                if abs(value.translation.width) > threshold(in: size) {
                    fling(keep: value.translation.width > 0, size: size)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        drag = .zero
                    }
                }
            }
    }

    private func fling(keep: Bool, size: CGSize) {
        if model.deck.count == 1 {
            Haptics.success()
        } else {
            Haptics.tap()
        }
        guard !reduceMotion else {
            model.commit(keep: keep)
            drag = .zero
            return
        }
        isFlinging = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            drag = CGSize(width: (keep ? 1.4 : -1.4) * size.width, height: drag.height * 1.3)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(230))
            model.commit(keep: keep)
            drag = .zero
            isFlinging = false
        }
    }

    // MARK: - Geometry

    private func threshold(in size: CGSize) -> CGFloat {
        size.width / 3
    }

    private func pullProgress(in size: CGSize) -> Double {
        min(abs(drag.width) / threshold(in: size), 1)
    }

    private func rotation(in size: CGSize) -> Double {
        guard size.width > 0 else { return 0 }
        let raw = Double(drag.width / size.width) * Self.maxRotation
        return min(max(raw, -Self.maxRotation), Self.maxRotation)
    }
}
