---
title: logmo iPhone App
status: approved
version: 4.0
created: 2026-11-11
updated: 2026-11-25
---

# logmo: Product Requirements (v4.0)

## Vision and outcome

A personal iPhone app for logging weight, food (calories and macros), water, steps and daily biofeedback (the 1–5 check-in ratings from the S3 Athletic Foundation workbook), with weekly goals, fitness campaigns (cut, bulk, maintenance), and a dashboard showing goal status, three streaks, compliance, and the weight trend with optional biofeedback trend lines. Data stays on the phone. The design leaves room for Apple Health and cloud sync later.

Success means the user can log a full day in under a minute and see at a glance whether they are keeping up and where their weight is heading.

**Source:** [Workbook analysis](./workbook-analysis.md) maps the S3 workbook (fields, formulas, defects). Only the daily-tracking fields are used so far.

## Core concepts

- **Day log:** one record per calendar day holding any of the values below. A value never entered is *missing*, never zero.
- **Logged day:** a day on which at least one tracker has a value.
- **Trackers:** weight, food, water, steps, check-in.
- **Fully logged:** every field of a tracker is entered. Food needs calories, protein, carbs and fat; check-in needs all seven ratings; weight, water and steps need their one value.
- **Week:** Monday to Sunday.
- **Weekly goals:** one set of goals per week (see FR-3).
- **Trend weight:** exponentially smoothed weight, distinct from a measured weight.

## Requirements

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

Empty fields stay empty. A day with nothing entered is not saved: clearing every field of a day removes its record. Where a goal exists, the empty field shows it as a hint (for example "goal 140").

**FR-2. Units.** The user chooses kg or lb. Weight is stored in kg, so switching units never alters data.

**FR-3. Weekly goals.** Goals are set per week and are expected to be set each Sunday for the coming Monday–Sunday week. A goal set has:
- **Calories:** a weekly total (kcal), with a direction: *at or under* (default) or *at or over*.
- **Protein:** grams per day.
- **Steps:** per day.
- **Water:** ml per day.

Every goal is optional; an empty field means no goal. A week with no goals of its own inherits the most recent earlier week's, and the editor says so. The Streaks tab prompts for goals on Sundays, and when none exist yet. The editor can open any past week, the current week or the next week, not later.

**FR-4. Goal status.**
- **Daily:** protein, steps and water are each met at or above the goal. A goal with no value logged is not met. A day's goals are met when every goal that was set is met; with no daily goals set, nothing counts as met.
- **Weekly calories:** judged on the week's **average** daily calories (over the days that have calories logged) against the weekly goal ÷ 7, in the chosen direction (*at or under* by default, or *at or over*). An average exactly at the target counts as met.
  - A *finished* week is met only if calories were logged on all seven days *and* the average is on target.
  - A week in progress shows its running average and whether it is currently on or off target. It is marked missed early once the week's total already exceeds an at-or-under goal, since the final average can no longer come back under it.
- The Streaks tab shows today's daily goals with progress, this week's average calories against the daily-equivalent target, how far over or under it is, and how many days are logged. It also shows the last 7 days of daily goals and the weekly calorie goal for the last 4, 8 or 12 weeks (selectable).

**FR-5. Streaks.** Three, each with current and best:
- **Logging:** consecutive days with anything logged.
- **Daily goals:** consecutive days whose daily goals were all met.
- **Weekly goal:** consecutive *finished* weeks whose calorie goal was met. The week in progress neither extends nor breaks it.

For logging and daily goals, a day not yet logged *today* does not break the current streak. Each streak's definition is behind a small "i" next to its name (FR-13).

**FR-6. Compliance.** A day is **complied** when every *required* tracker is fully logged, every daily goal that was set is met, *and* (when a calorie goal exists) the average calories of that day's week are on target. The calorie test uses the whole week's average (the week so far, while it is in progress), not the single day, so a day can change from complied to not complied as the week's average moves. Required trackers are chosen in Settings, all five by default. Over a 7- or 30-day window (today inclusive) the Streaks tab shows the share of days complied and, per tracker, the days it was fully logged. The count is always out of the full window (7 or 30 days). Today counts in the total and becomes a complied day once everything for it is done, so the ratio can rise during the day.

