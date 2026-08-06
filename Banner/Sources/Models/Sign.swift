import SwiftUI
import DesignSystem

/// One banner: what it says, and how it reads across a room.
struct Sign: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var color: SignColor
    var speed: SignSpeed

    init(id: UUID = UUID(), text: String, color: SignColor = .paper, speed: SignSpeed = .medium) {
        self.id = id
        self.text = text
        self.color = color
        self.speed = speed
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What a fresh install says, and the field's prompt once it's cleared.
    static let defaultText = "I LOVE YOU"
}

/// The sign is always dark — it is a light in a dark room, not a UI surface.
/// Only the ink changes.
enum SignColor: String, Codable, CaseIterable, Identifiable {
    case paper, amber, ember, violet

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: "White"
        case .amber: "Amber"
        case .ember: "Ember"
        case .violet: "Violet"
        }
    }

    var ink: Color {
        switch self {
        case .paper: .white
        case .amber: .dsStreak
        case .ember: .dsLetGo
        case .violet: DSTheme.banner.accent
        }
    }
}

enum SignSpeed: String, Codable, CaseIterable, Identifiable {
    case slow, medium, fast

    var id: String { rawValue }

    var name: String {
        switch self {
        case .slow: "Slow"
        case .medium: "Medium"
        case .fast: "Fast"
        }
    }

    /// Points travelled per second on the sign.
    var pointsPerSecond: Double {
        switch self {
        case .slow: 140
        case .medium: 260
        case .fast: 440
        }
    }
}
