---
title: logmo iPhone App
status: approved
version: 1.3
created: 2026-11-11
updated: 2026-11-24
---

# logmo: Product Requirements (v1.3)

## Vision and outcome

A personal iPhone app for logging weight, food, water and daily biofeedback (the 1–5 check-in ratings from the S3 Athletic Foundation workbook), with a dashboard showing logging compliance, logging streak and weight trend. Data stays on the phone. The design leaves room for Apple Health and cloud sync later.

Success means the user can log a full day in under a minute and see at a glance whether they are keeping up and where their weight is heading.

**Source:** [Workbook analysis](./workbook-analysis.md) maps the S3 workbook (fields, formulas, defects). Only the daily-tracking fields are used in v1.

## Core concepts

- **Day log:** one record per calendar day holding any of the values below. A value never entered is *missing*, never zero.
- **Logged day:** a day on which at least one tracker has a value.
- **Trackers:** weight, food, water, check-in.
- **Trend weight:** exponentially smoothed weight, distinct from a measured weight.

## Requirements (v1.0)

**FR-1. Log a day.** Choose any date up to today and view or edit that day's values:
- Weight (kg or lb).
- Food: calories (kcal) and protein (g).
- Water: total in ml, with quick-add buttons (+250, +500, +750).
- Biofeedback: seven ratings, each 1–5 (scale below). Tap a selected rating again to clear it. The app shows the meaning of 1 and 5 under every rating.

| Rating | 1 | 5 |
|---|---|---|
| Sleep | Lowest quality | Best quality |
| Fatigue | Fresh, no fatigue | Exhausted |
| Stress | Calm, no stress | Extremely stressed |
| Hunger | Not hungry | Ravenous |
| Training performance | Very poor session | Excellent, a best |
| Appetite | No appetite | Very strong appetite |
| Soreness | Not sore | Severe, can't train |

Direction differs by category: higher is better for sleep and training performance, and higher means "more" for the rest. Values 2–4 are the steps between. All seven anchors are confirmed by the user (D6).

Empty fields stay empty. A day with nothing entered is not saved.

**FR-2. Units.** The user chooses kg or lb. Weight is stored in kg, so switching units never alters data.

**FR-3. Streak.** Show the current and longest run of consecutive logged days. A day that has not been logged *yet* today does not break the current streak.

**FR-4. Logging compliance.** Show, for the last 7 or 30 days (today inclusive): the share of days logged, and for each tracker the number of days it was logged.

**FR-5. Weight trend.** Chart measured weights and the smoothed trend over 30 days, 90 days or 1 year. Show the latest trend value and its 7-day change (hidden until a week of history exists).
- Smoothing: `trend = α × weight + (1 − α) × previous trend`, α = 2 / (N + 1). Default N = 16, matching the workbook's value for male input; the user can choose 7, 10, 14, 16 or 20.
- The first weigh-in seeds the trend. Days without a weigh-in carry the previous trend forward.

**FR-6. Local-first and control.** All data is stored on the device and works offline. The user can delete all data from Settings. Nothing is sent to any service.

**FR-7. Export.** From Settings, export all logs as a CSV file through the iOS share sheet (save to Files, AirDrop, etc.). One row per day, oldest first, columns `date, weight_kg, calories_kcal, protein_g, water_ml` and the seven ratings. Dates are `yyyy-MM-dd`; weight is always kg; missing values are empty cells, so a real 0 (for example 0 ml water) stays distinguishable from missing. Export is user-initiated and is the only way data leaves the phone in v1. It is a backup, not an import path.

## Extensibility (provisions, not features)

- **Apple Health:** a `HealthSource` interface exists; each weight records its source (`manual` now). When Health is added, imports must not overwrite a manual value for the same day.
- **Cloud sync:** the data model is compatible with CloudKit (defaulted fields, no unique constraints, per-record id and `updatedAt`). A `SyncBackend` interface exists for another backend.
- Neither is user-visible in v1; Settings shows "Not yet available".

## Out of scope for v1.0

Social features, Android, accounts, notifications, goals and targets, and everything listed under Later phases.

## Later phases (carried over from the draft PRD)

These were in the earlier draft and are deliberately deferred. Open questions are in the workbook analysis.

1. **Apple Health integration:** read weight, water, nutrition, steps, workouts. Per-type authorization; denied read cannot be told apart from no data.
2. **Cloud sync:** CloudKit or another backend, last-write-wins on `updatedAt`.
3. **Workbook import:** historical entries, previewed before commit, matched by date (not by row position), with the workbook's broken references reported rather than reproduced.
4. **Nutrition integration:** MyFitnessPal API access is currently closed to new requests; Apple Health nutrition and manual entry are the fallback. No scraping.
5. **Targets and estimates:** calorie, protein and step targets; setup-based maintenance and calorie ranges; estimated maintenance (TDEE) from trend-weight change. Requires a safety review of the workbook's formulas before any recommendation is shown.
6. **Run log, weekly summaries and weekly assessment**, and the workbook's hidden sheets (Measurements, Weight Record, Weekly Check-Ins, Training Plan), whose intended role is unconfirmed.
7. **Overrides and conflict resolution** between synced sources and manual values.

## Quality and privacy

- Weight, nutrition and menstrual-related data is sensitive; do not log it, and request no permissions in v1.
- Streak, compliance and trend calculations are unit-tested, including missing days, a day not yet logged, window edges and no-data cases.
- Calculations never substitute a plausible value for missing data: no trend without a weigh-in, no 7-day change without 7 days of history.

## Decisions and assumptions

| # | Decision | Status |
|---|---|---|
| D1 | Native SwiftUI, iOS 17+, SwiftData storage | Decided |
| D2 | v1 is the lean scope above; the larger draft scope is deferred | Decided |
| D3 | A logged day means *any* tracker logged (alternative: all of weight, food and water) | Assumption: revisit after use |
| D4 | Default smoothing 16-day, user-adjustable | Assumption: workbook picks 16 or 20 by sex input |
| D5 | Water is tracked in ml only | Assumption |
| D6 | Rating anchors for all seven ratings (table in FR-1) | Decided: confirmed by the user |
