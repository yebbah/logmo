# logmo: Release notes

**Current version: 1.0.0 (build 1)**, built to PRD v15.0, 25 November 2026. This is the first version, installed on the owner's iPhone. Everything below is in it. The version number has not been bumped since the first build, so these notes describe the whole app as it stands; the PRD tags (`prd-v1` to `prd-v14.0`) record how it grew.

---

## What logmo does

logmo is a personal iPhone app to log weight, food, water, steps and a daily check-in, set weekly goals per fitness campaign, and see whether you are on track. Data stays on the phone; there is no account and no network use.

## Features in this version

### Logging
- **Log a day** for any date up to today: weight (kg or lb), calories, protein, carbs and fat, water (with +250 / +500 / +750 / +1,000 quick adds), and steps.
- **Daily check-in:** seven 1–5 ratings (sleep, fatigue, stress, hunger, training performance, appetite, soreness), with the meaning of 1 and 5 shown under each. Training performance can be marked **n/a** on a rest day.
- **Optional cycle tracking** ("Are you on your period today?") and **optional sick tracking** ("Are you sick today?"), each off by default and never counted against compliance.
- **Autosave** with a Saved indicator.
- **Still to log strip:** one icon per required tracker, green with a tick when complete.
- **Goal hints** in the fields (protein, steps and water goals; carbs and fat guides).

### Goals
- **Weekly goals per campaign:** calories (entered per day, judged on the week's average, at or under or at or over), protein, water, steps (daily total or weekly average), workout days a week.
- **Carbs and fat guidance** (never judged).
- **Weekly plan** per campaign: this week first, then the next four weeks to plan ahead, then past weeks (locked). Each week is marked "Set by you" or "Carried over", with changes from the week before highlighted. Same-as-before and repeat options.
- **A weigh-in counts as a daily goal.**

### Progress
- **Dashboard** (follows a campaign filter: current, overall, or any past campaign): campaign card, Goals card (today and this week), recent performance, weigh-ins and trend chart, rate of change, steps and calories, biofeedback bars. Full-screen landscape charts.
- **Weight trend** with adjustable smoothing, optional biofeedback overlay, and red dots for period days and yellow dots for sick days.
- **Streaks tab:** logging, daily-goals and weekly-goals streaks (current and best), compliance, daily goals for the last 7 days, and weekly goals history.
- **Compliance** that counts required trackers fully logged, daily goals met and the week's goals on track.

### Campaigns
- **Cut, bulk or maintenance** campaigns with an optional label, target weight, start date (up to a year ahead) and length in weeks. A default maintenance campaign fills the days between campaigns.
- **Campaigns tab:** the running campaign (weekly plan, rename, extend 1/2/4/8 weeks, end), an upcoming card, and a look back at every campaign (weight change, compliance, averages, weekly goals results).
- **Queue the next campaign** behind the running one; **edit an upcoming campaign's start date and length**; **past campaigns are read-only**.
- **Prompts:** a closing-soon card in the last week of a campaign (extend, or move the next one's start date), a finished-campaign card, and a first-run **Get set up** checklist that also asks you to set up a campaign when none exists.

### Apple Health (read only)
- **Settings → Connections → Apple Health:** connect, and switch on weight, steps, water, food and strength workouts. logmo never writes to Health.
- **Updates** on app start, when the app comes forward, when the Log screen opens, and with **Sync** and **Update now** buttons; steps and food keep updating while the day is open.
- **Typed values win.** Imported fields show a **Health** mark; change or clear one and it is yours (**Use Health's** hands it back). Zero or missing readings are never imported.
- **Strength workouts ask** whether to rate the day or mark it not a lifting day; nothing is rated automatically.
- Imported values count for goals, streaks, compliance, reminders and the weekly suggestion like typed ones.

### Weekly suggestion (Apple Intelligence)
- **Suggest next week**, on demand any day, from the Goals card, the Weekly plan or the plan prompts.
- Shows exactly what the assistant will see (numbers only), lets you assess this week so far or last week, and switch cycle and sick data off for the suggestion.
- logmo **calculates the facts and the decision**: weight trend over up to 21 days, adherence, logging coverage, recovery signals, per-metric **confidence**. Apple Intelligence (iOS 26+, on the phone) can only choose within the supported range and add a short note that passes a check for invented numbers and safety claims. Otherwise a calculated, rule-based suggestion is used.
- **Safety:** small calorie steps, a calorie floor and low-target protection, no harder cut when sick, strained or hungry, steps and lifting never raised automatically.
- You approve before anything is saved: **Use**, **Edit first**, or **Not now**.

### Reminders
- **Weekly plan reminder** at a day and time you choose.
- **Daily log reminder** at a time you choose, sent only on days your daily goals aren't done (scheduled a week ahead and cancelled when the goals are met).

### Your data
- **Local-first,** works offline; no account, no analytics.
- **Full backup and restore** (one JSON file with logs, weekly goals, campaigns and settings).
- **Three CSV exports:** daily logs (with each day's campaign and goals), campaigns, weekly goals.
- **Delete all data** that removes everything and reports any failure.

### Look and feel
- Two themes, **Clean** and **Midnight**, and kg or lb.
- Launch screen and landing screen with the logo, tagline and version (tap to skip).
- App icon, About section with version and a contact-the-developer email.

## Known limits in this version
- Installed on one phone with a free Apple account: it expires every **7 days** and has to be reinstalled (data is kept when reinstalled over the old copy). Save a full backup regularly.
- No cloud sync. Apple Health covers weight, steps, water, food and strength workouts only; sleep, cycle, heart rate and HRV, and body composition are planned. Data exists on one phone.
- The Apple Intelligence step needs iOS 26 or later, a supported iPhone and Apple Intelligence turned on; without it you get the calculated suggestion.
- Daily reminders for days the app isn't opened run for up to a week.
- The "Plan next week" banner on the Weekly plan screen keeps its older, tighter spacing.
- iPhone only; portrait except for full-screen charts.

## How it got here

| PRD | What arrived |
|---|---|
| v1 – v1.3 | Logging a day, weekly goals, streaks, compliance, weight trend; the 1–5 biofeedback ratings and their meanings; CSV export |
| v2 – v2.1 | Macros and steps, three streaks, biofeedback overlay; Clean and Midnight themes; calories judged on the week's average |
| v3 – v3.2 | Fitness campaigns, the campaign filter, days left, selectable history |
| v4 | Dashboard and Streaks tabs, info popovers, full-window compliance, full-screen landscape charts |
| v5 | Weekly goals stored per campaign |
| v6 – v6.1 | Autosave, weekday in the date, workout-day goals, n/a for training performance, calories entered per day |
| v7 – v7.1 | Future campaign starts, daily cycle question with red dots, app icon, version and contact, campaign labels |
| v8 | The Campaigns tab, campaign look-backs |
| v9 | Weekly plan per campaign, plan prompt, locked past weeks, weekly reminder, landing screen |
| v10 | Reliable delete-all, setup checklist, finished-campaign card, full backup, Log completeness strip |
| v11 – v11.1 | Complete exports and backup, neutral streak days before the first log, icon-based Still to log |
| v12 – v12.1 | Sick tracking, campaign changes (extend, queue, edit upcoming), weigh-in as a daily goal |
| v13 – v13.1 | Weekly suggestion with Apple Intelligence, carbs and fat guidance, daily log reminder |
| v14 | Evidence-based suggestions with confidence and safer rules, roomier Goals card and setup prompt |
| v15 | Apple Health: weight, steps, water, food and strength workouts, read only |
