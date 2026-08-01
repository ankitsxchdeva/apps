import SwiftUI

public enum DSSpace {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 36
}

public enum DSRadius {
    public static let card: CGFloat = 24
    public static let control: CGFloat = 16
}

public extension View {
    /// Standard surface card: continuous corners, whisper of depth.
    func dsCard() -> some View {
        self
            .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.card, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    /// Standard screen backdrop.
    func dsScreen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground.ignoresSafeArea())
    }
}
