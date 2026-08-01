import SwiftUI
import DesignSystem

/// One-screen settings sheet: the lifetime win, one toggle, one reset.
struct SettingsView: View {
    @Bindable var model: DeckModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.l) {
            DSHeader("Settings")

            VStack(spacing: DSSpace.xs) {
                Text("~" + model.formatBytes(model.lifetimeFreedBytes))
                    .font(.dsDisplay)
                    .foregroundStyle(Color.dsInk)
                Text("freed with Sweep")
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsInkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpace.m)
            .padding(.horizontal, DSSpace.l)
            .dsCard()

            VStack(alignment: .leading, spacing: DSSpace.xs) {
                Toggle("Review before deleting", isOn: $model.reviewBeforeDelete)
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsInk)
                    .onChange(of: model.reviewBeforeDelete) {
                        Haptics.tap()
                    }
                Text("Check the queue one last time before anything is deleted.")
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpace.m)
            .background(
                Color.dsSurface,
                in: .rect(cornerRadius: DSRadius.control, style: .continuous)
            )

            VStack(spacing: DSSpace.s) {
                Button("Reset kept photos") {
                    Haptics.firm()
                    model.resetKeptPhotos()
                }
                .buttonStyle(PillButtonStyle(.quiet))
                .disabled(model.keptIDs.isEmpty)
                .opacity(model.keptIDs.isEmpty ? 0.5 : 1)
                Text(resetCaption)
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsInkSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DSSpace.l)
        .dsScreen()
    }

    private var resetCaption: String {
        let count = model.keptIDs.count
        guard count > 0 else { return "Nothing kept yet." }
        return "\(count) kept photo\(count == 1 ? "" : "s") will come back into the deck."
    }
}
