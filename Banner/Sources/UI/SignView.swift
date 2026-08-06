import SwiftUI
import DesignSystem

/// The sign: the whole phone, sideways, black, one line of moving text.
/// Controls fade out after a few seconds so nothing competes with the words.
struct SignView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sign: Sign
    let onClose: () -> Void

    @State private var showsControls = true
    @State private var showsHint = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black
                MarqueeStrip(
                    text: sign.trimmedText,
                    ink: sign.color.ink,
                    speed: sign.speed,
                    fontSize: geo.size.height * 0.55
                )
                .frame(height: geo.size.height)
                controls
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        // The sign is always a light in a dark room, whatever the phone is set to.
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { revealControls() }
        .onAppear {
            Orientation.set(.landscape)
            UIApplication.shared.isIdleTimerDisabled = true
            revealControls()
        }
        .onDisappear {
            hideTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            Orientation.set(.portrait)
        }
    }

    private var controls: some View {
        HStack(spacing: DSSpace.m) {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Close banner")

            if showsHint {
                Text("Tap the screen to bring this back")
                    .font(.dsCaption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(DSSpace.l)
        .opacity(showsControls ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: showsControls)
        .allowsHitTesting(showsControls)
    }

    private func revealControls() {
        showsControls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showsControls = false
            // The hint has done its job once; after that it's just noise on the sign.
            showsHint = false
        }
    }

    private func close() {
        Haptics.firm()
        hideTask?.cancel()
        // Turn back before the cover animates away, so the editor never flashes sideways.
        Orientation.set(.portrait)
        onClose()
    }
}

#Preview {
    SignView(sign: Sign(text: "DJ Nova · main room · 11pm", color: .amber, speed: .medium)) {}
}
