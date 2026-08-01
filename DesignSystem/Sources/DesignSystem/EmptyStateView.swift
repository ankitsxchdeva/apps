import SwiftUI

/// An empty screen is an invitation to act: say what's true, then offer the next step.
public struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: DSSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.dsInkSecondary)
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(Color.dsInk)
            Text(message)
                .font(.dsBody)
                .foregroundStyle(Color.dsInkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DSSpace.l)
    }
}
