import SwiftUI
import DesignSystem

/// Home = the banner you're about to show. Type a line, tap Show, hold the
/// phone sideways. Everything else on the screen is optional.
struct ContentView: View {
    @Environment(SignStore.self) private var store
    @Environment(\.dsTheme) private var theme

    @State private var draft = Sign(text: Sign.defaultText)
    @State private var showsSign = false
    @State private var didLoadRecent = false
    @FocusState private var fieldFocused: Bool

    private var isEmpty: Bool { draft.trimmedText.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpace.l) {
                DSHeader("Banner")
                field
                preview
                colors
                speeds
                Button("Show banner", action: show)
                    .buttonStyle(PillButtonStyle())
                    .disabled(isEmpty)
                    .opacity(isEmpty ? 0.4 : 1)
                if !store.saved.isEmpty {
                    saved
                }
            }
            .padding(DSSpace.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .dsScreen()
        .fullScreenCover(isPresented: $showsSign) {
            SignView(sign: draft) { showsSign = false }
        }
        .onAppear {
            guard !didLoadRecent else { return }
            didLoadRecent = true
            if let recent = store.mostRecent { draft = recent }
            #if DEBUG
            // Screenshot hook for UI verification without touch automation.
            if ProcessInfo.processInfo.arguments.contains("-banner-screenshot-sign") {
                draft = Sign(text: Sign.defaultText, color: .ember, speed: .slow)
                showsSign = true
            }
            #endif
        }
    }

    // MARK: - Editing

    private var field: some View {
        TextField(Sign.defaultText, text: $draft.text, axis: .vertical)
            .font(.dsHeadline)
            .foregroundStyle(Color.dsInk)
            .lineLimit(1...3)
            .focused($fieldFocused)
            .submitLabel(.done)
            .padding(DSSpace.m)
            .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
    }

    /// The real marquee at desk size — what you see is what the room sees.
    private var preview: some View {
        MarqueeStrip(
            text: isEmpty ? Sign.defaultText : draft.trimmedText,
            ink: isEmpty ? .dsInkSecondary : draft.color.ink,
            speed: draft.speed,
            fontSize: 44
        )
        .frame(height: 84)
        .frame(maxWidth: .infinity)
        .background(.black, in: .rect(cornerRadius: DSRadius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var colors: some View {
        HStack(spacing: DSSpace.m) {
            ForEach(SignColor.allCases) { color in
                Button {
                    draft.color = color
                    Haptics.tap()
                } label: {
                    ZStack {
                        Circle().fill(.black)
                        Circle()
                            .fill(color.ink)
                            .frame(width: 24, height: 24)
                    }
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle().strokeBorder(
                            draft.color == color ? theme.accent : Color.dsSeparator,
                            lineWidth: draft.color == color ? 3 : 1
                        )
                    }
                }
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(draft.color == color ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .environment(\.colorScheme, .dark)
    }

    private var speeds: some View {
        HStack(spacing: DSSpace.s) {
            ForEach(SignSpeed.allCases) { speed in
                Button {
                    draft.speed = speed
                    Haptics.tap()
                } label: {
                    Text(speed.name)
                        .font(.dsHeadline)
                        .foregroundStyle(draft.speed == speed ? .white : Color.dsInk)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            draft.speed == speed ? theme.accent : Color.dsSurface,
                            in: .rect(cornerRadius: DSRadius.control, style: .continuous)
                        )
                }
                .accessibilityAddTraits(draft.speed == speed ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Saved

    private var saved: some View {
        VStack(alignment: .leading, spacing: DSSpace.s) {
            Text("Saved")
                .font(.dsCaption)
                .foregroundStyle(Color.dsInkSecondary)
            ForEach(store.saved) { sign in
                Button {
                    draft = sign
                    show()
                } label: {
                    HStack(spacing: DSSpace.m) {
                        Circle()
                            .fill(sign.color.ink)
                            .frame(width: 12, height: 12)
                            .environment(\.colorScheme, .dark)
                        Text(sign.trimmedText)
                            .font(.dsBody)
                            .foregroundStyle(Color.dsInk)
                            .lineLimit(1)
                        Spacer(minLength: DSSpace.s)
                        Text(sign.speed.name.lowercased())
                            .font(.dsCaption)
                            .foregroundStyle(Color.dsInkSecondary)
                    }
                    .padding(DSSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.delete(sign)
                        Haptics.firm()
                    }
                }
            }
        }
    }

    // MARK: - Showing

    private func show() {
        guard !isEmpty else { return }
        draft.text = draft.trimmedText
        fieldFocused = false
        store.remember(draft)
        Haptics.firm()
        showsSign = true
    }
}

#Preview {
    ContentView()
        .environment(SignStore.shared)
        .dsTheme(.banner)
}
