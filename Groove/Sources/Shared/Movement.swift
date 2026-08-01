import Foundation

/// One movement on the daily checklist: a name, a symbol, and a small daily set target.
struct Movement: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    var setsPerDay: Int

    init(id: UUID = UUID(), name: String, symbol: String, setsPerDay: Int) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.setsPerDay = max(1, min(setsPerDay, 10))
    }
}

extension Movement {
    /// Seeded on first launch so the app is usable in five seconds.
    static let starters: [Movement] = [
        Movement(name: "Push-ups", symbol: "figure.strengthtraining.functional", setsPerDay: 3),
        Movement(name: "Squats", symbol: "figure.strengthtraining.traditional", setsPerDay: 3),
        Movement(name: "Stand up and stretch", symbol: "figure.cooldown", setsPerDay: 5),
    ]

    /// One-tap adds in the add-movement sheet.
    static let suggestions: [Movement] = [
        Movement(name: "Pull-ups", symbol: "figure.climbing", setsPerDay: 3),
        Movement(name: "Plank (30s counts as a set)", symbol: "figure.core.training", setsPerDay: 3),
        Movement(name: "Dead hang", symbol: "figure.gymnastics", setsPerDay: 2),
        Movement(name: "Calf raises", symbol: "figure.stand", setsPerDay: 3),
        Movement(name: "Desk push-ups", symbol: "figure.wrestling", setsPerDay: 4),
        Movement(name: "Lunges", symbol: "figure.cross.training", setsPerDay: 3),
        Movement(name: "Wall sit", symbol: "figure.mind.and.body", setsPerDay: 2),
        Movement(name: "Neck rolls", symbol: "figure.flexibility", setsPerDay: 3),
    ]

    /// Curated picker grid. Every name verified to exist in SF Symbols 5 (iOS 17).
    static let symbolChoices: [String] = [
        "figure.strengthtraining.traditional",
        "figure.strengthtraining.functional",
        "figure.core.training",
        "figure.cross.training",
        "figure.flexibility",
        "figure.cooldown",
        "figure.walk",
        "figure.run",
        "figure.yoga",
        "figure.climbing",
        "figure.jumprope",
        "dumbbell.fill",
    ]
}
