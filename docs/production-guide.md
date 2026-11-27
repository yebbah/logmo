# logmo: Production guide

For the owner and anyone who maintains logmo. It covers how the app is built, how it runs on a phone, how to release and recover it, and what is known to be limited. Product behaviour is specified in the PRD (`_bmad-output/planning-artifacts/prds/prd-logmo-s3-2026-11-11/prd.md`); this guide does not repeat it.

Version of this guide: matches PRD v21.2 and app version 1.0.0 (build 6).

---

## 1. What is in production

| | |
|---|---|
| Product | logmo, a personal iPhone app to log weight, food, water, steps and daily check-ins against weekly goals, with fitness campaigns |
| Platform | iPhone only, iOS 17 or later (the AI suggestion needs iOS 26 and Apple Intelligence) |
| Stack | SwiftUI, SwiftData, Swift Charts, UserNotifications, Foundation Models (optional) |
| Bundle ID | `com.yebbah.logmo` |
| Distribution today | Installed straight onto the owner's iPhone from Xcode. Not on the App Store or TestFlight |
| Backend | None. No server, no account, no analytics, no network calls |
| Data location | On the phone only (the app's SwiftData store) |
| Repository | `github.com/yebbah/logmo`, branch `main` is the released state |

## 2. Architecture

```
SwiftUI views  ──►  Services (pure rules + stores)  ──►  SwiftData models
 (Views/)            (Services/)                          (Models/)
```

**Rule of thumb:** every rule that decides a number or a state lives in a pure Swift type with no SwiftData or UI in it, so it can be unit-tested. SwiftData is touched only in small `*Store` types and in views.

| Layer | Files | Role |
|---|---|---|
| Models | `DayLog`, `WeekGoal`, `Campaign` | The three stored tables. CloudKit-compatible: every field optional or defaulted, no unique constraints |
| Pure rules | `Metrics`, `GoalBook`, `Campaigns` (`CampaignRules`), `WeeklyPlan` (`PlanRules`), `Insights`, `WeekSuggestion` (`SuggestionRules`), `Prompts` (`SetupRules`), `DailyReminder` (`DailyReminderRules`) | Streaks, compliance, trend, goals per campaign, campaign dates, weekly plan, reports, suggestion rules, setup and reminder rules |
| Stores (SwiftData) | `CampaignStore`, `PlanStore`, `DataReset`, `Backup`, `ExportBuilder` | Writes: start, end, extend, reschedule campaigns; save goals; wipe; back up and restore; build exports |
| Services | `Reminders`, `DailyReminder`, `AIAdvisor`, `AppleHealth` (`HealthSync`, `HealthSettings`), `HealthMerge`, `AppInfo`, `Integrations` | Notifications, Apple Intelligence, Apple Health import and its pure merge rules, version and contact, future sync protocol |
| Views | `DashboardView`, `StreaksView`, `LogView`, `CampaignsView`, `SettingsView`, `WeeklyPlanView`, `GoalsEditor`, `GoalsCard`, `SuggestSheet`, `LandingView`, … | Screens |
| App | `LogmoApp` | Container setup, tab bar, landing screen, shared tab navigation |

### Data model

- **DayLog**: one row per calendar day. Weight (always kg), calories and macros, water, steps, seven 1–5 ratings, `performanceNA`, `onPeriod`, `isSick`. A value never entered is `nil`, never 0.
- **WeekGoal**: one row per campaign per Monday. Calories (stored as a weekly total), at-or-under flag, protein, steps and whether it is a weekly average, water, workout days, carbs and fat (guidance only), `confirmed` (false = carried over).
- **Campaign**: number, kind, default or real, target weight, start, planned weeks, end, ended early, label, start weight, `measureEveryDays` (0 off, 7, 14 or 28: measurement cadence) and `photoPrompt` (ask about progress photos on those days). `DayLog.photosTaken` records a yes.
- **Body measurements** are not a table: they are a small text on the day's `DayLog.measurementsRaw` (`navel:83.5,chest:97`, cm), parsed by `BodyMeasures`. `MeasureRules` (Measurements.swift) holds the due dates, the change per site and the campaign filter. The CSV gains `measure_<site>_cm` columns and the backup carries `measurementsRaw` and `measureEveryDays` (both optional, so older backups restore).

Invariants the code keeps: every campaign has a start and an end (no open-ended or automatic campaigns; `CampaignStore.tidy` closes any open automatic one from an older version and creates nothing); a campaign covers its start to `CampaignRules.lastDay` and nothing after, so days outside every campaign belong to none; a campaign has its own goals; only one campaign can be planned but not started; past campaigns and past weeks are locked.

### Settings storage

User preferences live in `UserDefaults` (via `@AppStorage`), keys in `SettingsKey`: units, trend smoothing, required trackers, theme, cycle and sick tracking, biofeedback overlay, campaign filter, weekly and daily reminder switches and times, and a few dismissal markers. They are included in the full backup.

### Starting weight and the trend

`Metrics.smoothed`/`weightTrend` take `seeds`: a date to a weight, one per real campaign that has `startWeightKg` (`CampaignRules.trendSeeds`). A seed is the trend on the day before, so the day's weigh-in moves it (day one blank means the trend is the seed, as in the workbook). `CampaignStore.start` refuses a real campaign without a plausible starting weight (20 to 400 kg); `setStartWeight` and `reschedule` change it for campaigns that haven't ended. Every caller of the trend passes the seeds (`Dashboard`, `Campaigns`, `Streaks`, `Maintenance`, `SuggestionRules.summary`). `Maintenance` counts its four weeks from the first log across campaigns and reads weekly change across a campaign boundary unless the new seed jumped more than 0.3 kg.

### Keyboard

`View.keyboardDismissible()` (in `Components.swift`) adds `scrollDismissesKeyboard(.interactively)` and a keyboard-toolbar Done button. Use it on any form that has a text or number field; number pads have no Return key and would otherwise be impossible to close.

### Estimated maintenance

`Maintenance` (pure, tested) replicates the workbook's TDEE: `series` walks the days from the first log, smoothing intake (a 14-day average of logged days, then an EMA with the weight's coefficient) and applying `1100 × weekly change in trend weight`; it starts after 28 days of logging counted from the first log across all campaigns and updates only when weigh-ins are present on at least 5 of the last 10 days and calories on at least 7 (otherwise the estimate is carried: `waiting`/"Holding"). `estimate` returns the trend estimate, or a Mifflin-St Jeor formula estimate from `MaintenanceProfile` (UserDefaults, optional) when there isn't one, with `DataConfidence`. `WeekSummary` carries it; `SuggestionRules.assess` shows it as evidence, sizes a calorie move by the gap to the target pace (`min(weekly cap, max(50, rounded gap))`), keeps the target if the estimate and the scale disagree, and uses it in the low-target rule. `MaintenanceCard` draws it on the Dashboard. The thresholds are constants in `Maintenance.swift`; changing one means updating `MaintenanceTests` and probably `WeekSuggestionTests`.

