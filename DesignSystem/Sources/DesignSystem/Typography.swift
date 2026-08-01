import SwiftUI

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
}
