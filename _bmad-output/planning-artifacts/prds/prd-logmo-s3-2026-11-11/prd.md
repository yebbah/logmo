---
title: logmo iPhone App
status: approved
version: 2.1
created: 2026-11-11
updated: 2026-11-24
---

# logmo: Product Requirements (v2.1)

## Vision and outcome

A personal iPhone app for logging weight, food (calories and macros), water, steps and daily biofeedback (the 1–5 check-in ratings from the S3 Athletic Foundation workbook), with weekly goals and a dashboard showing goal status, three streaks, compliance, and the weight trend with optional biofeedback trend lines. Data stays on the phone. The design leaves room for Apple Health and cloud sync later.

Success means the user can log a full day in under a minute and see at a glance whether they are keeping up and where their weight is heading.

**Source:** [Workbook analysis](./workbook-analysis.md) maps the S3 workbook (fields, formulas, defects). Only the daily-tracking fields are used in v1.

## Core concepts

- **Day log:** one record per calendar day holding any of the values below. A value never entered is *missing*, never zero.
- **Logged day:** a day on which at least one tracker has a value.
- **Trackers:** weight, food, water, steps, check-in.
- **Fully logged:** every field of a tracker is entered. Food needs calories, protein, carbs and fat; check-in needs all seven ratings; weight, water and steps need their one value.
- **Week:** Monday to Sunday.
- **Weekly goals:** one set of goals per week (see FR-3).
- **Trend weight:** exponentially smoothed weight, distinct from a measured weight.

## Requirements (v2.0)

**FR-1. Log a day.** Choose any date up to today and view or edit that day's values:
- Weight (kg or lb).
- Food: calories (kcal), protein (g), carbs (g), fat (g).
- Water: total in ml, with quick-add buttons (+250, +500, +750).
- Steps.
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

Empty fields stay empty. A day with nothing entered is not saved. Where a goal exists, the empty field shows it as a hint (for example "goal 140").

**FR-2. Units.** The user chooses kg or lb. Weight is stored in kg, so switching units never alters data.

**FR-3. Weekly goals.** Goals are set per week and are expected to be set each Sunday for the coming Monday–Sunday week. A goal set has:
- **Calories:** a weekly total (kcal), with a direction: *at or under* (default) or *at or over*.
- **Protein:** grams per day.
- **Steps:** per day.
- **Water:** ml per day.

Every goal is optional; an empty field means no goal. A week with no goals of its own inherits the most recent earlier week's, and the editor says so. The dashboard prompts for goals on Sundays, and when none exist yet. The editor can open the current or next week, not later.

**FR-4. Goal status.**
- **Daily:** protein, steps and water are each met at or above the goal. A goal with no value logged is not met. A day's goals are met when every goal that was set is met; with no daily goals set, nothing counts as met.
- **Weekly calories:** judged on the week's **average** daily calories (over the days that have calories logged) against the weekly goal ÷ 7, in the chosen direction (*at or under* by default, or *at or over*). An average exactly at the target counts as met.
  - A *finished* week is met only if calories were logged on all seven days *and* the average is on target.
  - A week in progress shows its running average and whether it is currently on or off target. It is marked missed early once the week's total already exceeds an at-or-under goal, since the final average can no longer come back under it.
- The dashboard shows today's daily goals with progress, this week's average calories against the daily-equivalent target, how far over or under it is, and how many days are logged. It also shows the last 7 days of daily goals and the last 4 weeks of the weekly calorie goal.

**FR-5. Streaks.** Three, each with current and best:
- **Logging:** consecutive days with anything logged.
- **Daily goals:** consecutive days whose daily goals were all met.
- **Weekly goal:** consecutive *finished* weeks whose calorie goal was met. The week in progress neither extends nor breaks it.

For logging and daily goals, a day not yet logged *today* does not break the current streak.

**FR-6. Compliance.** A day is **complied** when every *required* tracker is fully logged, every daily goal that was set is met, *and* (when a calorie goal exists) the average calories of that day's week are on target. The calorie test uses the whole week's average (the week so far, while it is in progress), not the single day, so a day can change from complied to not complied as the week's average moves. Required trackers are chosen in Settings, all five by default. Over a 7- or 30-day window (today inclusive) the dashboard shows the share of days complied and, per tracker, the days it was fully logged. Today is left out of the count until it is complied, so an unfinished day is not a miss.

**FR-7. Weight trend and biofeedback.** Chart measured weights and the smoothed trend over 30 days, 90 days or 1 year, with the latest trend value and its 7-day change (hidden until a week of history exists).
- Smoothing: `trend = α × weight + (1 − α) × previous trend`, α = 2 / (N + 1). Default N = 16, matching the workbook's value for male input; the user can choose 7, 10, 14, 16 or 20. The first weigh-in seeds the trend, and days without a weigh-in carry the previous trend forward.
- **Biofeedback overlay:** a switch adds one smoothed trend line per rating beside the weight line, each with its own tick box to show or hide it. Ratings use a right-hand 1–5 axis and a fixed 7-day smoothing. The choices are remembered on the device.

