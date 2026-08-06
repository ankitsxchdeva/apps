import SwiftUI
import UIKit

public extension Font {
    /// The one big number or word that anchors a screen. Use once per screen.
    static let dsDisplay = Font.system(size: 54, weight: .bold, design: .rounded)
    /// Screen titles.
    static let dsTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    /// Row and button emphasis.
    static let dsHeadline = Font.system(.headline, design: .rounded)
    /// Reading text.
    static let dsBody = Font.system(.body)
    /// Metadata, counts, hints.
    static let dsCaption = Font.system(.footnote, design: .rounded).weight(.medium)

    /// A sign face: text meant to be read across a room, sized to the space it
    /// fills rather than to a scale step. Not part of the type scale.
    static func dsSign(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Rendered width of `text` set in `dsSign(size)`. Lives next to the token so
    /// the two can't drift; a marquee needs the width before it can lay itself out.
    static func dsSignWidth(of text: String, size: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
