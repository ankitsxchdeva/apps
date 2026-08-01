# apps

Suite of minimal iOS apps sharing one design language.

- `DesignSystem/` — shared SwiftUI package (tokens + components). Read `DESIGN.md`
  before touching any UI; it is the contract.
- `Sweep/` — swipe-to-clean camera roll app.
- `Groove/` — greasing-the-groove exercise checklist app (+ widgets).

Projects are generated: edit `project.yml`, never the `.xcodeproj` (gitignored).

Verify: `Scripts/verify.sh` (xcodegen + simulator build of every app).
