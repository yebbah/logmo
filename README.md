# logmo

## logmo iPhone app (SwiftUI, iOS 17+)

<img src="logmo/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="logmo app icon">

Log weight, food (calories, protein, carbs, fat), water, steps and the workbook's 1–5 check-in ratings against weekly goals. The dashboard shows goal status, three streaks, compliance and the weight trend with optional biofeedback lines. Two themes (Clean, Midnight) in Settings. Fitness campaigns (cut, bulk, maintenance) with history. Weekly goals (calories, steps, workout days) are stored per campaign. A Dashboard tab that filters by campaign and holds the goals, a Streaks tab for streaks and compliance, a Campaigns tab to run campaigns and look back at each one, a weekly plan per campaign, an optional weekly reminder, and full-screen landscape charts.

### Run it
1. Install Xcode, then `brew install xcodegen`
2. `DEVELOPMENT_TEAM=<your Apple team id> xcodegen` in this folder creates `logmo.xcodeproj` (find the id in Xcode → Settings → Accounts; leave it out for simulator-only builds)
3. Open it, set your Team under Signing, pick your iPhone, Run

### Layout
- `logmo/Services/Metrics.swift` — streak, compliance, trend (pure Swift, unit-tested in `logmo-tests`)
- `logmo/Models/DayLog.swift` — one SwiftData row per day, CloudKit-compatible
- `logmo/Services/Integrations.swift` — `HealthSource` and `SyncBackend` protocols for Apple Health and cloud later

### Definitions
- **Logged day**: anything logged that day. **Streak**: consecutive logged days; today not yet logged doesn't break it.
- **Compliance**: logged days ÷ window days. Missing is never treated as zero.
- **Trend**: exponential smoothing, alpha = 2/(N+1), N=16 by default (workbook's male default); missing days carry the trend forward.
