# apps

Suite of minimal iOS apps sharing one design language.

- `DesignSystem/` — shared SwiftUI package (tokens + components). Read `DESIGN.md`
  before touching any UI; it is the contract.
- `Sweep/` — swipe-to-clean camera roll app.
- `Groove/` — greasing-the-groove exercise checklist app (+ widgets).
- `Banner/` — landscape scrolling-text sign (hold the phone sideways).
- `SBS/` — side-by-side pour testing with two Bookoo Bluetooth scales. Simulator
  has no Bluetooth: launch with `-sbs-mock` for two fake scales.

Projects are generated: edit `project.yml`, never the `.xcodeproj` (gitignored).

Verify: `Scripts/verify.sh` (xcodegen + simulator build of every app).
