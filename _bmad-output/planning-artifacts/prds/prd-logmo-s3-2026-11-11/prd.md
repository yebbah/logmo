---
title: logmo iPhone App
status: approved
version: 13.1
created: 2026-11-11
updated: 2026-11-25
---

# logmo: Product Requirements (v13.1)

## Vision and outcome

A personal iPhone app for logging weight, food (calories and macros), water, steps and daily biofeedback (the 1–5 check-in ratings from the S3 Athletic Foundation workbook), with weekly goals, fitness campaigns (cut, bulk, maintenance), and a dashboard showing goal status, three streaks, compliance, and the weight trend with optional biofeedback trend lines. Data stays on the phone. The design leaves room for Apple Health and cloud sync later.

Success means the user can log a full day in under a minute and see at a glance whether they are keeping up and where their weight is heading.

**Source:** [Workbook analysis](./workbook-analysis.md) maps the S3 workbook (fields, formulas, defects). Only the daily-tracking fields are used so far.

## Core concepts

- **Day log:** one record per calendar day holding any of the values below. A value never entered is *missing*, never zero.
- **Logged day:** a day on which at least one tracker has a value.
- **Trackers:** weight, food, water, steps, check-in.
- **Fully logged:** every field of a tracker is entered. Food needs calories, protein, carbs and fat; check-in needs all seven ratings (training performance may be n/a); weight, water and steps need their one value.
- **Week:** Monday to Sunday.
- **Weekly goals:** one set of goals per week (see FR-3).
- **Trend weight:** exponentially smoothed weight, distinct from a measured weight.

## Requirements

**FR-1. Log a day.** Choose any date up to today and view or edit that day's values. The date shows the day of the week ("Wednesday, 25 Nov 2026"); tapping it opens a calendar, and arrows step a day at a time.
- Weight (kg or lb).
- Food: calories (kcal), protein (g), carbs (g), fat (g).
- Water: total in ml, with quick-add buttons (+250, +500, +750, +1,000).
- Steps.
- **Cycle** (only when "Track my menstrual cycle" is on in Settings): "Are you on your period today?" with Yes and No. Tapping the chosen answer clears it. It is optional: it is not required for a complete day and never counts against compliance.
- **Health** (only when "Track when I'm sick" is on in Settings → Health): "Are you sick today?" with Yes and No. Tapping the chosen answer clears it. It works like the cycle question: optional, never part of compliance or streaks, stored only on the phone. Days marked yes show as yellow dots on the weigh-in and on the trend (the weigh-ins chart legend says "Sick"); if a day is both sick and on period, the weigh-in dot is yellow and the trend carries both dots. The question and the dots follow the switch, so turning it off hides them without deleting any answers.
- Biofeedback: seven ratings, each 1–5 (scale below). Tap a selected rating again to clear it. The app shows the meaning of 1 and 5 under every rating. **Training performance** is the last check-in item. Under its 1–5 buttons is a switch row, "Not a lifting day (n/a)": n/a is not a workout, but it counts as answered, so a rest day can still be a complete check-in. Switching n/a on dims and clears the rating, and choosing a rating switches n/a off.

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

**Saving is automatic**: changes are saved shortly after you stop typing, when you change the date or leave the screen, and when the app goes to the background. A "Saved" indicator shows the state; there is no Save button. Empty fields stay empty. A day with nothing entered is not saved: clearing every field of a day removes its record. Where a goal exists, the empty field shows it as a hint (for example "goal 140").

**FR-2. Units.** The user chooses kg or lb. Weight is stored in kg, so switching units never alters data.