**FR-7. Weight trend and biofeedback.** Show weigh-ins and the smoothed trend as two separate lines: weigh-ins connected with markers, the trend as a thick line, with a legend. Ranges are 14 days, 30 days, 90 days or All (of the period selected with the Showing control, FR-12). The latest trend value and last weigh-in are shown, and value labels appear when 15 or fewer points are on screen. The trend is computed over all data and only displayed per period, so it never restarts at a campaign boundary.
- Smoothing: `trend = α × weight + (1 − α) × previous trend`, α = 2 / (N + 1). Default N = 16, matching the workbook's value for male input; the user can choose 7, 10, 14, 16 or 20. The first weigh-in seeds the trend, and days without a weigh-in carry the previous trend forward.
- **Biofeedback overlay:** a switch adds one smoothed trend line per rating beside the weight line, each with its own tick box to show or hide it. Ratings use a right-hand 1–5 axis and a fixed 7-day smoothing. The choices are remembered on the device.

**FR-8. Appearance.** Two themes, switched in Settings and remembered on the device: **Clean** (light, white cards, blue accent) and **Midnight** (dark navy, cyan accent). The choice applies to every screen, including charts and the biofeedback line colours. Clean is the default.

**FR-9. Local-first and control.** All data is stored on the device and works offline. The user can delete all data (logs, goals and campaign history) from Settings. Nothing is sent to any service.

**FR-10. Export.** From Settings, export all daily logs as a CSV file through the iOS share sheet. One row per day, oldest first, columns `date, weight_kg, calories_kcal, protein_g, fat_g, carbs_g, water_ml, steps` and the seven ratings. Dates are `yyyy-MM-dd`; weight is always kg; missing values are empty cells, so a real 0 stays distinguishable from missing. Goals are not included. Export is user-initiated and is the only way data leaves the phone. It is a backup, not an import path.

**FR-11. Fitness campaigns.** From Settings the user defines a campaign:
- **Type:** cut, bulk or maintenance.
- **Target weight** (optional for maintenance), **start date** and **length in weeks** (any number; nothing assumes four weeks to a month).
- Campaigns are numbered 1, 2, 3 … in order of creation.

Rules:
- Every day belongs to exactly one campaign.
- When no real campaign is running, an automatic **default maintenance campaign** is open. It takes the next number, so the stretches between campaigns keep their own history. The first default starts on the first logged day (or today).
- Starting a campaign closes the running default the day before the new start date. The start date can't be before the running default began.
- Only one real campaign runs at a time. It can be **ended early** (or run to its planned end); it stays in history either way. Ending it opens a new default campaign the next day.
- **History:** Settings lists every campaign (running, completed, ended early, default) with dates and trend-weight change. A detail view shows type, dates, planned and actual length, target, trend weight start to end, change, versus target, days logged out of its actual length in days, and average calories, protein and steps.

**FR-12. Dashboard tab (follows the campaign filter).** The app has four tabs: **Dashboard, Streaks, Log, Settings**. The Dashboard tab shows what can be filtered by campaign. Its **Showing** control sits under a small "Showing" label and uses the full row, so a long campaign name wraps instead of running over the card. Choices are *Current campaign* (default), *Overall (all time)*, or any past campaign. Sections, top to bottom:
1. **Campaign card:** title, dates, **days left** (a countdown from today to the last planned day, counting today: 28 on the first day of a 4-week campaign, 1 on the last planned day, 0 once it has passed), week x of y, target weight and distance from it (using the trend). Overall shows all data since the first weigh-in.
2. **Recent performance:** overall trend change in the period; average calories, protein and steps over the last 14 days; trend change over 7, 14 and 21 days. Averages use only days with a value.
3. **Weigh-ins and trend** chart (FR-7).
4. **Rate of change per week:** one bar per day, trend weight today minus 7 days earlier, over the last 12 weeks, with the latest value and its percent of body weight.
5. **Steps and calories:** last 14 days as grouped bars (steps on the left axis, calories on the right) and the past-7-day averages.
6. **Biofeedback, last 7 days:** one small bar chart per rating with its 7-day average and which direction is better: higher for sleep and training performance, lower for fatigue, stress, hunger and soreness, and none for appetite. Days without a rating have no bar.
7. **Protein intake:** days the protein goal was hit out of days with a goal, last 14 days. An unlogged day counts as missed.

**FR-13. Streaks tab (never filtered by campaign).** Everything here is about now or about all time. Top to bottom:
1. **Streaks** (FR-5), each name followed by a small "i" that opens a short explanation in a popover. There is no paragraph under the numbers.
2. **Set your weekly goals** banner (FR-3), shown on Sundays and when no goals exist yet.
3. **Goals:** today's protein, steps and water with progress, and this week's average calories against the daily-equivalent target (FR-4).
4. **Compliance** (FR-6), with an "i" for the definition.
5. **Daily goals, last 7 days:** its own card.
6. **Weekly calorie goal:** its own card, with the 4, 8 or 12 weeks selector inside it, so the selector can't be mistaken for a control of the daily row.
7. **Overall weight journey:** weigh-ins and trend across all campaigns, with the total change since the first weigh-in.

