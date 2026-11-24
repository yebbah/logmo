# logmo

## logmo iPhone app (SwiftUI, iOS 17+)

Log weight, food (kcal/protein), water and the workbook's 1–5 check-in ratings. The dashboard shows logging streak, compliance (7/30 days, per tracker) and the smoothed weight trend.

### Run it
1. Install Xcode, then `brew install xcodegen`
2. `xcodegen` in this folder creates `logmo.xcodeproj`
3. Open it, set your Team under Signing, pick your iPhone, Run

### Layout
- `logmo/Services/Metrics.swift` — streak, compliance, trend (pure Swift, unit-tested in `logmo-tests`)
- `logmo/Models/DayLog.swift` — one SwiftData row per day, CloudKit-compatible
- `logmo/Services/Integrations.swift` — `HealthSource` and `SyncBackend` protocols for Apple Health and cloud later

### Definitions
- **Logged day**: anything logged that day. **Streak**: consecutive logged days; today not yet logged doesn't break it.
- **Compliance**: logged days ÷ window days. Missing is never treated as zero.
- **Trend**: exponential smoothing, alpha = 2/(N+1), N=16 by default (workbook's male default); missing days carry the trend forward.