**FR-8. Appearance.** Two themes, switched in Settings and remembered on the device: **Clean** (light, white cards, blue accent) and **Midnight** (dark navy, cyan accent). The choice applies to every screen, including charts and the biofeedback line colours. Clean is the default.

**FR-9. Local-first and control.** All data is stored on the device and works offline. The user can delete all data (logs and goals) from Settings. Nothing is sent to any service.

**FR-10. Export.** From Settings, export all daily logs as a CSV file through the iOS share sheet. One row per day, oldest first, columns `date, weight_kg, calories_kcal, protein_g, fat_g, carbs_g, water_ml, steps` and the seven ratings. Dates are `yyyy-MM-dd`; weight is always kg; missing values are empty cells, so a real 0 stays distinguishable from missing. Goals are not included. Export is user-initiated and is the only way data leaves the phone in v2.0. It is a backup, not an import path.

## Extensibility (provisions, not features)

- **Apple Health:** a `HealthSource` interface exists; each weight records its source (`manual` now). When Health is added, imports must not overwrite a manual value for the same day.
- **Cloud sync:** the data model is compatible with CloudKit (defaulted fields, no unique constraints, per-record id and `updatedAt`). A `SyncBackend` interface exists for another backend.
- Neither is user-visible in v1; Settings shows "Not yet available".

## Out of scope for v2.0

Social features, Android, accounts, notifications, and everything listed under Later phases. A new visual theme is planned but not yet specified: mockups are pending the user's choice.

## Later phases (carried over from the draft PRD)

These were in the earlier draft and are deliberately deferred. Open questions are in the workbook analysis.

1. **Apple Health integration:** read weight, water, nutrition, steps, workouts. Per-type authorization; denied read cannot be told apart from no data.
2. **Cloud sync:** CloudKit or another backend, last-write-wins on `updatedAt`.
3. **Workbook import:** historical entries, previewed before commit, matched by date (not by row position), with the workbook's broken references reported rather than reproduced.
4. **Nutrition integration:** MyFitnessPal API access is currently closed to new requests; Apple Health nutrition and manual entry are the fallback. No scraping.
5. **Estimates:** setup-based maintenance and calorie ranges, and estimated maintenance (TDEE) from trend-weight change. Requires a safety review of the workbook's formulas before any recommendation is shown. (Goals themselves are in v2.0; the user sets them, they are not calculated.)
6. **Run log, weekly summaries and weekly assessment**, and the workbook's hidden sheets (Measurements, Weight Record, Weekly Check-Ins, Training Plan), whose intended role is unconfirmed.
7. **Overrides and conflict resolution** between synced sources and manual values.

## Quality and privacy

- Weight, nutrition and menstrual-related data is sensitive; do not log it, and request no permissions in v1.
- Streak, goal, compliance and trend calculations are unit-tested, including missing days, a day not yet logged, goals exactly at the limit, finished weeks with an unlogged day, week boundaries, and no-data cases.
- Calculations never substitute a plausible value for missing data: no trend without a weigh-in, no 7-day change without 7 days of history, and a week with an unlogged day is never "met".

## Decisions and assumptions

| # | Decision | Status |
|---|---|---|
| D1 | Native SwiftUI, iOS 17+, SwiftData storage | Decided |
| D2 | Lean scope; the larger draft scope is deferred (Later phases) | Decided |
| D3 | A *logged* day (for the logging streak) means any tracker logged | Assumption: revisit after use |
| D4 | Default smoothing 16-day, user-adjustable | Assumption: workbook picks 16 or 20 by sex input |
| D5 | Water is tracked in ml only | Assumption |
| D6 | Rating anchors for all seven ratings | Decided: confirmed by the user |
| D7 | Goals are set each Sunday for the coming week; weeks run Monday to Sunday | Decided |
| D8 | Weekly calorie goal is judged "at or under" by default, switchable to "at or over" | Decided: default confirmed by the user |
| D9 | Daily protein, steps and water goals are met at or above the goal | Assumption |
| D10 | A week with any day lacking calories can't be "met" | Assumption |
| D11 | A week with no goals inherits the latest earlier goals | Assumption |
| D12 | Complied = every required tracker fully logged and every set daily goal met; required trackers are toggles, all on by default | Decided |
| D13 | Today is left out of compliance until complied | Assumption |
| D14 | Biofeedback lines use fixed 7-day smoothing | Assumption |
| D15 | Calories count toward compliance through the week's average (at or under by default), not per day | Decided: the user asked for it. Consequence: a day's compliance can change as the week's average moves |
| D16 | Goals are not in the CSV export | Assumption: backing up goals is a gap |
| D17 | Two themes (Clean, Midnight), chosen in Settings; Clean is the default | Decided |
| D18 | A finished week needs calories on all seven days to be "met", even though it is judged on the average | Assumption: confirm, or allow partial weeks |