### Apple Health

`AppleHealth` reads from HealthKit (statistics queries for daily sums, a sample query for the day's last weigh-in, a workout query for strength training) and returns plain `HealthDay` values. `HealthSync.apply` merges them into `DayLog` using `HealthMerge`, which is pure and tested:
- a normal refresh fills a field only if empty or already a Health value, so typed values are not overwritten; the Log screen's **Sync** button passes `overwriteDay`, which makes Health's values replace typed ones for that day only (`HealthMerge.merge(... overwriting: true)`), after flushing any half-typed edit;
- `DayLog.importedFields` and `overriddenFields` record where each value came from, and saving a Log edit (`DayDraft.apply`) moves a changed or cleared Health value to overridden;
- zero or missing readings are never imported; future days are ignored; no record is created for a day with nothing.

Besides the fields that merge (weight, calories and macros, water, steps, and the cycle's period flag), Health also fills read-only context on `DayLog`: `healthSleepMinutes`, `healthRestingHR`, `healthHRV`, `healthBodyFat`, `healthLeanKg`, `healthWorkoutMinutes`. Sleep is the union of asleep intervals per wake-up day, with time awake during the night and deep plus REM when stages exist. `SleepScore` (pure, tested) turns that into the 1 to 5 sleep rating: duration tiers, then a stage quality (unbroken, deep share, REM share, weighted 40/30/30) that adds one (nights of 6 h or more), nothing, or takes one or two off, with efficiency under 80% always costing at least one; scored only after 11:00 on the night's own day. Deep and REM minutes are stored separately (`healthSleepDeepMinutes`, `healthSleepREMMinutes`). The score is a `HealthField.sleep` value, so it follows the same typed-wins and Sync rules as the other fields. Thresholds are constants in `SleepScore.swift`; changing one means updating `SleepScoreTests`. The cycle topic starts off and is dropped from a sync unless cycle tracking is on. Resting heart rate and HRV feed `WeekSummary` and can soften a good recovery reading and add a caution, never a target change.

`HealthSync.window` decides how far back a sync reads: the last `days` (7 by default; 30 on first connection; up to 365 on request), stretched back to an older day open on the Log screen. `HealthSettings.currentAuthVersion` is bumped whenever a release reads a new type; a connection whose stored version is lower calls `requestAuthorization` once (iOS prompts only for undecided types).

Syncs run on app start, on foreground, when the Log screen opens, and from the Sync and Update now buttons (20-second throttle unless forced), over the last seven days. Disconnecting only stops syncing. Health access can't be read back, so a declined type looks like no data. The entitlement signed correctly with a free personal team in this project.

### Notifications

Two local notification types, both scheduled on the phone:
- **Weekly plan reminder:** one repeating notification at a chosen day and time.
- **Daily log reminder:** because iOS can't check conditions at delivery, the app schedules one notification per day for the next 7 days and re-plans them whenever a log is saved, the app opens or leaves the foreground, or the setting changes. Today's is cancelled once the day's goals are met. Identifiers start with `logmo.daily-reminder.`.

### Weekly review

`ReviewRules.review` (WeeklyReview.swift) turns a week's snapshots into a `WeeklyReview`: one `ReviewMetric` per row (weight trend from `Metrics.weeklyTrendRows`, calories, protein days from `Insights.proteinDays`, steps, water, training, felt, measurements), the biofeedback rows, notes, a verdict and a calculated summary, each compared with the seven days before. It is pure and stored nowhere. `AIAdvisor.polishReview` asks Foundation Models to reword the summary and keeps it only if `NoteValidator.clean` accepts it (20 s limit). `DaySnapshot.strengthMinutes` carries Apple Health's strength minutes. The Sunday card uses `ReviewRules.isLastDayOfWeek`; `-forceReviewPrompt YES` and `-reviewOnAppear YES` are debug aids.

### AI suggestion

The suggestion is calculated first and explained second:

1. `SuggestionRules.summary` builds a numbers-only `WeekSummary` (weight slope over up to 21 days with scatter, recent slope, averages, days logged per metric, check-in averages and changes, sick and period days, estimated maintenance). It is shown to the user first.
2. `SuggestionRules.assess` turns it into an `Assessment`: per-metric `DataConfidence`, rate status against the campaign's band, intake and adherence, recovery, contradictions, the supported calorie, steps and lifting changes, the **allowed ranges**, and the evidence, caution and "needs more data" texts. All text is written from the facts.
3. `AIAdvisor` (Foundation Models, iOS 26+ with Apple Intelligence) gets the facts and ranges as structured context, picks calories, steps and lifting days **inside the ranges**, and writes a one- or two-sentence note.
4. `SuggestionRules.compose` clamps the model's choices to the ranges, rebuilds macros so they add up, and writes the headline. `NoteValidator` drops the note if it uses a number not in the facts or targets, makes a safety or medical claim, or is too long.

Pace and the Why: `assess` also works out `conservativeDelta`, an optional `aggressiveDelta` (faster end of the campaign's range, sized from estimated maintenance, at most `aggressiveStepLimit` = 250 kcal a day from the current goal, inside the same floor and maintenance limit, withheld with a reason when data or recovery argue against it) and `aggressiveNote`. `WeekSummary.pace` picks which one is the decision; `SuggestionRules.options` builds both. `SuggestionWhy.swift` writes the plain-language `WhyItem`s and the measurement lines from calculated facts. The Settings preference is `SettingsKey.pace` and is in the backup.

If the model is unavailable, fails, or takes longer than 25 seconds (`SuggestSheet.withTimeout`), steps 1, 2 and 4 stand alone. "Edit first" hands the goals to the parent, which opens the editor from the suggestion sheet's `onDismiss` (a fixed delay is not reliable on a slower device). No network is involved. Thresholds (confidence cut-offs, rate bands, the 1,500 kcal and 25% deficit low-target rules, step sizes) are constants in `WeekSuggestion.swift`; changing one means updating `WeekSuggestionTests`.

## 3. Build, sign and install

### Prerequisites
- Xcode (the project was built with Xcode 27), `brew install xcodegen`.
- An Apple ID signed in to Xcode. A paid developer account is not required, with the limits in section 6.

### Generate the project
The Xcode project is generated from `project.yml` and is **not committed**.

```
DEVELOPMENT_TEAM=<your team id> xcodegen generate
```

Run it again after adding or removing source files. Never commit the team id; it comes from the environment.

### Run the tests

```
xcodebuild test -project logmo.xcodeproj -scheme logmo \
  -destination 'platform=iOS Simulator,name=<a simulator>' \
  CODE_SIGNING_ALLOWED=NO GENERATE_INFOPLIST_FILE=YES
```

All tests must pass before anything is merged (250 at this version). They cover the pure rules and the SwiftData stores (in-memory containers), not the screens.

### Install on the iPhone

```
xcodebuild build -project logmo.xcodeproj -scheme logmo -configuration Debug \
  -destination 'id=<device id>' -allowProvisioningUpdates
xcrun devicectl device install app --device <device id> <path to logmo.app>
xcrun devicectl device process launch --device <device id> com.yebbah.logmo
```

Find the device id with `xcrun devicectl list devices`. The phone must be unlocked to launch. Installing over an existing copy keeps the data.

### Debug aids
Compiled only in Debug (`#if DEBUG`): launch arguments such as `-demo-data` (in-memory sample data), `-tab N`, `-debugScreen …`, `-scrollTo …`, `-suggestRun 1`. They never run in a release build.

## 4. Release process

1. Work on a branch off `main`, one topic per branch.
2. Update the PRD (`prd.md`): requirement, decision numbers, version in the front matter and the title.
3. Run the full test suite.
4. Commit, tag the PRD version (`prd-vX.Y`), push the branch and tags.
5. Fast-forward merge to `main` (`git merge --ff-only`), push `main`.
6. Build and install on the phone (section 3).
7. Raise `CURRENT_PROJECT_VERSION` by one for every push to `main` and add the build to `docs/changelog.md`.
8. Bump `MARKETING_VERSION` in `project.yml` when a release should show a new version in Settings → About and on the landing screen (it is still 1.0.0, build 6).

Mock-ups for screen changes are made first on the design canvas and agreed before building.

## 5. Data, privacy and recovery

- **Data stays on the phone.** The only things that leave it are files the user exports through the share sheet. The app makes no network requests.
- **Permissions:** notifications (requested when a reminder is turned on) and read access to Apple Health (requested when the user connects it). The app has the HealthKit entitlement (`logmo/logmo.entitlements`, generated by xcodegen from `project.yml`) and `NSHealthShareUsageDescription` in the plist.
- **Sensitive data:** weight, nutrition, cycle and illness are stored in the app's sandbox and are never included in the contact email (which carries only app and iOS versions).
- **AI:** the assistant sees only the numbers in the preview sheet, on the device.

### Backup and restore
- **Settings → Backup → Save a full backup** writes `logmo-backup.json`: every log, weekly goal, campaign and the settings. Keep it in Files or iCloud Drive.
- **Restore from a backup** replaces everything on the phone after a confirmation. Older backups (without settings) restore the data and leave settings alone.
- CSV exports (daily logs with campaign and goals, campaigns, weekly goals) are for spreadsheets only and cannot be restored.

### Recovery cases

| Situation | What to do |
|---|---|
| App won't open after 7 days (free account) | Don't delete it. Reinstall over it from Xcode; data is kept |
| App was deleted | Data is gone unless a backup exists. Reinstall and restore the backup |
| Wrong data after a bug | Restore the last backup, or Settings → Delete all data |
| New phone | Install, then restore a backup |

**Make a full backup before every install of a new version and at least weekly.**

## 6. Known limits and risks

- **Free Apple account:** the signed app expires after 7 days and must be reinstalled; at most 3 sideloaded apps; no TestFlight or App Store. A paid account removes the 7-day limit.
- **No cloud sync.** Data exists on one phone. The model is CloudKit-ready but sync is a later phase.
- **Apple Health is read-only.** `SyncBackend` for cloud sync is still only a protocol.
- **AI suggestion availability:** needs iOS 26+, a supported iPhone and Apple Intelligence turned on; otherwise the rule-based suggestion is used. The on-device model is small, so its numbers are clamped and are advice, not medical advice.
- **Daily reminders** for days the app isn't opened are scheduled a week at a time; if the app is not opened for over a week they stop until it is opened again.
- **Reminders depend on iOS permission.** If refused, the switches go back off.
- **Tests do not cover screens.** UI changes are checked by hand on a simulator and the phone.
- **Single-user, single-device.** No accounts, no sharing.

## 7. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| "No such module" or missing files after adding code | Re-run `xcodegen generate` |
| `xcodebuild` says no Info.plist for the test target | Add `GENERATE_INFOPLIST_FILE=YES` when testing, as above |
| Signing error installing | Run with `DEVELOPMENT_TEAM` set; use `-allowProvisioningUpdates`; unlock the phone |
| Launch fails with "Locked" | Unlock the phone, then launch the app by hand |
| Old data still showing after a wipe | Settings → Delete all data now deletes item by item and reports failures; if it shows an error, restore a backup and report it |
| Reminder not arriving | iOS Settings → Notifications → logmo; check Focus mode; check the switch and time in Settings; the daily one is skipped on days the goals are already met |
| Suggestion says it's unavailable | The message says why (device, setting, or iOS version); the basic suggestion still works |

## 8. Readiness for the App Store (not done)

Before submitting to anyone else: a paid Apple Developer account and a distribution profile; a privacy policy and App Privacy answers (data not collected; local notifications; on-device AI); an app icon set at all sizes (the supplied logo exists); a release build and TestFlight run; replacing `connectwithsvetlanamae@gmail.com` with a support address and adding a support page; accessibility pass (VoiceOver labels exist on key controls); iPad is unsupported (`TARGETED_DEVICE_FAMILY: 1`); consider CloudKit sync so a lost phone is not a lost history.

## 9. Contacts and ownership

- Owner and developer: Yvette Ebbah.
- In-app contact: Settings → About → Contact the developer (prepared email with only app and iOS versions).
- Planning documents: `_bmad-output/planning-artifacts/`. Design mock-ups: the shared design canvas.