**FR-3. Weekly goals, per campaign.** Goals belong to a campaign, not to the app as a whole. Within a campaign they are set per week, expected each Sunday for the coming Monday–Sunday week. A goal set has:
- **Calories:** a **daily goal** in kcal (for example 1,800 a day), judged on the **week's average**, with a direction: *at or under* (default) or *at or over*. The week's total allowed is the daily goal × 7 (12,600). Because it is judged weekly, calorie cycling is allowed: more on some days and less on others, as long as the week averages out.
- **Protein:** grams per day.
- **Steps:** a per-day figure, judged either as a **daily total** (every day must reach it) or as a **weekly average** (the week's average daily steps must reach it). The user chooses which.
- **Workout days:** a target number of workout days per week (0 to 7).
- **Water:** ml per day.

Every goal is optional; an empty field means no goal. Within a campaign, a week with no goals of its own inherits that campaign's most recent earlier week. A week is **Set by you** once the user has set or confirmed its goals, and **Carried over** while it only has goals inherited from an earlier week (or copied in when a campaign started).

**Setting a week** (the editor, FR-17): only **this week and the following four weeks**, inside the campaign, can be changed. **Earlier weeks are locked**: changing one would change its result and the streaks. The editor starts from last week's goals, so only what differs needs changing; each field that differs shows "was …" beside it. **Start from** offers *Last week* and *Blank*. **Repeat for the weeks after** gives the following weeks (up to four, inside the campaign) the same goals, and never overwrites a week the user already set. A campaign that has ended has no editable weeks.

When a campaign starts, including the automatic default one, it begins with a **copy of the most recent weekly goals** of the other campaigns, placed on the Monday of the week it starts, so nothing starts unset. That copy counts as *carried over* until the user confirms or changes it. If there are no goals anywhere yet, it starts with none. Goals made before goals were per campaign move to the campaign that contains their week.

Which goals apply:
- **A day** uses the goals of the campaign it belongs to (the latest set for its week or earlier). Daily goal status, the daily-goals streak, compliance and the protein donut all follow this.
- **A week's calorie goal** belongs to the campaign that contains the week's Monday. If a campaign starts mid-week, the new campaign's goals apply to its own days, and the week's calorie goal still comes from the campaign that held the Monday.

**FR-4. Goal status.**
- **Daily:** a **weigh-in logged that day** (counted whenever the campaign has any daily goal, whatever the required-trackers setting), plus protein and water, and steps when the steps goal is a daily total, are each met at or above the goal. A goal with no value logged is not met. A day's goals are met when every goal that was set is met; with no daily goals set, nothing counts as met.
- **Weekly calories:** judged on the week's **average** daily calories (over the days that have calories logged) against the daily goal, in the chosen direction (*at or under* by default, or *at or over*). An average exactly at the target counts as met.
  - A *finished* week is met only if calories were logged on all seven days *and* the average is on target.
  - A week in progress shows its running average and whether it is currently on or off target. It is marked missed early once the week's total already exceeds an at-or-under goal, since the final average can no longer come back under it.
- **Weekly steps average:** when the steps goal is a weekly average it is judged exactly like calories, at or over: the average over the days with steps logged against the daily goal, and a finished week is met only if steps were logged on all seven days.
- **Workout days:** the week's workout days are the days with a Training performance rating of 1 to 5; n/a days and unrated days don't count. The goal is met once the count reaches the target. It is marked missed as soon as it can't be reached any more (days done plus days still open, counting today if it is unanswered, fall short of the target) and at the end of a week that fell short.
- **All weekly goals:** a week's overall result is met only when every weekly goal that was set (calories, weekly-average steps, workout days) is met, missed if any is missed, and in progress otherwise.
- The Goals card on the Dashboard tab (FR-12) shows today's daily goals with progress, and for this week the average calories against the daily-equivalent target, the weekly steps average and the workout days, each with its status. The Streaks tab shows the last 7 days of daily goals and the weekly results for the last 4, 8 or 12 weeks (selectable).

**FR-5. Streaks.** Three, each with current and best:
- **Logging:** consecutive days with anything logged.
- **Daily goals:** consecutive days whose daily goals were all met.
- **Weekly goal:** consecutive *finished* weeks in which every weekly goal was met (calories, weekly-average steps, workout days; each week against its own campaign's goals). The week in progress neither extends nor breaks it.

For logging and daily goals, a day not yet logged *today* does not break the current streak. Each streak's definition is behind a small "i" next to its name (FR-13).

**FR-6. Compliance.** A day is **complied** when every *required* tracker is fully logged, every daily goal that was set is met, *and* the week-level goals of that day's week are on track: the average calories (when a calorie goal exists), the average steps (when the steps goal is a weekly average), and the workout days (when a target exists, they must be reached or still reachable). Calories and weekly-average steps are judged on the **whole week**, so cycling works: while the week is open, a high or low day is not a miss (the only exception is a calorie total that has already passed the whole week's allowance for an at-or-under goal, which can no longer recover), and once the week is finished all of its days comply or none do, according to the week's average. Workout days must be reached or still reachable. So a day's status can change while its week is open. A missing training performance answer (a rating or n/a) keeps the check-in incomplete. Required trackers are chosen in Settings, all five by default. Over a 7- or 30-day window (today inclusive) the Streaks tab shows the share of days complied and, per tracker, the days it was fully logged. The count is always out of the full window (7 or 30 days). Today counts in the total and becomes a complied day once everything for it is done, so the ratio can rise during the day.

**FR-7. Weight trend and biofeedback.** Show weigh-ins and the smoothed trend as two separate lines: weigh-ins connected with markers, the trend as a thick line, with a legend. Ranges are 14 days, 30 days, 90 days or All (of the period selected with the Showing control, FR-12). The latest trend value and last weigh-in are shown, and value labels appear when 15 or fewer points are on screen. The trend is computed over all data and only displayed per period, so it never restarts at a campaign boundary. When cycle tracking is on, a day marked as on the period is a **red dot** on the weigh-in and on the trend at that date, with an "On period" entry in the legend (also in full screen).

**Protein intake** sits under the chart in the same card and follows the same range selector (14 days, 30 days, 90 days, All): days the protein goal was hit out of days with a protein goal in that range, as a donut with "n/m". An unlogged day with a goal counts as missed. It is not shown in the landscape full-screen view.
- Smoothing: `trend = α × weight + (1 − α) × previous trend`, α = 2 / (N + 1). Default N = 16, matching the workbook's value for male input; the user can choose 7, 10, 14, 16 or 20. The first weigh-in seeds the trend, and days without a weigh-in carry the previous trend forward.
- **Biofeedback overlay:** a switch adds one smoothed trend line per rating beside the weight line, each with its own tick box to show or hide it. Ratings use a right-hand 1–5 axis and a fixed 7-day smoothing. The choices are remembered on the device.

**FR-8. Appearance.** Two themes, switched in Settings and remembered on the device: **Clean** (light, white cards, blue accent) and **Midnight** (dark navy, cyan accent). The choice applies to every screen, including charts and the biofeedback line colours. Clean is the default.

**FR-9. Local-first and control.** All data is stored on the device and works offline. The user can delete all data (logs, goals and campaign history) from Settings. Nothing is sent to any service.

**FR-10. Export.** From Settings, export all daily logs as a CSV file through the iOS share sheet. One row per day, oldest first, columns `date, weight_kg, calories_kcal, protein_g, fat_g, carbs_g, water_ml, steps`, the seven ratings `performance_na` (true when training performance was answered n/a), `on_period` and `sick` (true or false when answered, blank when not). Dates are `yyyy-MM-dd`; weight is always kg; missing values are empty cells, so a real 0 stays distinguishable from missing. Each day's row also says which campaign it belongs to (`campaign_number, campaign, campaign_kind`) and carries that day's goals (`goal_calories_per_day, goal_calories_basis, goal_protein_g, goal_steps, goal_steps_basis, goal_water_ml, goal_workout_days`), so the file stands on its own. Two more CSV files complete the export: **campaigns** (number, name, kind, whether automatic, target weight, start, planned weeks, end, ended early) and **weekly goals** (one row per campaign-week with its goals and whether the user set it). Export is user-initiated and is the only way data leaves the phone. The CSVs are for spreadsheets, not an import path; the full backup (FR-20) is the way back in.

**FR-11. Fitness campaigns.** On the Campaigns tab (FR-16) the user starts a campaign with the **+ New** button, and defines it:
- **Type:** cut, bulk or maintenance.
- **Target weight** (optional for maintenance), **start date** (today, an earlier date, or a date up to a year ahead) and **length in weeks** (any number; nothing assumes four weeks to a month).
- An optional **label** of the user's own (for example "Summer cut", up to 40 characters), set when starting the campaign and editable later from the campaign's detail screen. Without a label the standard name is used ("Campaign 2 · Cut"; "(default)" for an automatic one).
- Campaigns are numbered 1, 2, 3 … in order of creation.
- **Dates are appended automatically** wherever a campaign is named, worked out from its settings so they follow any change: "29 Oct – 23 Dec" (to the planned last day while it runs; to the actual last day once ended, so ending early updates it), or "since 11 Nov" for an open-ended default. A year is added for dates outside the current year. The Showing menu reads "#2 Summer cut · 29 Oct – 23 Dec", the campaign card and goals card show the label with the number, type and dates, and the history and detail screens show the same.

Rules:
- Every day belongs to exactly one campaign.
- When no real campaign is running, an automatic **default maintenance campaign** is open. It takes the next number, so the stretches between campaigns keep their own history. The first default starts on the first logged day (or today).
- Starting a campaign closes the running default the day before the new start date. With a **future start date** the campaign is *upcoming*: the current campaign carries on until the day before, the Dashboard shows a countdown to the start, and the upcoming campaign counts as the one real campaign allowed, so another can't be started until it is cancelled. **Cancelling** an upcoming campaign removes it (and its goals) and the current campaign carries on. An upcoming campaign gets the usual copy of the latest goals and can be edited before it starts.
- Starting a campaign closes the running default the day before the new start date. The start date can't be before the running default began.
- **Queueing:** while a real campaign runs, the next one can be planned to start after its planned last day (+ New offers that date as the earliest). If it starts later than the day after, a maintenance campaign fills the days in between. A running campaign whose planned days are over, with another queued, closes itself on its planned last day. Only one campaign can be *planned* (not yet started) at a time.
- **Changing campaigns.** A **running** campaign can be **extended** by 1, 2, 4 or 8 weeks (Campaigns tab → Extend). If a queued campaign starts before the new end, the extension is refused and the app offers to move that campaign's start date first. An **upcoming** campaign can have its **start date and length** edited (Campaigns tab → Edit dates & length); the earliest start is the day after the running campaign's planned end, or tomorrow; the maintenance days around it adjust, and its weekly goals are copied again from the latest ones for the new weeks. A **past** campaign (ended, completed or a closed default) can't be changed at all: not its label, dates, length or weekly goals.
- **Closing soon:** with 7 days or fewer left in a running campaign, the Dashboard shows a card: with nothing queued it offers **Extend 2 weeks** or **Extend 4 weeks** (or **Not now**, which hides it for the day); with a campaign already planned it says so, names its start date and asks whether to **move its start date**.
- Only one real campaign runs at a time. It can be **ended early** (or run to its planned end); it stays in history either way. Ending it opens a new default campaign the next day (or, with a campaign queued, maintenance until it starts).
- **History:** every campaign (running, upcoming, completed, ended early, default) is kept and looked back on from the Campaigns tab (FR-16).

**FR-12. Dashboard tab (follows the campaign filter).** The app has five tabs: **Dashboard, Streaks, Log, Campaigns, Settings**. The Dashboard tab shows what can be filtered by campaign, including the goals. Its **Showing** control sits under a small "Showing" label and uses the full row, so a long campaign name wraps instead of running over the card. Choices are *Current campaign* (default), *Overall (all time)*, or any past campaign. Sections, top to bottom:
1. **Campaign card:** the label (or standard name), then "#number type · dates", **days left** (a countdown from today to the last planned day, counting today: 28 on the first day of a 4-week campaign, 1 on the last planned day, 0 once it has passed), week x of y, target weight and distance from it (using the trend). For an upcoming campaign it shows the number of days until it starts and its planned length. Overall shows all data since the first weigh-in.
2. **Plan prompt** (FR-17), shown when the weekly plan needs a decision.
3. **Goals card** for the campaign being shown. For the campaign running today it is live: today's weigh-in (logged or not yet), protein, steps and water with progress, this week's average calories against the daily-equivalent target (FR-4), an **Edit goals** button and a **Weekly plan** link, and a "Carried over" chip when this week's goals were not set or confirmed. For a past campaign it summarises that campaign: days on which the daily goals were met out of days with goals, finished weeks whose calorie goal was met, and the goals it ended with. With *Overall* selected it shows the campaign running today.
4. **Recent performance:** overall trend change in the period; average calories, protein and steps over the last 14 days; trend change over 7, 14 and 21 days. Averages use only days with a value.
5. **Weigh-ins and trend** chart (FR-7), with the protein intake summary under it.
6. **Rate of change per week:** one bar per day, trend weight today minus 7 days earlier, over the last 12 weeks, with the latest value and its percent of body weight.
7. **Steps and calories:** last 14 days as grouped bars (steps on the left axis, calories on the right) and the past-7-day averages.
8. **Biofeedback, last 7 days:** one small bar chart per rating with its 7-day average and which direction is better: higher for sleep and training performance, lower for fatigue, stress, hunger and soreness, and none for appetite. Days without a rating have no bar.

**FR-13. Streaks tab (never filtered by campaign).** Everything here is about now or about all time. Top to bottom:
1. **Streaks** (FR-5), each name followed by a small "i" that opens a short explanation in a popover. There is no paragraph under the numbers.
2. **Compliance** (FR-6), with an "i" for the definition.
3. **Daily goals, last 7 days:** its own card.
4. **Weekly goals:** its own card, a mark for each week (all weekly goals met, missed, or open), with the 4, 8 or 12 weeks selector inside it, so the selector can't be mistaken for a control of the daily row.
5. **Overall weight journey:** weigh-ins and trend across all campaigns, with the total change since the first weigh-in.

Streaks, compliance and the history cards use each day's own campaign goals (FR-3), so they run across campaign changes. Goals themselves are shown and set on the Dashboard tab.

**FR-14. Full-screen charts.** The weigh-ins and trend chart, rate of change, steps and calories, and the overall weight journey each have an expand button. It opens the chart full screen and turns the phone to landscape; closing it returns to portrait. The rest of the app stays portrait. In full screen the weigh-ins and trend chart keeps its range selector and biofeedback switch, and shows weigh-in values (up to about a month of points) and the latest trend value.

**FR-15. About, version and contact.** Settings has an About section with the logmo logo, the tagline "Track progress with clarity", the **version** and build ("1.0.0 (1)", set in `project.yml`), and **Contact the developer**: it opens a prepared email to connectwithsvetlanamae@gmail.com with a subject and a footer that carry only the app and iOS versions, never anything from the user's logs. The address is also shown with a Copy button for people without a mail app set up. The app icon is the supplied logo: a blue square with a white check above four rising bars.

**FR-16. Campaigns tab.** The home for campaigns: managing the one running, and looking back at all of them. Goals and campaigns are no longer in Settings.
- **Running now** card, for the campaign that today belongs to: its name, "#number type · dates", week x of y and days left with a progress bar for a real campaign. A real campaign has **Weekly plan**, **Rename**, **Extend** (1, 2, 4 or 8 weeks) and **End campaign** (with a confirmation; it stays in history and a default campaign starts the next day). The automatic default campaign shows "No campaign running" with **Start a campaign**, **Weekly plan** and **Rename**. **+ New** (top right) opens the new-campaign form (FR-11); it and Start are disabled while a real campaign is running or upcoming.
- **Upcoming** card (FR-11) with its countdown, **Edit dates & length**, **Weekly plan**, **Rename** and **Cancel it**.
- **Look back**: one card per campaign, newest first, each with its name, status (running, upcoming, closed, completed, ended early), "#number type · dates · length" (for one ended early, days run out of days planned), the **trend weight change** with start and end weights and the target, and three figures: **compliance** (complied days of days so far, as a percent), **average steps** and **average calories**, then a line with weekly goals met of finished weeks and workout days a week against the target. A campaign with no weigh-ins says so; an upcoming one shows only its start.
- **A campaign's look back** (tap a card):
  - Header: name, status, "#number type · dates", and planned versus actual length.
  - **Result:** trend weight change, start to end, how far from the target, a small trend chart with the target line, the average change a week (change across the campaign, per week; needs a week of data), the **fastest week** (the largest 7-day change in the trend) and days weighed of days.
  - **Compliance:** percent and complied days of days so far, one square per day (complied, not complied, or still open for today) and bars per tracker (days fully logged).
  - **Weekly plan** (read-only): the weeks that have begun, newest first, each with the goals set for it (changes from the week before highlighted), whether it was set by the user or carried over, how many of its days complied under its goals, a one-square-per-day strip, and whether its weekly goals were met or missed with the reason (for example "calories averaged 2,050 against 1,800", "1 of 3 workouts"). It shows four weeks and expands to all. A campaign that is running or upcoming also links to its editable plan.
  - **Averages:** calories, protein, carbs, fat, steps, water, and the biofeedback averages with which direction is better. A rating that was never logged has no average.
  - **Label** (editable only while the campaign hasn't ended; a past campaign shows it read-only with a note) and **Open on Dashboard**: switches to the Dashboard tab with this campaign chosen in the Showing control. It is hidden for a campaign that hasn't started.
- Compliance for a campaign counts every day from its start to its end (or today), the same rules as FR-6; a running campaign counts today.

**FR-17. Weekly plan.** A campaign's weekly goals, week by week, opened from the **Weekly plan** button on the Campaigns tab or the link on the Dashboard Goals card.
- **This week** comes first, then **Plan ahead**, then past weeks (locked).
- **Plan ahead:** the next four weeks, each with its goals (changes from the week before highlighted, with the old value), a "Set by you" or "Carried over" chip, and **Same as before** (confirms it) and **Edit**.
- **This week:** the same, with its compliance so far.
- **Past weeks**, newest first, **locked**: goals, set or carried over, "n of 7 days complied" under that week's goals, a strip of the days, and the result with its reason. There is no way to edit them.
- **Plan prompt**, on the Dashboard and at the top of the plan: with no goals at all, "Set your weekly goals"; on any day but Sunday when this week is only carried over, "This week's goals are carried over" with **Keep them** (confirms them) and **Change them**; on Sunday, if next week isn't set, "Plan next week" with **Same as this week** and **Change it**. Confirming counts as setting the week, so the prompt goes away.

**FR-18. Reminders.** In Settings, a **Weekly plan reminder** switch with a day of the week and a time the user chooses (Sunday 18:00 by default). When on, a local notification repeats weekly at that time: "Plan your week. Set next week's goals in logmo." It carries nothing from the user's logs. Turning it on asks iOS for permission; if that is refused the switch goes back off and Settings points to iOS Settings. Turning it off cancels the notification, and changing the day or time reschedules it.

**FR-19. Launch.** The launch screen shows the logo on a plain background from the first moment, with no white flash. The landing screen then shows the logo, "logmo" and the tagline as one block centred slightly above the middle, and the version at the bottom, for three seconds in all, and fades into the Dashboard. The Dashboard is built behind it, so the landing is on screen immediately. Tapping the landing skips the wait.

**FR-20. Full backup and restore.** Settings → Backup has **Save a full backup** (one JSON file with every log, every weekly goal (including whether it was set or carried over), every campaign and the user's settings (units, trend smoothing, required trackers, theme, cycle tracking, weekly reminder, biofeedback overlay, campaign filter, the cycle and sick switches), through the share sheet, for Files or iCloud Drive) and **Restore from a backup**, which asks first and then replaces everything on the phone. A file that isn't a logmo backup is refused with a message. Nothing is sent anywhere by the app. Cloud sync stays a later phase.

**FR-21. Delete all data.** Settings → Delete all data removes every log, goal and campaign, one by one, and checks the save; if it fails an alert says so. Afterwards the app is as new: one automatic maintenance campaign, the Dashboard back on *Current campaign*, the setup card (FR-22) showing again. Nothing from the old data remains on any screen.

**FR-22. Setup and nudges.** (a) **No campaign:** when no real campaign is running or upcoming, the Dashboard shows a *Set up a campaign* card with a three-step checklist (start a campaign, set weekly goals, log a first day). Its main button does the next step; for the campaign step it opens the Campaigns tab with the new-campaign form already open. **Not now** hides the card for the rest of the day. While it shows, the separate "Set your weekly goals" banner is hidden. (b) **Finished campaign:** a real campaign whose planned weeks are over but which is still open shows a card on the Dashboard: **End & see results** (closes it on its last planned day, not as ended early, and opens the Campaigns tab) or **Extend 2 weeks** (refused if it would run into a later campaign). (c) **Log completeness:** under the date, the Log tab shows one icon per required tracker (scale, fork and knife, drop, walking figure, checklist), grey until complete and then green with a tick, each with a spoken label such as "Water, done"; no words, so nothing can be cut short (ticked when complete: food needs all four macros, check-in all seven ratings, with n/a counting for training performance) and "n of m".

**FR-23. Weekly suggestion (Apple Intelligence).** On demand, any day, the user can ask for a suggestion for next week's goals: the **Suggest** link on the live Goals card, the sparkles button on the Weekly plan screen, and a third button on the "Plan next week" and "carried over" prompts. It is not tied to Sunday.
- **What is shared.** A sheet first shows exactly what the assistant will see, as numbers only: campaign type and week, weight trend per week, average calories, protein, carbs, fat and steps against goal, workout days, days with daily goals met, the check-in averages for the week, and (only if the user tracks them, each with its own switch for this suggestion) period days and sick days. No name, email, campaign label, dates or notes. The user chooses to assess **This week so far** (the default when at least three days are logged) or **Last week**. At least three logged days are needed.
- **Who runs it.** Apple Intelligence's on-device model (the Foundation Models framework, iOS 26 or later on a supported iPhone with Apple Intelligence on), so nothing leaves the phone and no key or server is involved. Otherwise a **basic, rule-based suggestion** is used and the sheet says why.
- **What it proposes.** Calories a day, protein, carbs, fat, steps, lifting days and water for next week, with three to five short reasons tied to the numbers. The campaign type sets what a good pace is (cut about -0.3 to -1.0% of body weight a week, bulk about +0.1 to +0.6%, maintenance within 0.25%). Sick days mean no harder cut, no more steps and lighter lifting; period days mean a stall isn't read as a reason to cut harder; fatigue, soreness or poor training performance mean one lifting day fewer and no harder cut; high hunger on a cut is noted.
- **Guard rails.** Whoever proposes, the numbers are held in the app: calories move at most 150 a day from this week's goal and never below 1,200, steps at most 2,000, lifting days at most 1, and a cut never gets harder in a sick or very fatigued week.
- **Approval.** Nothing is saved until the user taps **Use for next week** (saved as "Set by you", keeping the week's judging modes), or **Edit first** (opens the week editor filled with the suggestion), or **Not now**. It is a suggestion, not medical advice, and the sheet says so.
- **Carbs and fat guidance.** Weekly goals gain a **carbs** and a **fat** figure (g a day), set in the week editor or by a suggestion. They are guidance: shown in the plan line, as hints in the Log screen's carbs and fat fields, in the exports and the backup, and carried over like other goals. They are never judged as met or missed and never affect compliance or streaks.

**FR-24. Daily log reminder.** In Settings → Reminders, a **Daily log reminder** switch with a time the user chooses (20:00 by default), separate from the weekly plan reminder (FR-18). Turning it on asks iOS for notification permission; if refused it goes back off and Settings points to iOS Settings.
- **Only when needed.** A reminder is sent on a day only if that day's daily goals aren't done: with daily goals set, until all are met (the weigh-in, protein, steps and water that are set; FR-6); with none set, until every required tracker is complete, or, if none is required, until anything is logged.
- **How.** iOS can't decide at delivery time, so the app schedules one notification a day for the next seven days and re-plans whenever a log is saved, the app opens or leaves the foreground, or the switch or time changes. When today's goals are met, today's notification is cancelled; tomorrow's stays. Days the app isn't opened still get their reminder, which is the point.
- **Content.** "Time to log: You haven't finished today's goals in logmo yet." Nothing from the user's logs. Turning the switch off cancels all of them. The switch and time are in the full backup.

## Extensibility (provisions, not features)

- **Apple Health:** a `HealthSource` interface exists; each weight records its source (`manual` now). When Health is added, imports must not overwrite a manual value for the same day.
- **Cloud sync:** the data model is compatible with CloudKit (defaulted fields, no unique constraints, per-record id and `updatedAt`). A `SyncBackend` interface exists for another backend.
- Neither is user-visible yet; Settings shows "Not yet available".

## Out of scope

Social features, Android, accounts, push notifications from a server (the app only schedules local ones), and everything listed under Later phases.

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

- Weight, nutrition and menstrual-related data is sensitive; do not log it. The only permission the app asks for is notifications, and only when the user turns on a reminder. Apple Intelligence suggestions run on the device (FR-23).
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
| D11 | Within a campaign, a week with no goals inherits that campaign's latest earlier goals | Assumption |
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
| D27 | Five tabs, in this order: Dashboard (campaign-filtered), Streaks (not filtered), Log, Campaigns, Settings. The Streaks tab is named "Streaks" although it also holds goals-related history, compliance and the overall journey (it was four tabs before the Campaigns tab, D52) | Decided: mockup approved |
| D28 | The Streaks tab opens with the streaks, then the weekly-goals banner; the campaign filter sits at the top of the Dashboard tab | Decided: mockup approved |
| D29 | Landscape is used only for full-screen charts; everything else is portrait | Decided |
| D30 | All four charts (weigh-ins and trend, rate of change, steps and calories, overall journey) can go full screen. Biofeedback bars and the protein donut cannot | Assumption: the user said "the graph" |
| D31 | Weekly goals are stored per campaign, not globally | Decided: the user asked for it |
| D32 | A new campaign (including the automatic default) starts with a copy of the most recent goals | Decided: the user chose copy |
| D33 | A day uses its own campaign's goals; a week's weekly goals belong to the campaign containing the week's Monday | Decided: accepted by the user, to be tuned after use |
| D34 | Goals are shown and set on the Dashboard tab; Overall shows the current campaign's goals; past campaigns' goals are read-only summaries | Decided: accepted by the user |
| D35 | The goals editor opens from the Dashboard prompt, the Goals card and the weekly plan, for the campaign concerned and a chosen week. It is not in Settings or on the campaign card | Decided |
| D36 | Saving on the Log screen is automatic; there is no Save button | Decided |
| D37 | A steps goal is either a daily total or a weekly average, chosen per goal set | Decided: the user asked for both |
| D38 | A workout day is a day with a training performance rating (1–5); n/a means not a lifting day and is not a workout | Decided |
| D39 | The workout target is assessed per week and feeds compliance and the weekly streak. Compliance stays red for every day of a week once its target is out of reach | Decided: accepted by the user |
| D40 | A finished week with the steps goal as a weekly average needs steps on all seven days to be met, like calories | Assumption |
| D41 | Workout days need no 7-day logging: a finished week is met if the count reached the target | Assumption |
| D42 | The calorie goal is entered per day and stored as a weekly total (× 7). Older goals entered as weekly totals keep their value and show as the per-day equivalent (14,500 a week shows as 2,071 a day) | Decided: the user asked for per-day entry |
| D43 | Calorie cycling is allowed. Calories and weekly-average steps affect compliance only when the week is finished, apart from a calorie total already past an at-or-under allowance | Decided: accepted by the user |
| D44 | Cycle tracking is an opt-in toggle in Settings ("Track my menstrual cycle"), not a sex field in a profile. The daily question is optional and not part of compliance | Decided: accepted by the user |
| D45 | Period days are shown as red dots whenever cycle tracking is on, independent of the "Show biofeedback" switch | Decided: accepted by the user |
| D46 | A new campaign can start up to a year ahead; an upcoming campaign counts as the one real campaign and can be cancelled | Decided |
| D47 | Protein intake follows the weigh-ins range selector and is no longer its own card | Decided: the user asked for it |
| D48 | The app icon and in-app logo come from the supplied logo sheet (kept in `design/`), redrawn at 1024 px | Decided |
| D49 | App version starts at 1.0.0 (build 1) | Assumption: bump `MARKETING_VERSION` in project.yml per release |
| D50 | A campaign can carry an optional label; the name shown is the label or "Campaign N · Type", always followed by its dates, which are worked out from the campaign and so change if it is ended early | Decided: the user asked for it |
| D51 | Compliance per campaign is shown on the Campaigns tab (look back), not on the Streaks tab, which keeps only the 7-day and 30-day compliance | Decided: the user chose a Campaigns tab over a Streaks-tab list |
| D52 | A fifth tab, Campaigns, holds starting, ending, cancelling, renaming and the goals entry for campaigns; Settings no longer has "Goals and campaigns" | Decided |
| D53 | A campaign's compliance, averages and goal results cover its own days only, from its start to its end (or today); the trend is the one computed over all data, so start and end weights come from a series that doesn't restart | Decided |
| D54 | "Open on Dashboard" switches tabs and selects the campaign, replacing the old "Show on dashboard" button that only changed the filter | Decided: the user pointed out the label implied navigation |
| D55 | "Fastest week" is the largest 7-day change of the trend within the campaign | Assumption |
| D56 | Past weeks of the plan are locked, with no way to edit them | Decided |
| D57 | Planning reaches four weeks ahead (this week plus four), inside the campaign | Decided |
| D58 | A weekly-plan reminder is optional, switchable, and its day and time are the user's choice | Decided |
| D59 | The landing screen shows for three seconds in all and fades out. It is drawn alone first so it appears immediately | Decided |
| D60 | The launch screen shows the logo on a light or dark background matching the system appearance | Assumption: it can't know the in-app theme choice |
| D61 | "Set by you" means the user set or confirmed a week. Goals copied in when a campaign starts, and inherited ones, are "carried over" until then | Decided |
| D62 | The prompt on days other than Sunday concerns this week; on Sunday it concerns next week and not this one | Assumption |
| D63 | Confirming a week ("Keep them", "Same as before") creates that week's own record with the carried-over goals | Decided |
| D64 | Delete-all removes each object and checks the save, rather than a batch delete whose errors were swallowed | Fixed after a report that old data stayed visible |
| D65 | Restoring a backup replaces everything on the phone, after confirmation; it does not merge | Assumption: simplest and safest |
| D66 | The setup card is put off per day, not forever | Assumption: a nudge, not a nag |
| D67 | A finished campaign stays open (and keeps collecting days) until the user closes or extends it | Assumption: nothing changes without the user |
| D68 | The Streaks "Daily goals, last 7 days" row uses the goals of the campaign each day belongs to, and a day before the first logged day shows the neutral hollow circle, not a red cross | Fixed after a campaign started midweek showed red crosses for the days before it |
| D69 | Restoring a backup also restores settings; a version-1 backup (no settings) restores the data and leaves settings alone | Decided |
| D70 | The Log completeness strip uses icons only, with accessibility labels carrying the names | Decided: words didn't fit on one line |
| D73 | A running campaign can be followed by a queued one, which is how "move its start date" can arise while another is closing | Decided: needed for the closing-soon prompt to make sense |
| D74 | Extending a running campaign never overlaps a queued one: it is refused and the user is sent to move the queued start first | Decided |
| D75 | Editing an upcoming campaign re-copies its weekly goals from the latest ones, replacing the copies it had | Assumption: it has none set by the user yet |
| D76 | Past campaigns are fully read-only, including the label | Decided |
| D71 | Sick tracking is its own opt-in switch (Settings → Health), separate from cycle tracking | Decided |
| D72 | Sick days are yellow dots; sick takes the weigh-in dot's colour over period red when both apply | Assumption |
| D77 | A day's daily goals are met only if a weight was logged, in the Streaks row, the daily-goals streak, the Goals card and campaign reports; with no daily goals set there is nothing to judge | Decided: the user asked |
| D78 | The weekly suggestion uses Apple Intelligence on the device, not a cloud AI, so there is no key, server or data leaving the phone | Decided: the user chose it |
| D79 | The suggestion is on demand, any day, not only on Sunday | Decided: the user asked |
| D80 | Carbs and fat are guidance only: shown and exported, never judged | Decided: the user chose it |
| D81 | The user sees exactly what is shared, and approves before anything is saved | Decided |
| D82 | The on-device model refines a rule-based baseline and its numbers are clamped, because a small model can be wrong | Decided: safety |
| D83 | Weight change for the suggestion is the slope of the weigh-ins over the assessed week and the week before, not the smoothed trend, which lags too much for a single week | Decided |
| D84 | The daily reminder is local, scheduled a week ahead and re-planned on every change, because iOS can't evaluate "goals not met" at delivery | Decided |
| D85 | "Daily goals done" for the reminder includes the weigh-in whenever daily goals exist; with none it uses the required trackers | Decided: matches FR-6 and the required-trackers setting |
