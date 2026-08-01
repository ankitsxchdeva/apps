import SwiftUI

/// Oversized rounded screen title, shared across both apps.
public struct DSHeader: View {
    let title: String
    let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.xs) {
            Text(title)
                .font(.dsTitle)
                .foregroundStyle(Color.dsInk)
            if let subtitle {
                Text(subtitle)
                    .font(.dsBody)
                    .foregroundStyle(Color.dsInkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
