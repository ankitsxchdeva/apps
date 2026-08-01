# Design language

The contract for every app in this repo. If a screen doesn't follow this file, it's a bug.

## Principle

Zero cognitive load. Each screen has exactly one job and one obvious action. The app
opens directly into that job — no dashboards, no onboarding carousels, no menus to
learn. Settings exist, but the user never *needs* them.

## Tokens (all in the `DesignSystem` package — never hardcode)

| Token | Use |
|---|---|
| `Color.dsBackground` | every screen backdrop (warm paper / near-black) |
| `Color.dsSurface` | cards, rows, sheets |
| `Color.dsInk` / `dsInkSecondary` | text |
| `Color.dsSeparator` | hairlines, ring tracks |
| `Color.dsKeep` / `dsLetGo` | swipe feedback only (green / ember) |
| `Color.dsStreak` | streak + celebration amber |
| `Font.dsDisplay` | ONE big rounded number/word per screen — the anchor |
| `Font.dsTitle`, `dsHeadline`, `dsBody`, `dsCaption` | everything else |
| `DSSpace` (4/8/16/24/36), `DSRadius` (24 card / 16 control) | spacing & corners |

Per-app accent via `.dsTheme(.sweep)` (ember) or `.dsTheme(.groove)` (moss) at the
app root only. Components read it from the environment.

## Components

`DSHeader`, `PillButtonStyle` (primary / quiet / destructive), `ProgressRing`,
`EmptyStateView`, `.dsCard()`, `.dsScreen()`, `Haptics` (tap / firm / success).
Extend the package rather than one-off-styling inside an app if a component would
plausibly serve both apps.

## Motion & touch

- One spring: `.spring(response: 0.3–0.5, dampingFraction: 0.75–0.85)`. No easing zoo.
- Haptic on every meaningful touch: `Haptics.tap()` passing, `.firm()` commit,
  `.success()` milestone. Never more than one per gesture.
- Respect Reduce Motion: gate decorative animation behind `@Environment(\.accessibilityReduceMotion)`.

## Voice

Sentence case, plain verbs, no exclamation marks, no apologies. Buttons say exactly
what happens: "Delete 34 photos", not "Confirm". Empty states say what's true and
offer the next step. Numbers are heroes — set them in `dsDisplay`.

## Quality floor

Light + dark from day one. Dynamic Type doesn't break layouts. Tap targets ≥ 44pt.
Every screen readable at arm's length.