**FR-14. Full-screen charts.** The weigh-ins and trend chart, rate of change, steps and calories, and the overall weight journey each have an expand button. It opens the chart full screen and turns the phone to landscape; closing it returns to portrait. The rest of the app stays portrait. In full screen the weigh-ins and trend chart keeps its range selector and biofeedback switch, and shows weigh-in values (up to about a month of points) and the latest trend value.

## Extensibility (provisions, not features)

- **Apple Health:** a `HealthSource` interface exists; each weight records its source (`manual` now). When Health is added, imports must not overwrite a manual value for the same day.
- **Cloud sync:** the data model is compatible with CloudKit (defaulted fields, no unique constraints, per-record id and `updatedAt`). A `SyncBackend` interface exists for another backend.
- Neither is user-visible yet; Settings shows "Not yet available".

## Out of scope

Social features, Android, accounts, notifications, and everything listed under Later phases.

## Later phases (carried over from the draft PRD)

These were in the earlier draft and are deliberately deferred. Open questions are in the workbook analysis.

1. **Apple Health integration:** read weight, water, nutrition, steps, workouts. Per-type authorization; denied read cannot be told apart from no data.
2. **Cloud sync:** CloudKit or another backend, last-write-wins on `updatedAt`.
3. **Workbook import:** historical entries, previewed before commit, matched by date (not by row position), with the workbook's broken references reported rather than reproduced.
4. **Nutrition integration:** MyFitnessPal API access is currently closed to new requests; Apple Health nutrition and manual entry are the fallback. No scraping.
5. **Estimates:** setup-based maintenance and calorie ranges, and estimated maintenance (TDEE) from trend-weight change. Requires a safety review of the workbook's formulas before any recommendation is shown. (Goals are already built; the user sets them, they are not calculated.)
6. **Run log, weekly summaries and weekly assessment**, and the workbook's hidden sheets (Measurements, Weight Record, Weekly Check-Ins, Training Plan), whose intended role is unconfirmed.
7. **Overrides and conflict resolution** between synced sources and manual values.

## Quality and privacy

- Weight, nutrition and menstrual-related data is sensitive; do not log it, and request no permissions (the app currently asks for none).
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
| D13 | Compliance is always out of the full 7 or 30 days; today counts in the total and turns complied once everything for it is done | Decided: the user asked for the full window |
| D14 | Biofeedback lines use fixed 7-day smoothing | Assumption |
| D15 | Calories count toward compliance through the week's average (at or under by default), not per day | Decided: the user asked for it. Consequence: a day's compliance can change as the week's average moves |
| D16 | Goals are not in the CSV export | Assumption: backing up goals is a gap |
| D17 | Two themes (Clean, Midnight), chosen in Settings; Clean is the default | Decided |
| D18 | A finished week needs calories on all seven days to be "met", even though it is judged on the average | Assumption: confirm, or allow partial weeks |
| D19 | The Dashboard tab opens on the current campaign, with Overall one tap away; the filter scope is accepted as is | Decided: to be re-checked after use |
| D20 | Streaks and compliance are not filtered by campaign | Assumption: they describe consistency over time |
| D21 | The trend line is computed over all data and sliced per campaign | Assumption: smoothing shouldn't restart at a boundary |
| D22 | Only one real campaign at a time; start date can't precede the running default's start | Assumption |
| D23 | "Days left" counts down from today to the last planned day (start + weeks × 7 − 1), counting today | Decided: confirmed by the user |
| D24 | Deleting all data also deletes campaign history | Assumption |
| D25 | Choosing cut or bulk does not change the calorie-goal direction. It stays at-or-under for every campaign type (the user's goal is a lean bulk) | Decided: confirmed by the user |
| D26 | Weekly history length is selectable (4, 8, 12 weeks) | Decided: months can have 5 weeks |
| D27 | Four tabs, in this order: Dashboard (campaign-filtered), Streaks (not filtered), Log, Settings. The Streaks tab is named "Streaks" although it also holds goals, compliance and the overall journey | Decided: mockup approved. Rename if it reads wrong |
| D28 | The Streaks tab opens with the streaks, then the weekly-goals banner; the campaign filter sits at the top of the Dashboard tab | Decided: mockup approved |
| D29 | Landscape is used only for full-screen charts; everything else is portrait | Decided |
| D30 | All four charts (weigh-ins and trend, rate of change, steps and calories, overall journey) can go full screen. Biofeedback bars and the protein donut cannot | Assumption: the user said "the graph" |
